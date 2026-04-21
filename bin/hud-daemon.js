#!/usr/bin/env node
/**
 * hud-daemon.js — ctrl+shft HUD daemon
 *
 * Zero external dependencies in core path.
 * Optional: better-sqlite3 for persistent history (falls back to in-memory + JSONL)
 *
 * Data sources (in priority order):
 *   1. Named pipe  ~/dotfiles/working/hud.pipe  — real-time from shells
 *   2. JSONL file  ~/dotfiles/working/events.jsonl    — AFK/Docker writes here
 *   3. State file  ~/dotfiles/working/hud-state.json — legacy fallback
 *
 * AFK/Docker note:
 *   afk.sh mounts $CTRL_DIR read-only. working/ is NOT mounted by default.
 *   AFK events reach the daemon via the JSONL file, which requires adding
 *   a working/ read-write mount to afk.sh (see afk.sh patch below).
 *   HITL (once.sh) runs on host — uses named pipe directly.
 *
 * Usage:
 *   node ~/dotfiles/bin/hud-daemon.js
 *   node ~/dotfiles/bin/hud-daemon.js --port 7823 --ws-port 7822 --debug
 *
 * Start/stop:
 *   bash ~/dotfiles/bin/start-hud.sh
 *   bash ~/dotfiles/bin/start-hud.sh --stop
 */

'use strict';

const fs      = require('fs');
const path    = require('path');
const http    = require('http');
const net     = require('net');
const os      = require('os');
const crypto  = require('crypto');
const { execSync } = require('child_process');

// ── Config ────────────────────────────────────────────────────────────────────
const DOTFILES    = process.env.DOTFILES || path.join(os.homedir(), 'dotfiles');
const WORKING     = path.join(DOTFILES, 'working');
const PIPE_PATH   = path.join(WORKING, 'hud.pipe');
const JSONL_PATH  = path.join(WORKING, 'events.jsonl');
const STATE_PATH  = path.join(WORKING, 'hud-state.json');
const LOG_PATH    = path.join(WORKING, 'compliance-log.md');
const DB_PATH     = path.join(WORKING, 'hud.db');
const LOCK_DIR    = path.join(WORKING, '.hud.lock');
const DISMISSED_PATH = path.join(WORKING, '.hud-dismissed.json');

const args = process.argv.slice(2);
const getArg = (flag, def) => {
    const i = args.indexOf(flag);
    return i !== -1 && args[i + 1] ? args[i + 1] : def;
};

const HTTP_PORT = parseInt(getArg('--port', '7823'));
const WS_PORT   = parseInt(getArg('--ws-port', '7822'));
const DEBUG     = args.includes('--debug');

const log  = (...a) => console.log(`[ctrlshft]`, new Date().toLocaleTimeString(), ...a);
const dbg  = (...a) => DEBUG && console.log(`[debug]`, ...a);
const warn = (...a) => console.warn(`[ctrlshft WARN]`, ...a);

// ── Concurrency guard (same mkdir pattern as afk.sh) ──────────────────────────
try {
    fs.mkdirSync(LOCK_DIR);
} catch (e) {
    if (e.code === 'EEXIST') {
        console.error('[ctrlshft] HUD daemon already running. Use --stop to stop it.');
        process.exit(1);
    }
    throw e;
}
process.on('exit', () => { try { fs.rmdirSync(LOCK_DIR); } catch { } });

// ── SQLite setup ──────────────────────────────────────────────────────────────
let db = null;

function initDb() {
    try {
        const Database = require('better-sqlite3');
        db = new Database(DB_PATH);
        db.pragma('journal_mode = WAL');
        db.pragma('synchronous = NORMAL');
        db.exec(`
            CREATE TABLE IF NOT EXISTS events (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id   TEXT NOT NULL,
                project_id   TEXT NOT NULL,
                timestamp    TEXT NOT NULL,
                time_display TEXT,
                type         TEXT NOT NULL,
                message      TEXT NOT NULL,
                ide          TEXT DEFAULT 'unknown',
                source       TEXT DEFAULT 'pipe'
            );
            CREATE TABLE IF NOT EXISTS sessions (
                id           TEXT PRIMARY KEY,
                project_id   TEXT NOT NULL,
                project_path TEXT,
                ide          TEXT DEFAULT 'unknown',
                started_at   TEXT NOT NULL,
                ended_at     TEXT,
                contexts     TEXT,
                source       TEXT DEFAULT 'pipe'
            );
            CREATE TABLE IF NOT EXISTS violations (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id   TEXT NOT NULL,
                project_id   TEXT NOT NULL,
                timestamp    TEXT NOT NULL,
                rule_file    TEXT,
                severity     TEXT DEFAULT 'medium',
                title        TEXT,
                body         TEXT,
                resolved     INTEGER DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS loaded_files (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id   TEXT NOT NULL,
                project_id   TEXT NOT NULL,
                file_name    TEXT NOT NULL,
                file_type    TEXT,
                read_at      TEXT,
                UNIQUE(session_id, file_name)
            );
            CREATE INDEX IF NOT EXISTS idx_events_project   ON events(project_id);
            CREATE INDEX IF NOT EXISTS idx_events_session   ON events(session_id);
            CREATE INDEX IF NOT EXISTS idx_events_type      ON events(type);
            CREATE INDEX IF NOT EXISTS idx_violations_proj  ON violations(project_id);
        `);
        log('SQLite ready:', DB_PATH);
    } catch (e) {
        warn('better-sqlite3 unavailable — run: cd ~/dotfiles && npm install better-sqlite3');
        warn('Using in-memory + JSONL fallback. History will not persist across restarts.');
    }
}

// ── In-memory state ───────────────────────────────────────────────────────────
const sessions     = new Map(); // project_id → session
const eventBuffers = new Map(); // project_id → Event[]  (last 500)
const wsClients    = new Set();
const startedAt      = new Date().toISOString();
let totalEventCount  = 0;
const complianceData = new Map(); // project → { latestRate, violations, history }
const loadedFilesMap = new Map(); // session_id → [{file_name, file_type, read_at}]
const violationsMap  = new Map(); // project_id → [{session_id, timestamp, rule_file, severity, title, body}]

// Dismissed projects — persisted to disk, un-dismissed on new events
const dismissedProjects = new Set();
function loadDismissed() {
    try {
        const data = JSON.parse(fs.readFileSync(DISMISSED_PATH, 'utf8'));
        if (Array.isArray(data)) data.forEach(id => dismissedProjects.add(id));
    } catch { }
}
function saveDismissed() {
    try { fs.writeFileSync(DISMISSED_PATH, JSON.stringify([...dismissedProjects]), 'utf8'); }
    catch (e) { dbg('Save dismissed:', e.message); }
}

// ── IDE detection ─────────────────────────────────────────────────────────────
// Called once per session creation, not on every event
function detectIde() {
    // Check environment variables first (works on all platforms including Windows)
    if (process.env.CURSOR_SESSION_ID) return 'cursor';
    if (process.env.VSCODE_PID || process.env.VSCODE_IPC_HOOK) return 'vscode';
    if (process.platform === 'win32') return 'terminal';
    try {
        const ps = execSync('ps aux 2>/dev/null', { timeout: 1500, encoding: 'utf8' });
        if (/\bCursor\b/.test(ps))      return 'cursor';
        if (/\bCode Helper\b/.test(ps)) return 'vscode';
        if (/\bCode\b/.test(ps))        return 'vscode';
        if (/\bidea\b/i.test(ps))       return 'jetbrains';
        if (/\bwebstorm\b/i.test(ps))   return 'jetbrains';
        if (/\bnvim\b/.test(ps))        return 'neovim';
        if (/\bvim\b/.test(ps))         return 'vim';
    } catch { }
    return 'terminal';
}

// ── Session management ────────────────────────────────────────────────────────
function getOrCreateSession(projectId, projectPath, contexts, source) {
    if (sessions.has(projectId)) {
        const s = sessions.get(projectId);
        if (contexts?.length) s.contexts = contexts;
        // Un-dismiss if new events arrive for a previously dismissed project
        if (dismissedProjects.has(projectId)) {
            dismissedProjects.delete(projectId);
            saveDismissed();
            dbg('Un-dismissed project (existing session):', projectId);
        }
        return s;
    }

    const sessionId = `${projectId}-${Date.now()}`;
    const ide       = source === 'docker' ? 'afk-docker' : detectIde();
    const now       = new Date().toISOString();

    const session = {
        id:           sessionId,
        project_id:   projectId,
        project_path: projectPath || projectId,
        ide,
        started_at:   now,
        contexts:     contexts || ['general'],
        source:       source || 'pipe',
        complianceRate: null,
        violations:   0,
        health:       'healthy',
    };

    sessions.set(projectId, session);
    eventBuffers.set(projectId, []);

    // Un-dismiss if new events arrive for a previously dismissed project
    if (dismissedProjects.has(projectId)) {
        dismissedProjects.delete(projectId);
        saveDismissed();
        dbg('Un-dismissed project:', projectId);
    }

    if (db) {
        try {
            db.prepare(`
                INSERT OR REPLACE INTO sessions
                (id, project_id, project_path, ide, started_at, contexts, source)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            `).run(sessionId, projectId, session.project_path, ide, now,
                   JSON.stringify(session.contexts), source || 'pipe');
        } catch (e) { dbg('Session insert:', e.message); }
    }

    log(`Session: ${sessionId} [${ide}] ${session.project_path}`);
    return session;
}

// ── Event processing ──────────────────────────────────────────────────────────
function processLine(raw, source) {
    const line = raw.trim();
    if (!line) return;

    let event;

    // JSON format (from write_hud_event)
    try {
        event = JSON.parse(line);
    } catch {
        // Plain text formats:

        // "Read path/to/file" — Claude Code stdout
        const readMatch = line.match(/^Read (.+)$/);
        if (readMatch) {
            event = { type: 'read', message: line, project: inferProjectFromCwd() };
        }
        // "TYPE|project|path|contexts|message" — pipe format
        else if (line.includes('|')) {
            const [type, project, projectPath, contexts, ...rest] = line.split('|');
            event = {
                type: type.trim().toLowerCase(),
                project: project.trim(),
                projectPath: projectPath.trim(),
                contexts: contexts.split(',').map(c => c.trim()).filter(Boolean),
                message: rest.join('|').trim(),
            };
        } else {
            dbg('Unparseable:', line.substring(0, 80));
            return;
        }
    }

    if (!event?.type) return;

    const projectId   = event.project || inferProjectFromCwd();
    const projectPath = event.projectPath || event.path || projectId;
    const contexts    = Array.isArray(event.contexts)
        ? event.contexts
        : (event.contexts?.split(',').map(c => c.trim()) || null);

    const session = getOrCreateSession(projectId, projectPath, contexts, source);
    const now     = new Date();

    const stored = {
        session_id:   session.id,
        project_id:   projectId,
        timestamp:    event.timestamp || now.toISOString(),
        time_display: event.time || now.toLocaleTimeString('en-US', { hour12: false }),
        type:         event.type,
        message:      event.message || '',
        ide:          session.ide,
        source:       source || 'pipe',
    };

    // Persist to SQLite
    if (db) {
        try {
            db.prepare(`
                INSERT INTO events
                (session_id, project_id, timestamp, time_display, type, message, ide, source)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            `).run(stored.session_id, stored.project_id, stored.timestamp,
                   stored.time_display, stored.type, stored.message, stored.ide, stored.source);
        } catch (e) { dbg('Event insert:', e.message); }
    }

    // In-memory buffer (last 500 per project)
    const buf = eventBuffers.get(projectId) || [];
    buf.push(stored);
    if (buf.length > 500) buf.shift();
    eventBuffers.set(projectId, buf);
    totalEventCount++;

    // Side effects
    if (event.type === 'read')               handleRead(session, event);
    if (event.type === 'fail')               handleViolation(session, event);
    if (event.type === 'compliance_update')  handleComplianceUpdate(session, event);
    if (event.type === 'compliance-result')  handleComplianceResult(session, event);
    if (event.type === 'context')            handleContext(session, event);

    // Broadcast
    broadcast({ type: 'event', projectId, sessionId: session.id, event: stored,
                session: publicSession(session) });
}

function handleRead(session, event) {
    let filename = event.message.replace(/^Read\s+/, '').trim();
    let fileType = 'file';
    if (filename.includes('instructions/') || filename.endsWith('.instructions.md')) fileType = 'instruction';
    if (filename.includes('skills/')) fileType = 'skill';
    if (filename.includes('rules/'))  fileType = 'rule';
    if (filename.includes('agents/')) fileType = 'agent';

    // Normalize to inventory-canonical names (skills/foo not skills/foo/SKILL.md)
    filename = filename.replace(/\/SKILL\.md$/, '');

    const readAt = event.time || new Date().toLocaleTimeString('en-US', { hour12: false });

    if (db) {
        try {
            db.prepare(`
                INSERT OR IGNORE INTO loaded_files
                (session_id, project_id, file_name, file_type, read_at)
                VALUES (?, ?, ?, ?, ?)
            `).run(session.id, session.project_id, filename, fileType, readAt);
        } catch (e) { dbg('Loaded file:', e.message); }
    }

    // In-memory fallback (always runs so getLoadedFiles works without SQLite)
    const arr = loadedFilesMap.get(session.id) || [];
    if (!arr.some(f => f.file_name === filename)) {
        arr.push({ session_id: session.id, project_id: session.project_id, file_name: filename, file_type: fileType, read_at: readAt });
        loadedFilesMap.set(session.id, arr);
    }
}

function handleViolation(session, event) {
    session.violations = (session.violations || 0) + 1;
    session.health     = session.violations >= 3 ? 'error' : 'warning';

    // Parse: "VIOLATION — rule_file — title — severity"
    const parts    = event.message.replace(/^VIOLATION\s*—\s*/i, '').split(/\s*—\s*/);
    const ruleFile = parts[0] || 'unknown';
    const title    = parts[1] || event.message;
    const severity = parts[2] || 'medium';

    const ts = new Date().toISOString();

    if (db) {
        try {
            db.prepare(`
                INSERT INTO violations
                (session_id, project_id, timestamp, rule_file, severity, title, body)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            `).run(session.id, session.project_id, ts,
                   ruleFile, severity, title, event.message);
        } catch (e) { dbg('Violation insert:', e.message); }
    }

    // In-memory fallback
    const varr = violationsMap.get(session.project_id) || [];
    varr.push({ session_id: session.id, project_id: session.project_id, timestamp: ts, rule_file: ruleFile, severity, title, body: event.message });
    if (varr.length > 100) varr.shift();
    violationsMap.set(session.project_id, varr);
}

function handleComplianceUpdate(session, event) {
    const data = event.data || {};
    if (data.rate !== undefined) {
        const prev = session.complianceRate;
        // Rolling 70/30 average
        session.complianceRate = prev === null
            ? data.rate
            : Math.round(0.7 * prev + 0.3 * data.rate);
    }
    if (data.fail !== undefined) {
        session.violations = data.fail;
        session.health = data.fail === 0 ? 'healthy' : data.fail < 3 ? 'warning' : 'error';
    }
    updateComplianceData(session.project_id, session.complianceRate, event);
}

function handleComplianceResult(session, event) {
    const passCount = Number(event.passCount) || 0;
    const failCount = Number(event.failCount) || 0;
    const warnCount = Number(event.warnCount) || 0;
    const total = passCount + failCount + warnCount;
    const rate = total > 0 ? Math.round((passCount / total) * 100) : 0;

    session.complianceRate = rate;
    session.violations = failCount;
    session.health = failCount === 0 ? 'healthy' : failCount < 3 ? 'warning' : 'error';
    updateComplianceData(session.project_id, rate, event);
}

function updateComplianceData(projectId, rate, event) {
    if (!complianceData.has(projectId)) {
        complianceData.set(projectId, { latestRate: 0, violations: [], history: [] });
    }
    const comp = complianceData.get(projectId);
    comp.latestRate = rate;
    comp.history.push(rate);
    if (comp.history.length > 30) comp.history.shift();

    if (event.violations) {
        try {
            const vList = typeof event.violations === 'string' ? JSON.parse(event.violations) : event.violations;
            if (Array.isArray(vList)) {
                comp.violations = vList.map(v => ({
                    title: String(v.title || ''),
                    rule: String(v.rule || ''),
                    severity: String(v.severity || 'medium'),
                    file: String(v.file || ''),
                    body: String(v.body || ''),
                    timestamp: event.timestamp || new Date().toISOString(),
                }));
            }
        } catch { /* invalid violations JSON */ }
    }
}

function handleContext(session, event) {
    const match = event.message.match(/Active contexts:\s*(.+)/i)
                || event.message.match(/ACTIVE_CONTEXTS=(.+)/i);
    if (match) {
        session.contexts = match[1].split(',').map(c => c.trim()).filter(Boolean);
        if (db) {
            try {
                db.prepare('UPDATE sessions SET contexts = ? WHERE id = ?')
                  .run(JSON.stringify(session.contexts), session.id);
            } catch { }
        }
    }
}

function inferProjectFromCwd() {
    try { return path.basename(process.cwd()); } catch { return 'unknown'; }
}

function publicSession(s) {
    return {
        ...s,
        loadedFiles:  getLoadedFiles(s.id),
        recentEvents: eventBuffers.get(s.project_id)?.slice(-20) || [],
    };
}

function getLoadedFiles(sessionId) {
    if (db) {
        try {
            return db.prepare('SELECT * FROM loaded_files WHERE session_id = ? ORDER BY id')
                     .all(sessionId);
        } catch { }
    }
    // In-memory fallback
    return loadedFilesMap.get(sessionId) || [];
}

function getAllProjectsPublic() {
    const out = [];
    sessions.forEach((s, projectId) => {
        out.push({
            ...publicSession(s),
            eventCount: eventBuffers.get(projectId)?.length || 0,
        });
    });
    return out;
}

// ── Named pipe listener ───────────────────────────────────────────────────────
function startPipeListener() {
    // Create FIFO if it doesn't exist (Linux/macOS only)
    try {
        if (!fs.existsSync(PIPE_PATH)) {
            const { execSync: ex } = require('child_process');
            ex(`mkfifo "${PIPE_PATH}"`, { stdio: 'ignore' });
            log('Created pipe:', PIPE_PATH);
        }
    } catch (e) {
        warn('Could not create named pipe:', e.message, '— Windows or permission issue');
        warn('Shell events will fall back to HTTP POST or JSONL file');
        return;
    }

    let buf = '';

    function openPipe() {
        try {
            const fd     = fs.openSync(PIPE_PATH, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
            const socket = new net.Socket({ fd, readable: true, writable: false });

            socket.on('data', chunk => {
                buf += chunk.toString();
                const lines = buf.split('\n');
                buf = lines.pop();
                lines.forEach(l => { if (l.trim()) processLine(l, 'pipe'); });
            });

            socket.on('end',   () => { socket.destroy(); setTimeout(openPipe, 50); });
            socket.on('error', () => { socket.destroy(); setTimeout(openPipe, 500); });
        } catch {
            setTimeout(openPipe, 1000);
        }
    }

    openPipe();
    log('Pipe listener:', PIPE_PATH);
}

// ── JSONL file watcher (AFK/Docker events land here) ─────────────────────────
function startJsonlWatcher() {
    let lastSize = 0;
    let lastStateMtime = 0;

    // Read any existing content first
    try {
        const content = fs.readFileSync(JSONL_PATH, 'utf8');
        const lines   = content.split('\n').filter(Boolean);
        lines.forEach(l => processLine(l, 'jsonl'));
        lastSize = content.length;
    } catch { /* file doesn't exist yet */ }

    setInterval(() => {
        // Watch JSONL for new lines (AFK Docker events)
        try {
            const stat = fs.statSync(JSONL_PATH);
            if (stat.size < lastSize) {
                warn('JSONL file truncated — resetting read offset from', lastSize, 'to 0');
                lastSize = 0;
            }
            if (stat.size > lastSize) {
                const fd  = fs.openSync(JSONL_PATH, 'r');
                const buf = Buffer.alloc(stat.size - lastSize);
                fs.readSync(fd, buf, 0, buf.length, lastSize);
                fs.closeSync(fd);
                lastSize = stat.size;

                buf.toString('utf8').split('\n').filter(Boolean)
                   .forEach(l => processLine(l, 'jsonl'));
            }
        } catch { }

        // Also watch hud-state.json (legacy / write-hud-state.sh fallback)
        try {
            const stat = fs.statSync(STATE_PATH);
            if (stat.mtimeMs > lastStateMtime) {
                lastStateMtime = stat.mtimeMs;
                const state = JSON.parse(fs.readFileSync(STATE_PATH, 'utf8'));
                reconcileStateFile(state);
            }
        } catch { }
    }, 1500);

    log('JSONL watcher:', JSONL_PATH);
}

function reconcileStateFile(state) {
    if (!state.projects) return;
    Object.entries(state.projects).forEach(([projectId, proj]) => {
        if (!sessions.has(projectId)) {
            getOrCreateSession(projectId, proj.path, proj.contexts, 'state-file');
        }
        // Merge sessionLog entries not yet in eventBuffers
        const log = state.sessionLog?.[projectId] || [];
        const buf = eventBuffers.get(projectId) || [];
        if (log.length > buf.length) {
            log.slice(buf.length).forEach(e => {
                const stored = { ...e, session_id: sessions.get(projectId)?.id, project_id: projectId, source: 'state-file' };
                buf.push(stored);
                broadcast({ type: 'event', projectId, event: stored });
            });
            eventBuffers.set(projectId, buf.slice(-500));
        }
    });
}

// ── WebSocket (minimal, no external dep) ─────────────────────────────────────
function startWsServer() {
    const server = http.createServer();

    server.on('upgrade', (req, socket) => {
        const key = req.headers['sec-websocket-key'];
        if (!key) { socket.destroy(); return; }

        const accept = crypto
            .createHash('sha1')
            .update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
            .digest('base64');

        socket.write(
            'HTTP/1.1 101 Switching Protocols\r\n' +
            'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
            `Sec-WebSocket-Accept: ${accept}\r\n\r\n`
        );

        wsClients.add(socket);
        socket.on('error', () => wsClients.delete(socket));
        socket.on('close', () => wsClients.delete(socket));
        socket.on('data', (data) => {
            // Minimal frame handler: detect close (0x8) and ping (0x9) opcodes
            if (data.length < 2) return;
            const opcode = data[0] & 0x0f;
            if (opcode === 0x8) { socket.destroy(); return; }
            if (opcode === 0x9) {
                // Respond to ping with pong (opcode 0xA), echo payload
                const pong = Buffer.from(data);
                pong[0] = (pong[0] & 0xf0) | 0x0a;
                try { socket.write(pong); } catch { wsClients.delete(socket); }
            }
        });

        // Send initial state
        wsFrame(socket, JSON.stringify({
            type:     'init',
            projects: getAllProjectsPublic(),
            wsPort:   WS_PORT,
        }));
    });

    server.listen(WS_PORT, '127.0.0.1', () => log('WebSocket: ws://localhost:' + WS_PORT));
    server.on('error', e => e.code === 'EADDRINUSE'
        ? warn(`WS port ${WS_PORT} in use`) : warn('WS error:', e.message));
}

function wsFrame(socket, data) {
    try {
        const payload = Buffer.from(data, 'utf8');
        const len     = payload.length;
        const header  = len < 126 ? Buffer.from([0x81, len])
            : len < 65536         ? (() => { const h = Buffer.alloc(4); h[0]=0x81; h[1]=126; h.writeUInt16BE(len,2); return h; })()
                                  : (() => { const h = Buffer.alloc(10); h[0]=0x81; h[1]=127; h.writeBigUInt64BE(BigInt(len),2); return h; })();
        socket.write(Buffer.concat([header, payload]));
    } catch { wsClients.delete(socket); }
}

function broadcast(data) {
    if (!wsClients.size) return;
    const msg = JSON.stringify(data);
    wsClients.forEach(s => wsFrame(s, msg));
}

// ── File inventory — scans repo for all trackable files ───────────────────────
let fileInventory = null;

function scanFileInventory() {
    const inventory = [];

    const scan = (dir, type) => {
        try {
            const entries = fs.readdirSync(path.join(DOTFILES, dir));
            for (const e of entries) {
                if (e === 'README.md') continue;
                // Recurse into underscore folders (_local, _vendor)
                if (e.startsWith('_')) {
                    scan(dir + '/' + e, type);
                    continue;
                }
                const full = path.join(DOTFILES, dir, e);
                if (type === 'skill') {
                    const skill = path.join(full, 'SKILL.md');
                    try { fs.statSync(skill); inventory.push({ name: dir + '/' + e, type }); } catch { }
                } else {
                    if (e.endsWith('.md')) inventory.push({ name: dir + '/' + e, type });
                }
            }
        } catch { }
    };

    // Always-loaded
    inventory.push({ name: 'global.instructions.md', type: 'instruction' });

    scan('instructions', 'instruction');
    scan('rules', 'rule');
    scan('skills', 'skill');

    // Agents
    try {
        const entries = fs.readdirSync(path.join(DOTFILES, 'agents'));
        for (const e of entries) {
            if (e === 'README.md') continue;
            if (e.endsWith('.md')) inventory.push({ name: 'agents/' + e.replace('.md', ''), type: 'agent' });
        }
    } catch { }

    fileInventory = inventory;
    log('File inventory:', inventory.length, 'trackable files');
}

// ── HTTP server ───────────────────────────────────────────────────────────────
function startHttpServer() {
    const HUD_HTML = path.join(__dirname, '..', 'hud', 'index.html');

    const server = http.createServer((req, res) => {
        const url = new URL(req.url, `http://localhost:${HTTP_PORT}`);
        res.setHeader('Access-Control-Allow-Origin', 'http://localhost:' + HTTP_PORT);
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

        // CORS preflight
        if (req.method === 'OPTIONS') {
            res.writeHead(204);
            res.end();
            return;
        }

        // HUD HTML
        if (url.pathname === '/' || url.pathname === '/hud') {
            try {
                res.writeHead(200, { 'Content-Type': 'text/html' });
                res.end(fs.readFileSync(HUD_HTML, 'utf8'));
            } catch {
                res.writeHead(200, { 'Content-Type': 'text/html' });
                res.end(fallbackHtml());
            }
            return;
        }

        // API routes
        if (url.pathname === '/api/state') {
            res.writeHead(200, { 'Content-Type': 'application/json' });

            // Backward-compatible project list for current UI
            const projectsArray = [];
            sessions.forEach((s, projectId) => {
                if (dismissedProjects.has(projectId)) return;
                const buf = eventBuffers.get(projectId) || [];
                const last = buf[buf.length - 1];
                projectsArray.push({
                    project: projectId,
                    projectPath: s.project_path,
                    contexts: Array.isArray(s.contexts) ? s.contexts.join(',') : (s.contexts || ''),
                    lastEventType: last?.type || '',
                    lastMessage: last?.message || '',
                    lastTimestamp: last?.timestamp || '',
                    ide: s.ide,
                    loadedFiles: getLoadedFiles(s.id),
                });
            });

            // Collect recent events across all projects
            const allEvts = [];
            eventBuffers.forEach((buf, projectId) => {
                buf.slice(-50).forEach(e => allEvts.push({ ...e, project: projectId }));
            });
            allEvts.sort((a, b) => (a.timestamp || '').localeCompare(b.timestamp || ''));

            // Build compliance object keyed by project
            const complianceObj = {};
            complianceData.forEach((data, projectId) => {
                complianceObj[projectId] = data;
            });

            res.end(JSON.stringify({
                startedAt,
                eventCount: totalEventCount,
                projects: projectsArray,
                events: allEvts.slice(-100),
                compliance: complianceObj,
                inventory: fileInventory || [],
                wsPort:   WS_PORT,
                uptime:   process.uptime(),
                db:       !!db,
            }));
            return;
        }

        if (url.pathname.startsWith('/api/events/')) {
            const projectId = decodeURIComponent(url.pathname.split('/')[3]);
            const limit     = Math.min(parseInt(url.searchParams.get('limit') || '200'), 500);
            const events    = db
                ? db.prepare('SELECT * FROM events WHERE project_id=? ORDER BY id DESC LIMIT ?').all(projectId, limit).reverse()
                : (eventBuffers.get(projectId) || []).slice(-limit);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(events));
            return;
        }

        if (url.pathname.startsWith('/api/violations/')) {
            const projectId = decodeURIComponent(url.pathname.split('/')[3]);
            const violations = db
                ? db.prepare('SELECT * FROM violations WHERE project_id=? ORDER BY id DESC LIMIT 100').all(projectId)
                : (violationsMap.get(projectId) || []).slice(-100).reverse();
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(violations));
            return;
        }

        if (url.pathname === '/api/compliance-log') {
            res.writeHead(200, { 'Content-Type': 'text/plain' });
            try { res.end(fs.readFileSync(LOG_PATH, 'utf8')); }
            catch { res.end('No compliance log yet.\nRun /compliance-audit after a task.'); }
            return;
        }

        // DELETE /api/projects/:id — dismiss a project from the HUD
        if (req.method === 'DELETE' && url.pathname.startsWith('/api/projects/')) {
            const projectId = decodeURIComponent(url.pathname.split('/')[3]);
            dismissedProjects.add(projectId);
            saveDismissed();
            log('Dismissed project:', projectId);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true, dismissed: projectId }));
            return;
        }

        // POST /api/event — HTTP fallback for shells without pipe access
        if (req.method === 'POST' && url.pathname === '/api/event') {
            let body = '';
            let aborted = false;
            req.on('data', c => {
                body += c;
                if (body.length > 65536) {
                    aborted = true;
                    res.writeHead(413, { 'Content-Type': 'application/json' });
                    res.end('{"ok":false,"error":"Payload too large"}');
                    req.destroy();
                }
            });
            req.on('end', () => {
                if (aborted) return;
                try {
                    processLine(body.trim(), 'http');
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end('{"ok":true}');
                } catch (e) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ ok: false, error: e.message }));
                }
            });
            return;
        }

        res.writeHead(404);
        res.end('Not found');
    });

    server.listen(HTTP_PORT, '127.0.0.1', () => log('HUD: http://localhost:' + HTTP_PORT));
    server.on('error', e => e.code === 'EADDRINUSE'
        ? warn(`Port ${HTTP_PORT} in use — is the HUD already running?`)
        : warn('HTTP error:', e.message));
}

function fallbackHtml() {
    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><title>ctrl+shft</title>
<style>body{background:#080808;color:#fff;font-family:monospace;padding:4rem}
h1{color:#e8ff47}p{color:#9f9fa9}code{color:#e8ff47}</style></head><body>
<h1>ctrl+shft HUD</h1>
<p>Daemon is running. Place <code>hud/index.html</code> in the <code>hud/</code> folder for the full HUD.</p>
<p>API: <code><a href="/api/state" style="color:#e8ff47">/api/state</a></code></p>
<p>WebSocket: <code>ws://localhost:${WS_PORT}</code></p>
<script>
const ws = new WebSocket('ws://localhost:${WS_PORT}');
ws.onopen = () => { document.body.innerHTML += '<p style="color:#44ff88">WebSocket connected</p>'; };
ws.onmessage = e => { const d=JSON.parse(e.data); if(d.type==='event') console.log(d.event.type, d.event.message); };
</script></body></html>`;
}

// ── Heartbeat ─────────────────────────────────────────────────────────────────
setInterval(() => {
    broadcast({ type: 'heartbeat', uptime: process.uptime(), sessions: sessions.size, clients: wsClients.size });
    dbg(`heartbeat — sessions:${sessions.size} clients:${wsClients.size} uptime:${Math.round(process.uptime())}s`);
}, 30000);

// ── Shutdown ──────────────────────────────────────────────────────────────────
function shutdown(sig) {
    log('Shutdown:', sig);
    if (db) {
        try { db.prepare("UPDATE sessions SET ended_at=?, status='ended' WHERE ended_at IS NULL")
                .run(new Date().toISOString()); } catch { }
        db.close();
    }
    wsClients.forEach(s => s.destroy());
    try { fs.rmdirSync(LOCK_DIR); } catch { }
    process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));
process.on('uncaughtException', err => { warn('Uncaught:', err.message); dbg(err.stack); });
process.on('unhandledRejection', err => { warn('Unhandled rejection:', err); });

// ── Boot ──────────────────────────────────────────────────────────────────────
fs.mkdirSync(WORKING, { recursive: true });

log('ctrl+shft compliance daemon starting');
log('Dotfiles:', DOTFILES);

initDb();
loadDismissed();
scanFileInventory();
startPipeListener();
startJsonlWatcher();
startHttpServer();
startWsServer();

log('Ready.');
log('  HUD  →  http://localhost:' + HTTP_PORT);
log('  WebSocket  →  ws://localhost:' + WS_PORT);
log('  Pipe       →  ' + PIPE_PATH);
log('  JSONL      →  ' + JSONL_PATH);
