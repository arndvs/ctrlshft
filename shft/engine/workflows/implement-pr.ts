import path from "node:path";
import { run, Output, StructuredOutputError, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { ImplementPrOutput } from "../schemas/implement-pr-output.js";
import { fetchPrComments } from "../lib/fetch-pr-comments.js";
import { postReviewWithComments } from "../lib/inline-comment.js";
import { resolveThreads } from "../lib/resolve-threads.js";
import { sh, ghGraphql } from "../lib/shell-helpers.js";
import type { DispatchContext } from "../lib/types.js";

export async function runImplementPr(ctx: DispatchContext): Promise<void> {
  const { repoDir, model, promptsDir, args } = ctx;
  const prNumber = args.pr as string;

  if (!prNumber) {
    throw new Error("--pr is required for implement-pr workflow");
  }

  console.log(`[implement-pr] Fetching PR #${prNumber} data...`);
  const prContext = fetchPrComments({ prNumber, cwd: repoDir });

  const branch = sh({
    cmd: "gh",
    args: ["pr", "view", prNumber, "--json", "headRefName", "--jq", ".headRefName"],
    cwd: repoDir,
  });

  const issueNumber = prContext.issueNumber || "(none)";
  const issueTitle = prContext.issueTitle || "(no linked issue)";

  console.log(`[implement-pr] PR: ${prContext.prTitle}`);
  console.log(`[implement-pr] Branch: ${branch}`);
  console.log(`[implement-pr] Linked issue: ${issueNumber === "(none)" ? "none" : `#${issueNumber} — ${issueTitle}`}`);
  console.log(`[implement-pr] Unresolved threads: ${prContext.comments.review_threads.length}`);

  try {
    const result = await run({
      agent: claudeCode(model),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.join(promptsDir, "implement-pr.md"),
      promptArgs: {
        PR_NUMBER: prNumber,
        BRANCH: branch,
        ISSUE_NUMBER: issueNumber,
        ISSUE_TITLE: issueTitle,
        PR_COMMENTS_JSON: JSON.stringify(prContext.comments, null, 2),
      },
      output: Output.object({ tag: "output", schema: ImplementPrOutput }),
      logging: { type: "stdout" },
    });

    const commitsThisRun = result.commits.length;
    const replyCount = result.output.threadReplies.length + result.output.newInlineComments.length + result.output.topLevelComments.length;

    if (commitsThisRun === 0 && replyCount === 0) {
      console.error(`[implement-pr] FAILED: Agent produced no commits and no replies`);
      process.exit(1);
    }

    const headSha = sh({
      cmd: "gh",
      args: ["pr", "view", prNumber, "--json", "headRefOid", "--jq", ".headRefOid"],
      cwd: repoDir,
    });

    // Validate and post thread replies
    const validReplyIds = new Set(prContext.comments.review_threads.map((c) => c.commentId));
    const threadIdByCommentId = new Map(prContext.comments.review_threads.map((c) => [c.commentId, c.threadId]));
    const validThreadReplies = result.output.threadReplies.filter((r) => {
      if (!validReplyIds.has(r.commentId)) {
        console.warn(`[implement-pr] Dropping reply for commentId=${r.commentId} — not in fetched threads`);
        return false;
      }
      return true;
    });

    for (const reply of validThreadReplies) {
      const threadId = threadIdByCommentId.get(reply.commentId)!;
      console.log(`[implement-pr] Posting reply to thread ${threadId}...`);
      ghGraphql({
        query: "mutation($nodeId:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$nodeId,body:$body}){comment{id}}}",
        variables: { nodeId: threadId, body: reply.body },
        cwd: repoDir,
      });
    }

    // Post review with inline comments using shared utility
    if (result.output.newInlineComments.length > 0 || result.output.topLevelComments.length > 0) {
      const reviewBody = result.output.topLevelComments.map((c) => c.body).join("\n\n") || "Addressed review feedback.";
      postReviewWithComments({
        prNumber,
        comments: result.output.newInlineComments,
        summary: reviewBody,
        commitSha: headSha,
        cwd: repoDir,
      });
      console.log(`[implement-pr] Posted review with inline comments`);
    }

    console.log(`\n[implement-pr] Complete`);
    console.log(`  commits: ${commitsThisRun}`);
    console.log(`  thread replies: ${validThreadReplies.length}`);
    console.log(`  inline comments: ${result.output.newInlineComments.length}`);
    console.log(`  top-level comments: ${result.output.topLevelComments.length}`);
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[implement-pr] Failed: malformed agent output`);
      console.error(`[implement-pr] Tag: <${error.tag}>`);
      console.error(`[implement-pr] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[implement-pr] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}
