import { describe, it, expect, vi, beforeEach } from "vitest";
import * as childProcess from "node:child_process";
import { fetchPrComments } from "./fetch-pr-comments.js";

vi.mock("node:child_process", () => ({
  execSync: vi.fn(),
  execFileSync: vi.fn(),
}));

const mockExecSync = vi.mocked(childProcess.execSync);
const mockExecFileSync = vi.mocked(childProcess.execFileSync);

describe("fetchPrComments", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("throws on invalid PR number", () => {
    expect(() => fetchPrComments({ prNumber: "abc", cwd: "/tmp" })).toThrow("Invalid PR number");
  });

  it("fetches and structures PR data", () => {
    // fetchPrComments calls in order:
    // 1. execSync: sh() for gh pr view (title, body, comments)
    // 2. execSync: safeSh() for gh issue view (linked issue title)
    // 3. execSync: sh() for gh api reviews
    // 4. execFileSync: getOwnerRepo() via gh repo view
    // 5. execFileSync: gh api graphql for review threads

    mockExecSync
      // 1. gh pr view
      .mockReturnValueOnce(JSON.stringify({
        title: "Test PR",
        body: "Fixes #10",
        headRefOid: "abc123",
        comments: [{ author: { login: "user1" }, body: "LGTM" }],
      }) as never)
      // 2. gh issue view
      .mockReturnValueOnce("Issue title\n" as never)
      // 3. gh api reviews
      .mockReturnValueOnce(JSON.stringify([
        { id: 1, user: { login: "reviewer" }, body: "Needs changes", state: "CHANGES_REQUESTED" },
      ]) as never)
      // 4. gh repo view (getOwnerRepo uses execSync, not execFileSync)
      .mockReturnValueOnce("octocat/hello\n" as never);

    mockExecFileSync
      // 5. gh api graphql (threads) — only execFileSync call
      .mockReturnValueOnce(JSON.stringify({
        data: {
          repository: {
            pullRequest: {
              reviewThreads: {
                nodes: [
                  {
                    id: "thread1",
                    isResolved: false,
                    isOutdated: false,
                    comments: {
                      nodes: [
                        { id: "comment1", path: "src/index.ts", line: 10, originalLine: 10, body: "Fix this", author: { login: "bot" } },
                      ],
                    },
                  },
                  {
                    id: "thread2",
                    isResolved: true,
                    isOutdated: false,
                    comments: { nodes: [] },
                  },
                ],
              },
            },
          },
        },
      }));

    const result = fetchPrComments({ prNumber: "42", cwd: "/tmp" });

    expect(result.prTitle).toBe("Test PR");
    expect(result.issueNumber).toBe("10");
    expect(result.issueTitle).toBe("Issue title");
    expect(result.comments.issue_comments).toHaveLength(1);
    expect(result.comments.review_summaries).toHaveLength(1);
    // Only unresolved, non-outdated threads with comments
    expect(result.comments.review_threads).toHaveLength(1);
    expect(result.comments.review_threads[0]!.commentId).toBe("comment1");
  });
});
