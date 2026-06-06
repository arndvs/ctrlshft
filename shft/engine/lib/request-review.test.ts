import { describe, it, expect, vi, beforeEach } from "vitest";
import * as shellHelpers from "./shell-helpers.js";
import { requestReview, requestCopilotReview } from "./request-review.js";

vi.mock("./shell-helpers.js", () => ({
  trySh: vi.fn(),
}));

const mockTrySh = vi.mocked(shellHelpers.trySh);

describe("requestReview", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns true on success", () => {
    mockTrySh.mockReturnValue({ stdout: "", ok: true });
    const result = requestReview({ prNumber: "42", reviewer: "octocat", cwd: "/tmp/repo" });
    expect(result).toBe(true);
    expect(mockTrySh).toHaveBeenCalledWith(expect.objectContaining({
      cmd: "gh",
      args: ["pr", "edit", "42", "--add-reviewer", "octocat"],
    }));
  });

  it("returns false on failure", () => {
    mockTrySh.mockReturnValue({ stdout: "", ok: false });
    const result = requestReview({ prNumber: "42", reviewer: "octocat", cwd: "/tmp/repo" });
    expect(result).toBe(false);
  });
});

describe("requestCopilotReview", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("requests copilot as reviewer", () => {
    mockTrySh.mockReturnValue({ stdout: "", ok: true });
    requestCopilotReview({ prNumber: "10", cwd: "/tmp/repo" });
    expect(mockTrySh).toHaveBeenCalledWith(expect.objectContaining({
      args: expect.arrayContaining(["copilot"]),
    }));
  });
});
