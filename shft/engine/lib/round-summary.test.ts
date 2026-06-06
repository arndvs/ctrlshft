import { describe, it, expect, vi, beforeEach } from "vitest";
import * as shellHelpers from "./shell-helpers.js";
import { postRoundSummary } from "./round-summary.js";

vi.mock("./shell-helpers.js", () => ({
  sh: vi.fn(),
}));

const mockSh = vi.mocked(shellHelpers.sh);

describe("postRoundSummary", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockSh.mockReturnValue("");
  });

  it("posts a comment with all sections", () => {
    postRoundSummary({
      prNumber: "42",
      round: 1,
      fixed: ["c1", "c2"],
      deferred: ["c3"],
      skipped: ["c4"],
      cwd: "/tmp/repo",
    });

    expect(mockSh).toHaveBeenCalledTimes(1);
    const call = mockSh.mock.calls[0]![0] as { input: string };
    expect(call.input).toContain("Review Round 1 Summary");
    expect(call.input).toContain("Fixed (2)");
    expect(call.input).toContain("Deferred to Issues (1)");
    expect(call.input).toContain("Skipped (1)");
  });

  it("omits empty sections", () => {
    postRoundSummary({
      prNumber: "42",
      round: 2,
      fixed: ["c1"],
      deferred: [],
      skipped: [],
      cwd: "/tmp/repo",
    });

    const call = mockSh.mock.calls[0]![0] as { input: string };
    expect(call.input).toContain("Fixed (1)");
    expect(call.input).not.toContain("Deferred");
    expect(call.input).not.toContain("Skipped");
  });

  it("includes round stats footer", () => {
    postRoundSummary({
      prNumber: "1",
      round: 3,
      fixed: ["a"],
      deferred: ["b"],
      skipped: [],
      cwd: "/tmp/repo",
    });

    const call = mockSh.mock.calls[0]![0] as { input: string };
    expect(call.input).toContain("Round 3: 1/2 fixed, 1 deferred, 0 skipped");
  });
});
