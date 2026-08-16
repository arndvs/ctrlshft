#!/usr/bin/env node
/**
 * repo-hygiene: repo audit
 *
 * Measures structural debt in a codebase. This is the ground truth for phase
 * gating -- never infer progress from the ledger when you can measure it.
 *
 * Stack-aware: detects the stack (astro | static-html | worker-ts | python |
 * generic) and emits the relevant signals. The phase model lives in
 * references/phases-<stack>.md; this script only measures.
 *
 * Usage:
 *   node .refactor/audit.mjs            # human-readable summary
 *   node .refactor/audit.mjs --json     # machine-readable, for the pilot
 */

import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, relative, extname } from "node:path";

const ROOT = process.cwd();
const JSON_OUT = process.argv.includes("--json");

const PAGE_MAX_LINES = 300;
const DUP_MIN_LINES = 15;

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    if (entry === "node_modules" || entry.startsWith(".")) continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

const read = (f) => readFileSync(f, "utf8");
const lineCount = (s) => s.split("\n").length;
// Normalize to forward slashes so path-prefix checks work on Windows.
const rel = (f) => relative(ROOT, f).split("\\").join("/");

// ---------- Stack detection ----------

function detectStack() {
  const has = (p) => existsSync(join(ROOT, p));
  if (has("astro.config.mjs") || has("astro.config.ts") || has("astro.config.js")) {
    return "astro";
  }
  if (has("wrangler.toml") || has("wrangler.jsonc")) {
    // Could be static-html (wrangler pages dev .) or worker-ts. Check for a worker dir.
    if (has("worker") || has("src/workers")) return "worker-ts";
    const topHtml = readdirSync(ROOT).filter((f) => extname(f) === ".html");
    if (topHtml.length > 0) return "static-html";
    return "worker-ts";
  }
  if (has("package.json")) {
    const pkg = read(join(ROOT, "package.json"));
    if (/astro/.test(pkg)) return "astro";
    return "generic";
  }
  const topPy = readdirSync(ROOT).filter((f) => extname(f) === ".py");
  if (topPy.length > 0) return "python";
  return "generic";
}

const STACK = detectStack();

// ---------- Generic file inventory ----------
// Stack-aware: scan the directories where each stack keeps its code. Astro and
// generic use src/; worker-ts may keep code in worker/ or scripts/ at root;
// python may keep code in src/ or a named package dir; static-html scans
// top-level .html files.

function sourceDirs() {
  const dirs = ["src"];
  if (STACK === "worker-ts") {
    for (const d of ["worker", "scripts", "src/workers"]) {
      if (existsSync(join(ROOT, d))) dirs.push(d);
    }
  }
  if (STACK === "python") {
    for (const d of ["src", "scripts"]) {
      if (existsSync(join(ROOT, d))) dirs.push(d);
    }
  }
  return dirs;
}

const allFiles = sourceDirs().flatMap((d) => walk(join(ROOT, d))).concat(
  STACK === "static-html"
    ? readdirSync(ROOT).filter((f) => extname(f) === ".html").map((f) => join(ROOT, f))
    : [],
  STACK === "python"
    ? readdirSync(ROOT).filter((f) => extname(f) === ".py").map((f) => join(ROOT, f))
    : []
);
const relFiles = allFiles.map(rel);

// ---------- Duplicate block detection (all stacks) ----------

const blockIndex = new Map();
for (const f of allFiles) {
  const lines = read(f)
    .split("\n")
    .map((l) => l.trim().replace(/\s+/g, " "))
    .filter((l) => l.length > 0);
  for (let i = 0; i + DUP_MIN_LINES <= lines.length; i++) {
    const key = lines.slice(i, i + DUP_MIN_LINES).join("\n");
    if (key.length < 200) continue;
    if (!blockIndex.has(key)) blockIndex.set(key, new Set());
    blockIndex.get(key).add(rel(f));
  }
}
const duplicateBlocks = [...blockIndex.entries()]
  .filter(([, files]) => files.size >= 2)
  .map(([key, files]) => ({
    files: [...files],
    fileCount: files.size,
    preview: key.split("\n")[0].slice(0, 80),
  }))
  .sort((a, b) => b.fileCount - a.fileCount)
  .slice(0, 20);

// ---------- Largest files (all stacks) ----------

const largestFiles = relFiles
  .map((f) => ({ file: f, lines: lineCount(read(join(ROOT, f))) }))
  .sort((a, b) => b.lines - a.lines);

const oversizedFiles = largestFiles.filter((f) => f.lines > PAGE_MAX_LINES);

// ---------- Astro-specific signals ----------

let astro = null;
if (STACK === "astro") {
  const SRC = join(ROOT, "src");
  const astroFiles = allFiles.filter((f) => extname(f) === ".astro");
  const pages = astroFiles.filter((f) => rel(f).startsWith("src/pages/"));
  const components = astroFiles.filter((f) => rel(f).startsWith("src/components/"));
  const layouts = astroFiles.filter((f) => rel(f).startsWith("src/layouts/"));
  const cssFiles = allFiles.filter((f) => [".css", ".scss"].includes(extname(f)));

  const pagesWithoutLayout = [];
  const pagesWithRawHead = [];
  for (const p of pages) {
    const src = read(p);
    const importsLayout =
      /import\s+\w+\s+from\s+["'][^"']*layouts?\//i.test(src) ||
      /from\s+["']@\/layouts/i.test(src);
    if (!importsLayout) pagesWithoutLayout.push(rel(p));
    if (/<\s*(html|head)[\s>]/i.test(src)) pagesWithRawHead.push(rel(p));
  }

  const componentImporters = {};
  for (const c of components) {
    const name = rel(c).split("/").pop().replace(".astro", "");
    const pattern = new RegExp(`import\\s+${name}\\s+from`, "");
    componentImporters[rel(c)] = astroFiles.filter(
      (f) => f !== c && pattern.test(read(f))
    ).length;
  }
  const importerCounts = Object.values(componentImporters);
  const avgImporters = importerCounts.length
    ? importerCounts.reduce((a, b) => a + b, 0) / importerCounts.length
    : 0;

  let scopedStyleLines = 0;
  let inlineStyleCount = 0;
  for (const f of astroFiles) {
    const src = read(f);
    for (const m of src.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)) {
      scopedStyleLines += lineCount(m[1]);
    }
    inlineStyleCount += (src.match(/\sstyle\s*=\s*["']/g) || []).length;
  }
  const globalCssLines = cssFiles.reduce((n, f) => n + lineCount(read(f)), 0);

  const configFile = ["astro.config.mjs", "astro.config.ts", "astro.config.js"]
    .map((f) => join(ROOT, f))
    .find(existsSync);
  const config = configFile ? read(configFile) : "";
  const tailwindWired = /@tailwindcss\/vite/.test(config);
  const legacyTailwind = /@astrojs\/tailwind/.test(config);
  const hasThemeBlock = cssFiles.some((f) => /@theme\s*\{/.test(read(f)));

  astro = {
    totals: {
      pages: pages.length,
      components: components.length,
      layouts: layouts.length,
      astroFiles: astroFiles.length,
      totalAstroLines: astroFiles.reduce((n, f) => n + lineCount(read(f)), 0),
    },
    phase1_layouts: {
      layoutFiles: layouts.map(rel),
      pagesWithoutLayout,
      pagesWithRawHead,
      layoutAdoptionPct: pages.length
        ? Math.round(((pages.length - pagesWithoutLayout.length) / pages.length) * 100)
        : 100,
    },
    phase2_components: {
      largestPages: largestFiles.filter((f) => f.file.startsWith("src/pages/")).slice(0, 10),
      oversizedPageCount: oversizedFiles.filter((f) => f.file.startsWith("src/pages/")).length,
      pageMaxLines: PAGE_MAX_LINES,
      duplicateBlocks,
      duplicateBlockCount: duplicateBlocks.length,
      componentImporters,
      avgImportersPerComponent: Number(avgImporters.toFixed(2)),
      orphanComponents: Object.entries(componentImporters)
        .filter(([, n]) => n === 0)
        .map(([f]) => f),
    },
    phase3_styling: {
      tailwindWired,
      legacyTailwindIntegration: legacyTailwind,
      hasThemeBlock,
      scopedStyleLines,
      globalCssLines,
      totalCssLines: scopedStyleLines + globalCssLines,
      inlineStyleCount,
    },
  };
}

// ---------- Static-HTML signals ----------

let staticHtml = null;
if (STACK === "static-html") {
  const htmlFiles = allFiles.filter((f) => extname(f) === ".html");
  const withShell = htmlFiles.filter((f) => /<(header|nav|footer)[\s>]/i.test(read(f)));
  staticHtml = {
    htmlFileCount: htmlFiles.length,
    totalHtmlLines: htmlFiles.reduce((n, f) => n + lineCount(read(f)), 0),
    filesWithSharedShell: withShell.map(rel),
    shellAdoptionPct: htmlFiles.length
      ? Math.round((withShell.length / htmlFiles.length) * 100)
      : 100,
    largestFiles: largestFiles.filter((f) => extname(f.file) === ".html").slice(0, 10),
    duplicateBlocks,
    duplicateBlockCount: duplicateBlocks.length,
  };
}

// ---------- Worker-TS signals ----------

let workerTs = null;
if (STACK === "worker-ts") {
  const tsFiles = allFiles.filter((f) => [".ts", ".tsx"].includes(extname(f)));
  workerTs = {
    tsFileCount: tsFiles.length,
    totalTsLines: tsFiles.reduce((n, f) => n + lineCount(read(f)), 0),
    largestFiles: largestFiles.filter((f) => [".ts", ".tsx"].includes(extname(f.file))).slice(0, 10),
    duplicateBlocks,
    duplicateBlockCount: duplicateBlocks.length,
  };
}

// ---------- Python signals ----------

let python = null;
if (STACK === "python") {
  const pyFiles = allFiles.filter((f) => extname(f) === ".py");
  python = {
    pyFileCount: pyFiles.length,
    totalPyLines: pyFiles.reduce((n, f) => n + lineCount(read(f)), 0),
    largestFiles: largestFiles.filter((f) => extname(f.file) === ".py").slice(0, 10),
    duplicateBlocks,
    duplicateBlockCount: duplicateBlocks.length,
  };
}

// ---------- Assemble ----------

const report = {
  generatedAt: new Date().toISOString(),
  stack: STACK,
  totals: {
    files: relFiles.length,
    totalLines: relFiles.reduce((n, f) => n + lineCount(read(join(ROOT, f))), 0),
    oversizedFileCount: oversizedFiles.length,
    pageMaxLines: PAGE_MAX_LINES,
  },
  largestFiles: largestFiles.slice(0, 10),
  duplicateBlocks,
  duplicateBlockCount: duplicateBlocks.length,
  astro,
  staticHtml,
  workerTs,
  python,
};

if (JSON_OUT) {
  console.log(JSON.stringify(report, null, 2));
} else {
  console.log(`\nRepo hygiene audit — stack: ${STACK}`);
  console.log(`  ${report.totals.files} files, ${report.totals.totalLines} lines, ${report.totals.oversizedFileCount} over ${PAGE_MAX_LINES} lines`);
  console.log(`  ${report.duplicateBlockCount} duplicated blocks (>=${DUP_MIN_LINES} lines, >=2 files)`);

  if (astro) {
    const { totals: t, phase1_layouts: p1, phase2_components: p2, phase3_styling: p3 } = astro;
    console.log(`\nAstro: ${t.pages} pages, ${t.components} components, ${t.layouts} layouts, ${t.totalAstroLines} lines`);
    console.log(`  P1 layout adoption ${p1.layoutAdoptionPct}% (${p1.pagesWithoutLayout.length} without, ${p1.pagesWithRawHead.length} raw <head>)`);
    console.log(`  P2 oversized pages ${p2.oversizedPageCount}, avg component reuse ${p2.avgImportersPerComponent} (${p2.orphanComponents.length} orphans)`);
    console.log(`  P3 tailwind ${p3.tailwindWired ? "wired" : "not wired"}${p3.legacyTailwindIntegration ? " (LEGACY)" : ""}, ${p3.totalCssLines} css lines, ${p3.inlineStyleCount} inline styles`);
  }
  if (staticHtml) {
    console.log(`\nStatic HTML: ${staticHtml.htmlFileCount} files, ${staticHtml.totalHtmlLines} lines, shell adoption ${staticHtml.shellAdoptionPct}%`);
  }
  if (workerTs) {
    console.log(`\nWorker TS: ${workerTs.tsFileCount} files, ${workerTs.totalTsLines} lines`);
  }
  if (python) {
    console.log(`\nPython: ${python.pyFileCount} files, ${python.totalPyLines} lines`);
  }

  if (report.largestFiles.length) {
    console.log(`\nLargest files:`);
    for (const f of report.largestFiles.slice(0, 5)) console.log(`  ${String(f.lines).padStart(5)}  ${f.file}`);
  }
  console.log("");
}
