import { describe, it, expect, vi, beforeEach } from "vitest";
import { postRoundSummary } from "./round-summary.js";

vi.mock("node:child_process", () => ({
  execFileSync: vi.fn(),
}));

import { execFileSync } from "node:child_process";

const mockExecFileSync = vi.mocked(execFileSync);

const baseOpts = {
  owner: "acme",
  repo: "widgets",
  prNumber: "42",
  round: 1,
  maxRounds: 3,
  cwd: "/repo",
};

describe("postRoundSummary", () => {
  beforeEach(() => {
    mockExecFileSync.mockReset();
    vi.spyOn(console, "log").mockImplementation(() => {});
    vi.spyOn(console, "warn").mockImplementation(() => {});
  });

  it("posts a comment with round number and results table", () => {
    mockExecFileSync.mockReturnValueOnce("");

    postRoundSummary({
      ...baseOpts,
      results: [
        { body: "Add missing await", score: 85, tier: "auto", action: "fixed" },
        { body: "Restructure the module", score: 30, tier: "hitl", action: "deferred", issueNumber: 99 },
      ],
    });

    const args = mockExecFileSync.mock.calls[0]![1] as string[];
    const bodyIdx = args.indexOf("--body") + 1;
    const body = args[bodyIdx]!;

    expect(body).toContain("Round 1/3");
    expect(body).toContain("Add missing await");
    expect(body).toContain("Fixed ✅");
    expect(body).toContain("Deferred → #99");
    expect(body).toContain("**1** fixed");
    expect(body).toContain("**1** deferred");
  });

  it("includes round cap warning when at max rounds with skipped comments", () => {
    mockExecFileSync.mockReturnValueOnce("");

    postRoundSummary({
      ...baseOpts,
      round: 3,
      maxRounds: 3,
      results: [{ body: "Complex refactor needed", score: 55, tier: "confirm", action: "skipped" }],
    });

    const args = mockExecFileSync.mock.calls[0]![1] as string[];
    const body = args[(args as string[]).indexOf("--body") + 1]!;
    expect(body).toContain("Round cap reached");
    expect(body).toContain("1 unresolved comment(s)");
  });

  it("does not show round cap warning before max rounds", () => {
    mockExecFileSync.mockReturnValueOnce("");

    postRoundSummary({
      ...baseOpts,
      round: 1,
      maxRounds: 3,
      results: [{ body: "Something skipped", score: 55, tier: "confirm", action: "skipped" }],
    });

    const args = mockExecFileSync.mock.calls[0]![1] as string[];
    const body = args[(args as string[]).indexOf("--body") + 1]!;
    expect(body).not.toContain("Round cap reached");
  });

  it("warns on API error without crashing", () => {
    mockExecFileSync.mockImplementationOnce(() => {
      throw new Error("network error");
    });

    postRoundSummary({ ...baseOpts, results: [] });

    expect(console.warn).toHaveBeenCalledWith(expect.stringContaining("Failed to post round summary"));
  });
});
