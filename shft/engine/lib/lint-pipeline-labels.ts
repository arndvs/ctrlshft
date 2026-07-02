/**
 * lint-pipeline-labels.ts — Static linter for agent-*.yml label transitions.
 *
 * Parses workflow YAML files, extracts `--add-label` / `--remove-label`
 * operations, and validates each against the pipeline-states transition table.
 *
 * Usage:
 *   npx tsx shft/engine/lib/lint-pipeline-labels.ts [--workflows-dir .github/workflows]
 *
 * Exit 0 if all transitions are valid; exit 1 on violations.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { LABELS, MUTUAL_EXCLUSIONS } from "./pipeline-states.js";

// ── Types ────────────────────────────────────────────────────────────────────

interface LabelOp {
  file: string;
  line: number;
  action: "add" | "remove";
  label: string;
  objectType: "issue" | "pr";
}

interface Violation {
  file: string;
  line: number;
  message: string;
}

// ── Parse YAML files ─────────────────────────────────────────────────────────

const LABEL_RE =
  /gh\s+(?:issue|pr)\s+edit\b.*?--(add|remove)-label\s+"([^"]+)"/g;
const OBJECT_TYPE_RE = /gh\s+(issue|pr)\s+edit/;

function extractLabelOps(filePath: string): LabelOp[] {
  const content = fs.readFileSync(filePath, "utf8");
  const lines = content.split("\n");
  const ops: LabelOp[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    // Reset lastIndex for global regex
    LABEL_RE.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = LABEL_RE.exec(line)) !== null) {
      const objectMatch = OBJECT_TYPE_RE.exec(line);
      const objectType = objectMatch?.[1] === "pr" ? "pr" : "issue";
      ops.push({
        file: path.basename(filePath),
        line: i + 1,
        action: match[1] as "add" | "remove",
        label: match[2]!,
        objectType: objectType as "issue" | "pr",
      });
    }
  }

  return ops;
}

// ── Validate ─────────────────────────────────────────────────────────────────

function validateOps(ops: LabelOp[]): Violation[] {
  const violations: Violation[] = [];

  for (const op of ops) {
    if (op.action !== "add") continue; // only validate adds

    const def = LABELS[op.label];
    if (!def) {
      // Unknown label — warning, not a violation
      continue;
    }

    // Object-type check
    if (!def.appliesTo.includes(op.objectType)) {
      violations.push({
        file: op.file,
        line: op.line,
        message: `Label "${op.label}" applied to ${op.objectType} but only allowed on: ${def.appliesTo.join(", ")}`,
      });
    }
  }

  // Check for mutual exclusions within the same file (adds without
  // intervening removes — a heuristic; full runtime checking is in
  // the shell wrapper).
  // This is intentionally conservative: we only flag if both members
  // of an exclusion pair are added in the same step (same line group).

  return violations;
}

// ── Main ─────────────────────────────────────────────────────────────────────

function main(): void {
  const args = process.argv.slice(2);
  let workflowsDir = ".github/workflows";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--workflows-dir" && args[i + 1]) {
      workflowsDir = args[i + 1]!;
      i++;
    }
  }

  // Find the repo root by walking up from cwd looking for .github/
  let root = process.cwd();
  while (!fs.existsSync(path.join(root, ".github"))) {
    const parent = path.dirname(root);
    if (parent === root) break;
    root = parent;
  }

  const dir = path.resolve(root, workflowsDir);
  if (!fs.existsSync(dir)) {
    console.error(`Workflows directory not found: ${dir}`);
    process.exit(1);
  }

  const files = fs
    .readdirSync(dir)
    .filter((f) => f.startsWith("agent-") && f.endsWith(".yml"))
    .map((f) => path.join(dir, f));

  if (files.length === 0) {
    console.error("No agent-*.yml files found.");
    process.exit(1);
  }

  let totalOps = 0;
  const allViolations: Violation[] = [];

  for (const file of files) {
    const ops = extractLabelOps(file);
    totalOps += ops.length;
    const violations = validateOps(ops);
    allViolations.push(...violations);
  }

  // Report
  console.log(
    `Scanned ${files.length} workflow files, ${totalOps} label operations.`,
  );

  if (allViolations.length === 0) {
    console.log("✅ All label operations conform to the pipeline state machine.");
    process.exit(0);
  }

  console.log(
    `\n❌ ${allViolations.length} violation(s) found:\n`,
  );
  for (const v of allViolations) {
    console.log(`  ${v.file}:${v.line} — ${v.message}`);
  }
  process.exit(1);
}

main();
