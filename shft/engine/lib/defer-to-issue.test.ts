import { describe, it, expect, vi, beforeEach } from "vitest";
import { deferToIssue } from "./defer-to-issue.js";
import type { ScoredComment } from "./types.js";

vi.mock("node:child_process", () => ({
  execFileSync: vi.fn(),
}));

vi.mock("./resolve-threads.js", () => ({
  resolveThread: vi.fn(),
}));

import { execFileSync } from "node:child_process";
import { resolveThread } from "./resolve-threads.js";

const mockExecFileSync = vi.mocked(execFileSync);
const mockResolveThread = vi.mocked(resolveThread);

const basePr = { prNumber: "42", owner: "acme", repo: "widgets", cwd: "/repo" };

function makeScoredComment(overrides?: Partial<ScoredComment>): ScoredComment {
  return {
    comment: { path: "src/utils.ts", line: 10, body: "Consider restructuring this module for better separation of concerns" },
    score: 30,
    tier: "hitl",
    signals: [
      { label: "vague language", delta: -25 },
      { label: "cross-file", delta: -15 },
    ],
    ...overrides,
  };
}

describe("deferToIssue", () => {
  beforeEach(() => {
    mockExecFileSync.mockReset();
    mockResolveThread.mockReset();
    vi.spyOn(console, "warn").mockImplementation(() => {});
  });

  it("creates a GitHub issue with correct title, body, and labels", () => {
    // First call: findExistingIssue returns empty array
    // Second call: issue create returns new issue
    // Third call: postThreadReply
    mockExecFileSync
      .mockReturnValueOnce(JSON.stringify([]))
      .mockReturnValueOnce("https://github.com/acme/widgets/issues/99\n")
      .mockReturnValueOnce("");

    const result = deferToIssue({ scored: makeScoredComment(), pr: basePr, threadId: "PRRT_abc", cwd: "/repo" });

    expect(result.issueNumber).toBe(99);

    // Verify issue creation call
    const createCall = mockExecFileSync.mock.calls[1]!;
    expect(createCall[1]).toContain("--label");
    expect(createCall[1]).toContain("shft");
    expect(createCall[1]).toContain("hitl");
  });

  it("resolves the thread after creating the issue", () => {
    mockExecFileSync
      .mockReturnValueOnce(JSON.stringify([]))
      .mockReturnValueOnce("https://github.com/acme/widgets/issues/99\n")
      .mockReturnValueOnce("");

    deferToIssue({ scored: makeScoredComment(), pr: basePr, threadId: "PRRT_abc", cwd: "/repo" });

    expect(mockResolveThread).toHaveBeenCalledWith({ threadId: "PRRT_abc", cwd: "/repo" });
  });

  it("skips issue creation when duplicate exists", () => {
    const scored = makeScoredComment({ comment: { path: "src/utils.ts", line: 10, body: "Short comment" } });
    const expectedTitle = "review: Short comment";

    mockExecFileSync.mockReturnValueOnce(JSON.stringify([{ number: 50, url: "https://github.com/acme/widgets/issues/50", title: expectedTitle }]));
    // Thread reply call
    mockExecFileSync.mockReturnValueOnce("");

    const result = deferToIssue({ scored, pr: basePr, threadId: "PRRT_dup", cwd: "/repo" });

    expect(result.issueNumber).toBe(50);
    // Should NOT have called issue create (only findExisting + threadReply)
    expect(mockExecFileSync).toHaveBeenCalledTimes(2);
  });

  it("includes score breakdown in issue body", () => {
    mockExecFileSync
      .mockReturnValueOnce(JSON.stringify([]))
      .mockReturnValueOnce("https://github.com/acme/widgets/issues/99\n")
      .mockReturnValueOnce("");

    deferToIssue({ scored: makeScoredComment(), pr: basePr, threadId: "PRRT_abc", cwd: "/repo" });

    const createCall = mockExecFileSync.mock.calls[1]!;
    const bodyArg = (createCall[1] as string[])[(createCall[1] as string[]).indexOf("--body") + 1]!;
    expect(bodyArg).toContain("30/100");
    expect(bodyArg).toContain("vague language: -25");
    expect(bodyArg).toContain("`src/utils.ts`");
  });

  it("posts a thread reply linking to the created issue", () => {
    mockExecFileSync
      .mockReturnValueOnce(JSON.stringify([]))
      .mockReturnValueOnce("https://github.com/acme/widgets/issues/99\n")
      .mockReturnValueOnce("");

    deferToIssue({ scored: makeScoredComment(), pr: basePr, threadId: "PRRT_abc", cwd: "/repo" });

    // Third call is the thread reply
    const replyCall = mockExecFileSync.mock.calls[2]!;
    const args = replyCall[1] as string[];
    expect(args.some((a) => a.includes("Deferred to #99"))).toBe(true);
  });

  it("does not resolve the thread when posting the backlink fails", () => {
    mockExecFileSync
      .mockReturnValueOnce(JSON.stringify([]))
      .mockReturnValueOnce("https://github.com/acme/widgets/issues/99\n")
      .mockImplementationOnce(() => {
        throw new Error("graphql failed");
      });

    expect(() => deferToIssue({ scored: makeScoredComment(), pr: basePr, threadId: "PRRT_abc", cwd: "/repo" })).toThrow("graphql failed");
    expect(mockResolveThread).not.toHaveBeenCalled();
  });
});
