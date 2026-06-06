import { describe, it, expect, beforeEach } from "vitest";
import { registerWorkflow, getWorkflow, listWorkflows, dispatch, clearRegistry } from "./dispatch.js";
import type { DispatchContext } from "./types.js";

describe("dispatch", () => {
  beforeEach(() => {
    clearRegistry();
  });

  it("registers and retrieves a workflow", () => {
    const runner = async () => {};
    registerWorkflow("test-wf", runner);
    expect(getWorkflow("test-wf")).toBe(runner);
  });

  it("throws on duplicate registration", () => {
    registerWorkflow("dupe", async () => {});
    expect(() => registerWorkflow("dupe", async () => {})).toThrow("Workflow already registered: dupe");
  });

  it("throws on unknown workflow", () => {
    registerWorkflow("known", async () => {});
    expect(() => getWorkflow("unknown")).toThrow(/Unknown workflow: unknown/);
    expect(() => getWorkflow("unknown")).toThrow(/Available: known/);
  });

  it("lists registered workflows sorted", () => {
    registerWorkflow("zebra", async () => {});
    registerWorkflow("alpha", async () => {});
    registerWorkflow("middle", async () => {});
    expect(listWorkflows()).toEqual(["alpha", "middle", "zebra"]);
  });

  it("dispatches to the correct runner", async () => {
    let calledWith: DispatchContext | null = null;
    registerWorkflow("my-wf", async (ctx) => { calledWith = ctx; });

    const ctx: DispatchContext = {
      workflow: "my-wf",
      repoDir: "/tmp/test",
      model: "test-model",
      promptsDir: "/tmp/prompts",
      args: { issue: "42" },
    };

    await dispatch(ctx);
    expect(calledWith).toEqual(ctx);
  });

  it("clearRegistry removes all workflows", () => {
    registerWorkflow("a", async () => {});
    clearRegistry();
    expect(listWorkflows()).toEqual([]);
  });
});
