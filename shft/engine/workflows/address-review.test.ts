import { describe, it, expect, vi, beforeEach } from "vitest";
import type { DispatchContext } from "../lib/types.js";

// Mock all external dependencies
vi.mock("@ai-hero/sandcastle", () => ({
  run: vi.fn(),
  Output: { object: vi.fn() },
  StructuredOutputError: class StructuredOutputError extends Error {
    tag: string;
    rawMatched: string | null;
    constructor(tag: string, rawMatched: string | null) {
      super("structured output error");
      this.tag = tag;
      this.rawMatched = rawMatched;
    }
  },
  claudeCode: vi.fn(() => "mock-agent"),
}));

vi.mock("@ai-hero/sandcastle/sandboxes/no-sandbox", () => ({
  noSandbox: vi.fn(() => "mock-sandbox"),
}));

vi.mock("../lib/fetch-pr-comments.js", () => ({
  fetchPrComments: vi.fn(),
}));

vi.mock("../lib/score-comment.js", () => ({
  scoreComment: vi.fn(),
}));

vi.mock("../lib/defer-to-issue.js", () => ({
  deferToIssue: vi.fn(),
}));

vi.mock("../lib/resolve-threads.js", () => ({
  resolveThreads: vi.fn(),
}));

vi.mock("../lib/inline-comment.js", () => ({
  postReviewWithComments: vi.fn(),
}));

vi.mock("../lib/round-summary.js", () => ({
  postRoundSummary: vi.fn(),
}));

vi.mock("../lib/request-review.js", () => ({
  requestCopilotReview: vi.fn(),
}));

vi.mock("../lib/shell-helpers.js", () => ({
  sh: vi.fn(),
  ghGraphql: vi.fn(),
  trySh: vi.fn(() => ({ stdout: "", ok: true })),
}));

vi.mock("../lib/config.js", () => ({
  loadConfig: vi.fn(() => ({
    maxReviewRounds: 3,
    scoreThresholds: { auto: 75, confirm: 40 },
  })),
}));

describe("runAddressReview", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("exits early when no unresolved threads", async () => {
    const { fetchPrComments } = await import("../lib/fetch-pr-comments.js");
    const { postRoundSummary } = await import("../lib/round-summary.js");

    vi.mocked(fetchPrComments).mockReturnValue({
      prTitle: "Test PR",
      issueNumber: null,
      issueTitle: null,
      comments: {
        issue_comments: [],
        review_summaries: [],
        review_threads: [],
      },
    });

    const { runAddressReview } = await import("./address-review.js");

    const ctx: DispatchContext = {
      workflow: "address-review",
      repoDir: "/tmp/test",
      model: "test-model",
      promptsDir: "/tmp/prompts",
      args: { pr: "42" },
    };

    await runAddressReview(ctx);

    // Should not post any round summaries since there were no threads
    expect(postRoundSummary).not.toHaveBeenCalled();
  });

  it("throws when --pr is missing", async () => {
    const { runAddressReview } = await import("./address-review.js");

    const ctx: DispatchContext = {
      workflow: "address-review",
      repoDir: "/tmp/test",
      model: "test-model",
      promptsDir: "/tmp/prompts",
      args: {},
    };

    await expect(runAddressReview(ctx)).rejects.toThrow("--pr is required");
  });

  it("defers hitl-scored comments to issues", async () => {
    const { fetchPrComments } = await import("../lib/fetch-pr-comments.js");
    const { scoreComment } = await import("../lib/score-comment.js");
    const { deferToIssue } = await import("../lib/defer-to-issue.js");
    const { resolveThreads } = await import("../lib/resolve-threads.js");
    const { ghGraphql } = await import("../lib/shell-helpers.js");
    const { postRoundSummary } = await import("../lib/round-summary.js");

    // First call: has threads. Second call (final check): no threads
    vi.mocked(fetchPrComments)
      .mockReturnValueOnce({
        prTitle: "Test PR",
        issueNumber: null,
        issueTitle: null,
        comments: {
          issue_comments: [],
          review_summaries: [],
          review_threads: [
            { commentId: "c1", threadId: "t1", path: "src/foo.ts", line: 10, author: "copilot", body: "consider refactoring" },
          ],
        },
      })
      .mockReturnValue({
        prTitle: "Test PR",
        issueNumber: null,
        issueTitle: null,
        comments: { issue_comments: [], review_summaries: [], review_threads: [] },
      });

    vi.mocked(scoreComment).mockReturnValue({
      commentId: "c1",
      threadId: "t1",
      path: "src/foo.ts",
      line: 10,
      author: "copilot",
      body: "consider refactoring",
      score: 20,
      tier: "hitl",
      reason: "low-value pattern",
    });

    vi.mocked(deferToIssue).mockReturnValue(99);
    vi.mocked(resolveThreads).mockReturnValue({ resolved: ["t1"], failed: [] });

    const { runAddressReview } = await import("./address-review.js");

    const ctx: DispatchContext = {
      workflow: "address-review",
      repoDir: "/tmp/test",
      model: "test-model",
      promptsDir: "/tmp/prompts",
      args: { pr: "42" },
    };

    await runAddressReview(ctx);

    expect(deferToIssue).toHaveBeenCalledWith(expect.objectContaining({
      prNumber: "42",
      threadId: "t1",
      commentBody: "consider refactoring",
    }));
    expect(resolveThreads).toHaveBeenCalledWith(expect.objectContaining({
      threadIds: ["t1"],
    }));
    expect(postRoundSummary).toHaveBeenCalledWith(expect.objectContaining({
      round: 1,
      deferred: ["c1"],
      fixed: [],
    }));
  });
});
