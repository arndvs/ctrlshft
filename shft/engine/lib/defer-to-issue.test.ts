import { describe, it, expect, vi, beforeEach } from "vitest";
import * as shellHelpers from "./shell-helpers.js";
import { deferToIssue } from "./defer-to-issue.js";

vi.mock("./shell-helpers.js", () => ({
  sh: vi.fn(),
}));

const mockSh = vi.mocked(shellHelpers.sh);

describe("deferToIssue", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("creates an issue and returns its number", () => {
    mockSh.mockReturnValue("https://github.com/owner/repo/issues/42");

    const result = deferToIssue({
      prNumber: "10",
      threadId: "t1",
      commentBody: "Consider refactoring this module",
      path: "src/index.ts",
      line: 15,
      score: 30,
      reason: "low-value pattern",
      cwd: "/tmp/repo",
    });

    expect(result).toBe(42);
    expect(mockSh).toHaveBeenCalledWith(expect.objectContaining({
      cmd: "gh",
      args: expect.arrayContaining(["issue", "create"]),
    }));
  });

  it("includes path and line in issue title", () => {
    mockSh.mockReturnValue("https://github.com/owner/repo/issues/99");

    deferToIssue({
      prNumber: "5",
      threadId: "t2",
      commentBody: "Nit",
      path: "lib/util.ts",
      line: 42,
      score: 20,
      reason: "cosmetic",
      cwd: "/tmp/repo",
    });

    const call = mockSh.mock.calls[0]![0] as { args: string[] };
    const titleIdx = call.args.indexOf("--title") + 1;
    expect(call.args[titleIdx]).toContain("lib/util.ts");
    expect(call.args[titleIdx]).toContain(":42");
  });

  it("handles null path gracefully", () => {
    mockSh.mockReturnValue("https://github.com/owner/repo/issues/7");

    const result = deferToIssue({
      prNumber: "1",
      threadId: "t3",
      commentBody: "General comment",
      path: null,
      line: null,
      score: 25,
      reason: "vague",
      cwd: "/tmp/repo",
    });

    expect(result).toBe(7);
  });

  it("throws when issue URL cannot be parsed", () => {
    mockSh.mockReturnValue("unexpected output");

    expect(() => deferToIssue({
      prNumber: "1",
      threadId: "t4",
      commentBody: "test",
      path: null,
      line: null,
      score: 10,
      reason: "test",
      cwd: "/tmp/repo",
    })).toThrow(/Failed to parse issue number/);
  });
});
