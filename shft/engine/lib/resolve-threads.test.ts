import { describe, it, expect, vi, beforeEach } from "vitest";
import * as shellHelpers from "./shell-helpers.js";
import { resolveThread, resolveThreads } from "./resolve-threads.js";

vi.mock("./shell-helpers.js", () => ({
  ghGraphql: vi.fn(),
}));

const mockGhGraphql = vi.mocked(shellHelpers.ghGraphql);

describe("resolveThread", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("calls ghGraphql with the correct mutation", () => {
    mockGhGraphql.mockReturnValue('{"data":{}}');
    resolveThread({ threadId: "thread-123", cwd: "/tmp/repo" });
    expect(mockGhGraphql).toHaveBeenCalledWith(expect.objectContaining({
      variables: { threadId: "thread-123" },
      cwd: "/tmp/repo",
    }));
  });
});

describe("resolveThreads", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("resolves multiple threads and reports results", () => {
    mockGhGraphql.mockReturnValue('{"data":{}}');

    const result = resolveThreads({ threadIds: ["t1", "t2", "t3"], cwd: "/tmp/repo" });
    expect(result.resolved).toEqual(["t1", "t2", "t3"]);
    expect(result.failed).toEqual([]);
    expect(mockGhGraphql).toHaveBeenCalledTimes(3);
  });

  it("collects failed threads without blocking others", () => {
    mockGhGraphql
      .mockReturnValueOnce('{"data":{}}')
      .mockImplementationOnce(() => { throw new Error("network error"); })
      .mockReturnValueOnce('{"data":{}}');

    const result = resolveThreads({ threadIds: ["t1", "t2", "t3"], cwd: "/tmp/repo" });
    expect(result.resolved).toEqual(["t1", "t3"]);
    expect(result.failed).toEqual(["t2"]);
  });

  it("handles empty input", () => {
    const result = resolveThreads({ threadIds: [], cwd: "/tmp/repo" });
    expect(result.resolved).toEqual([]);
    expect(result.failed).toEqual([]);
    expect(mockGhGraphql).not.toHaveBeenCalled();
  });
});
