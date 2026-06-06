import path from "node:path";
import { run, Output, StructuredOutputError, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { ReviewOutput } from "../schemas/review-output.js";
import { fetchPrComments } from "../lib/fetch-pr-comments.js";
import { postReviewWithComments } from "../lib/inline-comment.js";
import { sh, ghGraphql } from "../lib/shell-helpers.js";
import type { DispatchContext } from "../lib/types.js";

export async function runReview(ctx: DispatchContext): Promise<void> {
  const { repoDir, model, promptsDir, args } = ctx;
  const prNumber = args.pr as string;

  if (!prNumber) {
    throw new Error("--pr is required for review workflow");
  }

  console.log(`[review] Fetching PR #${prNumber} data...`);
  const prContext = fetchPrComments({ prNumber, cwd: repoDir });

  console.log(`[review] PR: ${prContext.prTitle}`);
  console.log(`[review] Existing threads: ${prContext.comments.review_threads.length}`);

  try {
    const result = await run({
      agent: claudeCode(model),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.join(promptsDir, "review.md"),
      promptArgs: {
        PR_NUMBER: prNumber,
        PR_COMMENTS_JSON: JSON.stringify(prContext.comments, null, 2),
      },
      output: Output.object({ tag: "output", schema: ReviewOutput }),
      logging: { type: "stdout" },
    });

    const headSha = sh({
      cmd: "gh",
      args: ["pr", "view", prNumber, "--json", "headRefOid", "--jq", ".headRefOid"],
      cwd: repoDir,
    });

    // Post review with inline comments using shared utility
    postReviewWithComments({
      prNumber,
      comments: result.output.inlineComments,
      summary: result.output.summary,
      commitSha: headSha,
      cwd: repoDir,
    });
    console.log(`[review] Posted review with ${result.output.inlineComments.length} inline comments`);

    // Post thread replies
    const validReplyIds = new Set(prContext.comments.review_threads.map((c) => c.commentId));
    const threadIdByCommentId = new Map(prContext.comments.review_threads.map((c) => [c.commentId, c.threadId]));
    const validReplies = result.output.replies.filter((r) => {
      if (!validReplyIds.has(r.commentId)) {
        console.warn(`[review] Dropping reply for commentId=${r.commentId} — not in fetched threads`);
        return false;
      }
      return true;
    });

    for (const reply of validReplies) {
      const threadId = threadIdByCommentId.get(reply.commentId)!;
      console.log(`[review] Posting reply to thread ${threadId}...`);
      ghGraphql({
        query: "mutation($nodeId:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$nodeId,body:$body}){comment{id}}}",
        variables: { nodeId: threadId, body: reply.body },
        cwd: repoDir,
      });
    }

    console.log(`\n[review] Complete`);
    console.log(`  summary: ${result.output.summary.slice(0, 80)}...`);
    console.log(`  inline comments: ${result.output.inlineComments.length}`);
    console.log(`  thread replies: ${validReplies.length}`);
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[review] Failed: malformed agent output`);
      console.error(`[review] Tag: <${error.tag}>`);
      console.error(`[review] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[review] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}
