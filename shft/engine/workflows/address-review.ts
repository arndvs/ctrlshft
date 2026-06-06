import path from "node:path";
import { run, Output, StructuredOutputError, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { ImplementPrOutput } from "../schemas/implement-pr-output.js";
import { fetchPrComments } from "../lib/fetch-pr-comments.js";
import { scoreComment } from "../lib/score-comment.js";
import { deferToIssue } from "../lib/defer-to-issue.js";
import { resolveThreads } from "../lib/resolve-threads.js";
import { postReviewWithComments } from "../lib/inline-comment.js";
import { postRoundSummary } from "../lib/round-summary.js";
import { requestCopilotReview } from "../lib/request-review.js";
import { sh, ghGraphql, trySh } from "../lib/shell-helpers.js";
import { loadConfig } from "../lib/config.js";
import type { DispatchContext, ScoredComment, RoundResult } from "../lib/types.js";

export async function runAddressReview(ctx: DispatchContext): Promise<void> {
  const { repoDir, model, promptsDir, args } = ctx;
  const prNumber = args.pr as string;

  if (!prNumber) {
    throw new Error("--pr is required for address-review workflow");
  }

  const config = loadConfig({ cwd: repoDir });
  const maxRounds = config.maxReviewRounds;

  console.log(`[address-review] Starting review loop for PR #${prNumber}`);
  console.log(`[address-review] Max rounds: ${maxRounds}`);

  for (let round = 1; round <= maxRounds; round++) {
    console.log(`\n[address-review] ═══ Round ${round}/${maxRounds} ═══`);

    const prContext = fetchPrComments({ prNumber, cwd: repoDir });
    const unresolvedThreads = prContext.comments.review_threads;

    if (unresolvedThreads.length === 0) {
      console.log(`[address-review] No unresolved threads — review loop complete`);
      break;
    }

    console.log(`[address-review] Unresolved threads: ${unresolvedThreads.length}`);

    // Score each thread
    const scored: ScoredComment[] = unresolvedThreads.map((thread) =>
      scoreComment({
        commentId: thread.commentId,
        threadId: thread.threadId,
        path: thread.path ?? null,
        line: thread.line ?? null,
        author: thread.author,
        body: thread.body,
        thresholds: config.scoreThresholds,
      }),
    );

    const autoComments = scored.filter((s) => s.tier === "auto");
    const confirmComments = scored.filter((s) => s.tier === "confirm");
    const hitlComments = scored.filter((s) => s.tier === "hitl");

    console.log(`[address-review] Scored: ${autoComments.length} auto, ${confirmComments.length} confirm, ${hitlComments.length} hitl`);

    const roundResult: RoundResult = { round, fixed: [], deferred: [], skipped: [] };

    // Defer HITL comments to issues
    for (const comment of hitlComments) {
      const issueNum = deferToIssue({
        prNumber,
        threadId: comment.threadId,
        commentBody: comment.body,
        path: comment.path,
        line: comment.line,
        score: comment.score,
        reason: comment.reason,
        cwd: repoDir,
      });
      console.log(`[address-review] Deferred ${comment.commentId} → issue #${issueNum}`);

      // Resolve the thread with a link to the issue
      ghGraphql({
        query: "mutation($nodeId:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$nodeId,body:$body}){comment{id}}}",
        variables: {
          nodeId: comment.threadId,
          body: `Deferred to #${issueNum} for human review (score: ${comment.score}).`,
        },
        cwd: repoDir,
      });

      resolveThreads({ threadIds: [comment.threadId], cwd: repoDir });
      roundResult.deferred.push(comment.commentId);
    }

    // Process auto + confirm comments via agent
    const actionableComments = [...autoComments, ...confirmComments];

    if (actionableComments.length > 0) {
      const filteredContext = {
        ...prContext.comments,
        review_threads: unresolvedThreads.filter((t) =>
          actionableComments.some((s) => s.commentId === t.commentId),
        ),
      };

      const branch = sh({
        cmd: "gh",
        args: ["pr", "view", prNumber, "--json", "headRefName", "--jq", ".headRefName"],
        cwd: repoDir,
      });

      try {
        const result = await run({
          agent: claudeCode(model),
          sandbox: noSandbox(),
          cwd: repoDir,
          promptFile: path.join(promptsDir, "address-review.md"),
          promptArgs: {
            PR_NUMBER: prNumber,
            BRANCH: branch,
            ROUND: String(round),
            PR_COMMENTS_JSON: JSON.stringify(filteredContext, null, 2),
          },
          output: Output.object({ tag: "output", schema: ImplementPrOutput }),
          logging: { type: "stdout" },
        });

        // Post thread replies
        const threadIdByCommentId = new Map(unresolvedThreads.map((t) => [t.commentId, t.threadId]));
        const validReplyIds = new Set(unresolvedThreads.map((t) => t.commentId));

        for (const reply of result.output.threadReplies) {
          if (!validReplyIds.has(reply.commentId)) {
            console.warn(`[address-review] Dropping reply for commentId=${reply.commentId} — not in fetched threads`);
            continue;
          }
          const threadId = threadIdByCommentId.get(reply.commentId)!;
          ghGraphql({
            query: "mutation($nodeId:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$nodeId,body:$body}){comment{id}}}",
            variables: { nodeId: threadId, body: reply.body },
            cwd: repoDir,
          });
        }

        // Resolve threads that were addressed
        const addressedThreadIds = result.output.threadReplies
          .filter((r) => validReplyIds.has(r.commentId))
          .map((r) => threadIdByCommentId.get(r.commentId)!)
          .filter((id): id is string => id != null);

        if (addressedThreadIds.length > 0) {
          const { resolved } = resolveThreads({ threadIds: addressedThreadIds, cwd: repoDir });
          console.log(`[address-review] Resolved ${resolved.length} threads`);
        }

        // Post inline comments if any
        if (result.output.newInlineComments.length > 0 || result.output.topLevelComments.length > 0) {
          const headSha = sh({
            cmd: "gh",
            args: ["pr", "view", prNumber, "--json", "headRefOid", "--jq", ".headRefOid"],
            cwd: repoDir,
          });
          const reviewBody = result.output.topLevelComments.map((c) => c.body).join("\n\n") || "Addressed review feedback.";
          postReviewWithComments({
            prNumber,
            comments: result.output.newInlineComments,
            summary: reviewBody,
            commitSha: headSha,
            cwd: repoDir,
          });
        }

        for (const comment of actionableComments) {
          const wasReplied = result.output.threadReplies.some((r) => r.commentId === comment.commentId);
          if (wasReplied || result.commits.length > 0) {
            roundResult.fixed.push(comment.commentId);
          } else {
            roundResult.skipped.push(comment.commentId);
          }
        }

        console.log(`[address-review] Round ${round}: ${roundResult.fixed.length} fixed, ${roundResult.deferred.length} deferred, ${roundResult.skipped.length} skipped`);
      } catch (error) {
        if (error instanceof StructuredOutputError) {
          console.error(`[address-review] Round ${round} failed: malformed agent output`);
          console.error(`[address-review] Tag: <${error.tag}>`);
          console.error(`[address-review] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
          if (error.cause) console.error(`[address-review] Cause:`, error.cause);
          // Don't exit — continue to summary and potentially next round
          for (const comment of actionableComments) {
            roundResult.skipped.push(comment.commentId);
          }
        } else {
          throw error;
        }
      }
    }

    // Post round summary
    postRoundSummary({
      prNumber,
      round,
      fixed: roundResult.fixed,
      deferred: roundResult.deferred,
      skipped: roundResult.skipped,
      cwd: repoDir,
    });

    // Re-request Copilot review for next round (unless this is the last round)
    if (round < maxRounds && (roundResult.fixed.length > 0)) {
      console.log(`[address-review] Re-requesting Copilot review...`);
      requestCopilotReview({ prNumber, cwd: repoDir });
    }
  }

  // Final check: if we hit the round cap, label the PR
  const finalContext = fetchPrComments({ prNumber, cwd: repoDir });
  if (finalContext.comments.review_threads.length > 0) {
    console.log(`[address-review] Round cap reached with ${finalContext.comments.review_threads.length} unresolved threads`);
    trySh({
      cmd: "gh",
      args: ["pr", "edit", prNumber, "--add-label", "review-cap-reached"],
      cwd: repoDir,
    });
  }

  console.log(`\n[address-review] Review loop complete`);
}
