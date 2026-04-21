#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const os = require('os');

const DOTFILES = process.env.DOTFILES || path.join(os.homedir(), 'dotfiles');
const WORKING = path.join(DOTFILES, 'working');
const PIPE_PATH = path.join(WORKING, 'dashboard.pipe');
const JSONL_PATH = path.join(WORKING, 'events.jsonl');
const STATE_PATH = path.join(WORKING, 'dashboard-state.json');

const args = process.argv.slice(2);
const argValue = (flag, fallback) => {
  const i = args.indexOf(flag);
  return i !== -1 && args[i + 1] ? args[i + 1] : fallback;
};

const HTTP_PORT = Number.parseInt(argValue('--port', process.env.DASHBOARD_PORT || '7823'), 10);
const MAX_EVENTS = 500;

fs.mkdirSync(WORKING, { recursive: true });

const state = {
  startedAt: new Date().toISOString(),
  eventCount: 0,
  events: [],
  projects: {}
};

const parseJsonLine = (line) => {
  const trimmed = String(line || '').trim();
  if (!trimmed) {
    return null;
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
};

const persistState = () => {
  try {
    fs.writeFileSync(STATE_PATH, JSON.stringify(state, null, 2));
  } catch {
    // Non-fatal by design.
  }
};

const ingestEvent = (event, source) => {
  if (!event || typeof event !== 'object') {
    return;
  }

  const project = event.project || 'unknown';
  const normalized = {
    type: event.type || 'info',
    project,
    projectPath: event.projectPath || project,
    contexts: event.contexts || 'general',
    message: event.message || '',
    timestamp: event.timestamp || new Date().toISOString(),
    time: event.time || new Date().toLocaleTimeString('en-US', { hour12: false }),
    source: source || 'unknown'
  };

  state.eventCount += 1;
  state.events.push(normalized);
  if (state.events.length > MAX_EVENTS) {
    state.events.shift();
  }

  state.projects[project] = {
    project,
    projectPath: normalized.projectPath,
    contexts: normalized.contexts,
    lastEventType: normalized.type,
    lastMessage: normalized.message,
    lastTimestamp: normalized.timestamp
  };

  persistState();
};

const bootstrapFromJsonl = () => {
  try {
    const content = fs.readFileSync(JSONL_PATH, 'utf8');
    content
      .split('\n')
      .map(parseJsonLine)
      .filter(Boolean)
      .forEach((event) => ingestEvent(event, 'jsonl-bootstrap'));
  } catch {
    // File may not exist yet.
  }
};

const watchJsonl = () => {
  let lastSize = 0;
  try {
    lastSize = fs.statSync(JSONL_PATH).size;
  } catch {
    lastSize = 0;
  }

  setInterval(() => {
    let stat;
    try {
      stat = fs.statSync(JSONL_PATH);
    } catch {
      return;
    }

    if (stat.size <= lastSize) {
      return;
    }

    const readLength = stat.size - lastSize;
    const fd = fs.openSync(JSONL_PATH, 'r');
    const buf = Buffer.alloc(readLength);
    fs.readSync(fd, buf, 0, readLength, lastSize);
    fs.closeSync(fd);
    lastSize = stat.size;

    buf
      .toString('utf8')
      .split('\n')
      .map(parseJsonLine)
      .filter(Boolean)
      .forEach((event) => ingestEvent(event, 'jsonl-watch'));
  }, 1000);
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${HTTP_PORT}`);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method === 'GET' && (url.pathname === '/healthz' || url.pathname === '/api/healthz')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, uptime: process.uptime() }));
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/state') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      startedAt: state.startedAt,
      eventCount: state.eventCount,
      projects: Object.values(state.projects),
      events: state.events.slice(-100)
    }));
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/event') {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      const event = parseJsonLine(body);
      if (!event) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'invalid json payload' }));
        return;
      }

      ingestEvent(event, 'http');

      try {
        fs.appendFileSync(JSONL_PATH, `${JSON.stringify(event)}\n`);
      } catch {
        // Non-fatal append failure.
      }

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ ok: false, error: 'not found' }));
});

bootstrapFromJsonl();
watchJsonl();
persistState();

server.listen(HTTP_PORT, '127.0.0.1', () => {
  console.log(`[ctrlshft] dashboard daemon listening on http://localhost:${HTTP_PORT}`);
});
