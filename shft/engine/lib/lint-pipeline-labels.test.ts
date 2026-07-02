import { describe, it, expect } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as child_process from "node:child_process";

/**
 * Integration test for the pipeline label linter.
 * Runs the linter against fixture YAML content and verifies it detects
 * violations / passes clean files.
 */

const LINTER_PATH = path.join(import.meta.dirname, "lint-pipeline-labels.ts");
const TSX_CLI_PATH = path.join(
  import.meta.dirname,
  "..",
  "node_modules",
  "tsx",
  "dist",
  "cli.mjs",
);

let fixtureCounter = 0;

function makeFixtureDir(): string {
  fixtureCounter++;
  const dir = path.join(import.meta.dirname, `__fixtures_${fixtureCounter}_${Date.now()}`);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function writeFixture(dir: string, name: string, content: string): string {
  const p = path.join(dir, name);
  fs.writeFileSync(p, content, "utf8");
  return p;
}

function cleanFixtureDir(dir: string): void {
  fs.rmSync(dir, { recursive: true, force: true });
}

function runLinter(dir: string): { code: number; stdout: string; stderr: string } {
  const result = child_process.spawnSync(
    process.execPath,
    [
      TSX_CLI_PATH,
      LINTER_PATH,
      "--workflows-dir",
      dir,
    ],
    {
      cwd: path.resolve(import.meta.dirname, ".."),
      encoding: "utf8",
      timeout: 30_000,
      env: { ...process.env, NODE_NO_WARNINGS: "1" },
    },
  );
  return {
    code: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

describe("lint-pipeline-labels", () => {
  it("passes a valid workflow file", () => {
    const dir = makeFixtureDir();
    writeFixture(
      dir,
      "agent-valid-test.yml",
      `name: "Agent: Test Valid"
on:
  issues:
    types: [labeled]
jobs:
  plan:
    steps:
      - name: Transition labels
        run: |
          gh issue edit "$N" --remove-label "Sandcastle" || true
          gh issue edit "$N" --add-label "agent:in-progress"
          gh issue edit "$N" --add-label "agent:review"
      - name: Cleanup
        run: |
          gh issue edit "$N" --remove-label "agent:in-progress" || true
`,
    );

    const result = runLinter(dir);
    cleanFixtureDir(dir);
    // Should pass — all labels applied to correct object type
    expect(result.stdout).toContain("✅");
    expect(result.code).toBe(0);
  });

  it("fails when an issue-only label is applied to a PR", () => {
    const dir = makeFixtureDir();
    writeFixture(
      dir,
      "agent-invalid-test.yml",
      `name: "Agent: Test Invalid"
on:
  pull_request_target:
    types: [labeled]
jobs:
  bad:
    steps:
      - name: Bad transition
        run: |
          gh pr edit "$N" --add-label "agent:implement"
`,
    );

    const result = runLinter(dir);
    cleanFixtureDir(dir);
    expect(result.stdout).toContain("❌");
    expect(result.stdout).toContain("agent:implement");
    expect(result.code).toBe(1);
  });

  it("fails when a PR-only label is applied to an issue", () => {
    const dir = makeFixtureDir();
    writeFixture(
      dir,
      "agent-pr-on-issue-test.yml",
      `name: "Agent: Test PR on Issue"
on:
  issues:
    types: [labeled]
jobs:
  bad:
    steps:
      - name: Bad transition
        run: |
          gh issue edit "$N" --add-label "agent:fix"
`,
    );

    const result = runLinter(dir);
    cleanFixtureDir(dir);
    expect(result.stdout).toContain("❌");
    expect(result.stdout).toContain("agent:fix");
    expect(result.code).toBe(1);
  });

  it("parses backslash-continued label operations", () => {
    const dir = makeFixtureDir();
    writeFixture(
      dir,
      "agent-multiline-test.yml",
      `name: "Agent: Test Multiline"
on:
  pull_request_target:
    types: [labeled]
jobs:
  bad:
    steps:
      - name: Bad multiline transition
        run: |
          GH_TOKEN="$TOKEN" gh pr edit "$N" \\
            --add-label "agent:implement" \\
            -R example/repo
`,
    );

    const result = runLinter(dir);
    cleanFixtureDir(dir);
    expect(result.stdout).toContain("❌");
    expect(result.stdout).toContain("agent:implement");
    expect(result.stdout).toContain("agent-multiline-test.yml:11");
    expect(result.code).toBe(1);
  });
});
