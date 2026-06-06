import { describe, it, expect, beforeEach } from "vitest";
import { clearRegistry, listWorkflows, getWorkflow } from "../lib/dispatch.js";
import { registerAllWorkflows } from "./register.js";

describe("registerAllWorkflows", () => {
  beforeEach(() => {
    clearRegistry();
  });

  it("registers all expected workflows", () => {
    registerAllWorkflows();
    const workflows = listWorkflows();

    expect(workflows).toEqual([
      "address-review",
      "architecture-review",
      "implement-issue",
      "implement-pr",
      "implement-prd",
      "parallel",
      "review",
      "review-issue",
      "to-issues-prd",
      "update-branch",
      "write-pr",
    ]);
  });

  it("each registered workflow is a function", () => {
    registerAllWorkflows();
    const workflows = listWorkflows();

    for (const name of workflows) {
      const runner = getWorkflow(name);
      expect(typeof runner).toBe("function");
    }
  });

  it("throws on double registration", () => {
    registerAllWorkflows();
    expect(() => registerAllWorkflows()).toThrow(/Workflow already registered/);
  });
});
