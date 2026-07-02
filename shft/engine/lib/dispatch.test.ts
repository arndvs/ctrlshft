import { describe, it, expect } from "vitest";
import { resolveWorkflow, WORKFLOW_NAMES } from "./dispatch.js";

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
});
