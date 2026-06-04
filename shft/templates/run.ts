#!/usr/bin/env tsx
/**
 * Sandcastle dispatcher — single entry point for all workflow runners.
 * Workflow YAMLs call: npx tsx .sandcastle/run.ts <workflow-name> [--issue N] [--pr N]
 */

import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseCli } from "./engine/lib/parse-cli-args.js";
import { resolveWorkflow, WORKFLOW_NAMES } from "./engine/lib/dispatch.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoDir = path.resolve(__dirname, "..");
const templatesDir = path.resolve(__dirname, "templates", "prompts");

const args = parseCli(process.argv.slice(2));

const runner = resolveWorkflow(args.workflow);

if (!runner) {
  const available = WORKFLOW_NAMES.join(", ");
  console.error(`Unknown workflow: "${args.workflow}". Available: ${available}`);
  process.exit(1);
}

try {
  await runner({ args, repoDir, templatesDir });
} catch (error) {
  console.error(`[${args.workflow}] Failed:`, error);
  process.exit(1);
}
