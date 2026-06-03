import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { run, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { fetchPrComments, getOwnerRepo } from "../lib/fetch-pr-comments.js";
import { scoreComment } from "../lib/score-comment.js";
import { deferToIssue } from "../lib/defer-to-issue.js";
import { resolveThreads } from "../lib/resolve-threads.js";
import { postRoundSummary } from "../lib/round-summary.js";
import { requestCopilotReview } from "../lib/request-review.js";
import { loadConfig } from "../lib/config.js";
import type { ScoredComment, Tier } from "../lib/types.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultPromptsDir = path.resolve(__dirname, "..", "prompts");

interface AddressReviewOpts {
  prNumber: string;
  round: number;
  maxRounds: number;
  repoDir: string;
  model?: string;
  promptsDir?: string;
}

interface AddressReviewResult {
  fixed: number;
  deferred: number;
  remaining: number;
  roundCapped: boolean;
}

interface CommentWithThread {
  scored: ScoredComment;
  threadId: string;
  commentId: string;
}

export async function runAddressReview(opts: AddressReviewOpts): Promise<AddressReviewResult> {
  const config = await loadConfig({ cwd: opts.repoDir });
  const { prNumber, round, maxRounds, repoDir } = opts;
  const model = opts.model ?? config.model;
  const promptsDir = opts.promptsDir ?? defaultPromptsDir;
  const { owner, repo } = getOwnerRepo({ cwd: repoDir });

  console.log(`\n[address-review] Round ${round}/${maxRounds} — PR #${prNumber}`);

  // 1. Fetch unresolved review threads
  console.log(`[address-review] Fetching unresolved threads...`);
  const prContext = fetchPrComments({ prNumber, cwd: repoDir });
  const threads = prContext.comments.review_threads;

  if (threads.length === 0) {
    console.log(`[address-review] No unresolved threads — nothing to do`);
    return { fixed: 0, deferred: 0, remaining: 0, roundCapped: false };
  }

  console.log(`[address-review] ${threads.length} unresolved thread(s)`);

  // 2. Score each comment
  const withThreads: CommentWithThread[] = threads.map((t) => ({
    scored: scoreComment({ path: t.path, line: t.line, body: t.body }),
    threadId: t.threadId,
    commentId: t.commentId,
  }));

  for (const { scored } of withThreads) {
    const signalNames = scored.signals.map((s) => s.label).join(", ");
    console.log(`[address-review]   score=${scored.score} tier=${scored.tier} signals=[${signalNames}]`);
  }

  // 3. Partition: Auto/Confirm vs HITL
  const autoConfirm = withThreads.filter((c) => c.scored.tier === "auto" || c.scored.tier === "confirm");
  const hitl = withThreads.filter((c) => c.scored.tier === "hitl");

  console.log(`[address-review] ${autoConfirm.length} auto/confirm, ${hitl.length} HITL`);

  // Track results for round summary
  const results: Array<{ body: string; score: number; tier: Tier; action: "fixed" | "deferred" | "skipped"; issueNumber?: number }> = [];

  // 4. For Auto/Confirm: fix via Sandcastle
  let fixedCount = 0;
  const fixedThreadIds: string[] = [];

  if (autoConfirm.length > 0) {
    console.log(`[address-review] Fixing ${autoConfirm.length} auto/confirm comment(s) via Sandcastle...`);

    const commentsPayload = autoConfirm.map((c) => ({
      path: c.scored.comment.path,
      line: c.scored.comment.line,
      body: c.scored.comment.body,
      score: c.scored.score,
      tier: c.scored.tier,
    }));

    try {
      await run({
        agent: claudeCode(model),
        sandbox: noSandbox(),
        cwd: repoDir,
        promptFile: path.join(promptsDir, "address-review.md"),
        promptArgs: {
          PR_NUMBER: prNumber,
          BRANCH: getBranch({ prNumber, cwd: repoDir }),
          COMMENTS_JSON: JSON.stringify(commentsPayload, null, 2),
        },
        completionSignal: "<promise>COMPLETE</promise>",
        logging: { type: "stdout" },
      });

      // All auto/confirm comments treated as fixed after Sandcastle run
      for (const c of autoConfirm) {
        fixedCount++;
        fixedThreadIds.push(c.threadId);
        results.push({ body: c.scored.comment.body, score: c.scored.score, tier: c.scored.tier, action: "fixed" });
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`[address-review] Sandcastle fix failed: ${message}`);

      // Mark all as skipped on failure
      for (const c of autoConfirm) {
        results.push({ body: c.scored.comment.body, score: c.scored.score, tier: c.scored.tier, action: "skipped" });
      }
    }
  }

  // 5. For HITL: defer to issues
  let deferredCount = 0;

  for (const c of hitl) {
    try {
      const result = deferToIssue({
        scored: c.scored,
        pr: { prNumber, owner, repo },
        threadId: c.threadId,
        cwd: repoDir,
      });
      deferredCount++;
      results.push({ body: c.scored.comment.body, score: c.scored.score, tier: c.scored.tier, action: "deferred", issueNumber: result.issueNumber });
      console.log(`[address-review] Deferred to #${result.issueNumber}: ${c.scored.comment.body.slice(0, 50)}`);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.warn(`[address-review] Failed to defer comment: ${message}`);
      results.push({ body: c.scored.comment.body, score: c.scored.score, tier: c.scored.tier, action: "skipped" });
    }
  }

  // 6. Resolve threads for fixed comments (HITL threads already resolved by deferToIssue)
  if (fixedThreadIds.length > 0) {
    console.log(`[address-review] Resolving ${fixedThreadIds.length} fixed thread(s)...`);
    resolveThreads({ threadIds: fixedThreadIds, cwd: repoDir });
  }

  // 7. Post round summary
  postRoundSummary({ owner, repo, prNumber, round, maxRounds, results, cwd: repoDir });

  // 8. Re-request Copilot review
  requestCopilotReview({ owner, repo, prNumber, cwd: repoDir });

  const remaining = results.filter((r) => r.action === "skipped").length;
  const roundCapped = round >= maxRounds && remaining > 0;

  console.log(`\n[address-review] Round ${round} complete`);
  console.log(`  fixed: ${fixedCount}`);
  console.log(`  deferred: ${deferredCount}`);
  console.log(`  remaining: ${remaining}`);
  if (roundCapped) {
    console.log(`  ⚠️ Round cap reached with ${remaining} unresolved comment(s)`);
  }

  return { fixed: fixedCount, deferred: deferredCount, remaining, roundCapped };
}

function getBranch(opts: { prNumber: string; cwd: string }): string {
  return execFileSync("gh", ["pr", "view", opts.prNumber, "--json", "headRefName", "--jq", ".headRefName"], {
    encoding: "utf8",
    cwd: opts.cwd,
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}
