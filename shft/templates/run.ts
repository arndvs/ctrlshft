/**
 * run.ts — Vendored Sandcastle dispatcher entrypoint.
 *
 * This file is copied into .sandcastle/ of adopter repos by init-sandcastle.
 * It delegates to the engine's main.ts, passing the repo root as --repo.
 *
 * Usage (from GitHub Actions or locally):
 *   npx tsx .sandcastle/run.ts --workflow implement-issue --issue 42
 */

import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// The engine is installed as a dependency in .sandcastle/node_modules/
// or lives alongside this file. Resolve relative to this file's location.
const engineMain = path.join(__dirname, "node_modules", ".sandcastle-engine", "main.ts");

// Forward all CLI args to the engine, injecting --repo as the parent directory
const repoDir = path.resolve(__dirname, "..");
const args = ["--repo", repoDir, ...process.argv.slice(2)];

try {
  execFileSync("npx", ["tsx", engineMain, ...args], {
    cwd: repoDir,
    stdio: "inherit",
    env: { ...process.env },
  });
} catch (error: unknown) {
  const exitCode = (error as { status?: number }).status ?? 1;
  process.exit(exitCode);
}
