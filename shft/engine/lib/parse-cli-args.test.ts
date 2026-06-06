import { describe, it, expect } from "vitest";
import { parseCliArgs } from "./parse-cli-args.js";

describe("parseCliArgs", () => {
  it("parses required --repo", () => {
    const args = parseCliArgs(["--repo", "/tmp/test"]);
    expect(args.repo).toBe("/tmp/test");
  });

  it("throws without --repo", () => {
    expect(() => parseCliArgs([])).toThrow("--repo is required");
  });

  it("parses all options", () => {
    const args = parseCliArgs([
      "--repo", "/tmp/test",
      "--workflow", "review",
      "--pr", "42",
      "--issue", "10",
      "--branch", "feature/x",
      "--max-iterations", "3",
      "--max-parallel", "2",
      "--max-issues", "10",
      "--dry-run",
      "--model", "claude-opus-4-7",
      "--prompts-dir", "/tmp/prompts",
    ]);

    expect(args.workflow).toBe("review");
    expect(args.pr).toBe("42");
    expect(args.issue).toBe("10");
    expect(args.branch).toBe("feature/x");
    expect(args.maxIterations).toBe(3);
    expect(args.maxParallel).toBe(2);
    expect(args.maxIssues).toBe(10);
    expect(args.dryRun).toBe(true);
    expect(args.model).toBe("claude-opus-4-7");
    expect(args.promptsDir).toBe("/tmp/prompts");
  });

  it("uses defaults when options not provided", () => {
    const args = parseCliArgs(["--repo", "/tmp/test"]);
    expect(args.workflow).toBe("implement");
    expect(args.maxIterations).toBe(1);
    expect(args.maxParallel).toBe(4);
    expect(args.maxIssues).toBe(5);
    expect(args.dryRun).toBe(false);
  });

  it("throws on invalid --max-iterations", () => {
    expect(() => parseCliArgs(["--repo", "/tmp/test", "--max-iterations", "abc"])).toThrow(/--max-iterations must be a positive integer/);
  });

  it("throws on zero --max-parallel", () => {
    expect(() => parseCliArgs(["--repo", "/tmp/test", "--max-parallel", "0"])).toThrow(/--max-parallel must be a positive integer/);
  });

  it("throws on invalid --workflow characters", () => {
    expect(() => parseCliArgs(["--repo", "/tmp/test", "--workflow", "../escape"])).toThrow(/Invalid --workflow/);
  });
});
