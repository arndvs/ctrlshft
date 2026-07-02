import { describe, it, expect, vi, beforeEach } from "vitest";
import { requestCopilotReview } from "./request-review.js";

vi.mock("node:child_process", () => ({
  execFileSync: vi.fn(),
}));

import { execFileSync } from "node:child_process";

const mockExecFileSync = vi.mocked(execFileSync);

const baseOpts = { owner: "acme", repo: "widgets", prNumber: "42", cwd: "/repo" };

describe("requestCopilotReview", () => {
  beforeEach(() => {
    mockExecFileSync.mockReset();
    vi.spyOn(console, "log").mockImplementation(() => {});
    vi.spyOn(console, "warn").mockImplementation(() => {});
  });

  it("requests review from copilot via gh pr edit", () => {
    mockExecFileSync.mockReturnValueOnce("false"); // draft check
    mockExecFileSync.mockReturnValueOnce(""); // review request

    requestCopilotReview(baseOpts);

    expect(mockExecFileSync).toHaveBeenCalledTimes(2);
    const reviewCall = mockExecFileSync.mock.calls[1]!;
    // Must go through `gh pr edit --add-reviewer` (GraphQL); the REST
    // reviewers[] endpoint 422s the Copilot app and silently no-ops.
    expect(reviewCall[1]).toEqual(
      expect.arrayContaining(["pr", "edit", "--add-reviewer", "copilot-pull-request-reviewer"]),
    );
    expect(reviewCall[1]).not.toContain("requested_reviewers");
    expect(console.log).toHaveBeenCalledWith(expect.stringContaining("Requested Copilot review"));
  });

  it("skips when PR is a draft", () => {
    mockExecFileSync.mockReturnValueOnce("true"); // draft check

    requestCopilotReview(baseOpts);

    expect(mockExecFileSync).toHaveBeenCalledOnce();
    expect(console.log).toHaveBeenCalledWith(expect.stringContaining("draft"));
  });

  it("warns when copilot is not available as reviewer", () => {
    mockExecFileSync.mockReturnValueOnce("false"); // draft check
    mockExecFileSync.mockImplementationOnce(() => {
      throw new Error("422 Reviews may only be requested from collaborators");
    });

    requestCopilotReview(baseOpts);

    expect(console.warn).toHaveBeenCalledWith(expect.stringContaining("not available as reviewer"));
  });

  it("warns on generic API error without crashing", () => {
    mockExecFileSync.mockReturnValueOnce("false"); // draft check
    mockExecFileSync.mockImplementationOnce(() => {
      throw new Error("500 Internal Server Error");
    });

    requestCopilotReview(baseOpts);

    expect(console.warn).toHaveBeenCalledWith(expect.stringContaining("Failed to request"));
  });

  it("continues with review request when draft check fails", () => {
    mockExecFileSync.mockImplementationOnce(() => {
      throw new Error("network error");
    });
    mockExecFileSync.mockReturnValueOnce(""); // review request succeeds

    requestCopilotReview(baseOpts);

    expect(mockExecFileSync).toHaveBeenCalledTimes(2);
    expect(console.log).toHaveBeenCalledWith(expect.stringContaining("Requested Copilot review"));
  });
});
