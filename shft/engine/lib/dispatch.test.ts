import { afterEach, beforeEach, describe, it, expect, vi } from "vitest";
import { StructuredOutputError } from "@ai-hero/sandcastle";
import { resolveWorkflow, WORKFLOW_NAMES } from "./dispatch.js";

vi.mock("../workflows/review-issue.js", () => ({
  runReviewIssue: vi.fn(),
}));

import { runReviewIssue } from "../workflows/review-issue.js";

const mockRunReviewIssue = vi.mocked(runReviewIssue);

beforeEach(() => {
  mockRunReviewIssue.mockReset();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("resolveWorkflow", () => {
  it("returns a runner for each known workflow name", () => {
    for (const name of WORKFLOW_NAMES) {
      expect(resolveWorkflow(name)).toBeDefined();
    }
  });

  it("returns undefined for unknown workflow", () => {
    expect(resolveWorkflow("nonexistent")).toBeUndefined();
  });

  it("includes all expected workflow names", () => {
    expect(WORKFLOW_NAMES).toContain("review-issue");
    expect(WORKFLOW_NAMES).toContain("plan-issue");
    expect(WORKFLOW_NAMES).toContain("implement-issue");
    expect(WORKFLOW_NAMES).toContain("fix-pr-feedback");
    expect(WORKFLOW_NAMES).toContain("address-review");
    expect(WORKFLOW_NAMES).toContain("merge-pr");
    expect(WORKFLOW_NAMES).toContain("architecture-review");
    expect(WORKFLOW_NAMES).toContain("check-stale-prs");
  });

  it("wraps resolved runners with StructuredOutputError diagnostics", async () => {
    const runner = resolveWorkflow("review-issue");
    expect(runner).toBeDefined();

    const error = new StructuredOutputError("bad output", {
      tag: "output",
      rawMatched: "{ nope",
      cause: new Error("invalid json"),
      commits: [],
      branch: "feat/test",
      sessionId: "sess-dispatch",
    });
    mockRunReviewIssue.mockRejectedValueOnce(error);
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    const originalExitCode = process.exitCode;

    try {
      await runner!({ args: { issue: "1" } as never, repoDir: "/repo", templatesDir: "/templates" });

      expect(process.exitCode).toBe(1);
      expect(consoleError).toHaveBeenCalledWith("[review-issue] Failed: malformed agent output");
      expect(consoleError).toHaveBeenCalledWith("[review-issue] Tag: <output>");
      expect(consoleError).toHaveBeenCalledWith("[review-issue] Raw matched: { nope");
    } finally {
      consoleError.mockRestore();
      process.exitCode = originalExitCode;
    }
  });
});
