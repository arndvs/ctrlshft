import path from "node:path";
import { run, Output, StructuredOutputError, claudeCode, createSandbox } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { Semaphore } from "../lib/semaphore.js";
import type { DispatchContext } from "../lib/types.js";
import { z } from "zod";

const PlanOutput = z.object({
  issues: z.array(
    z.object({
      number: z.number(),
      title: z.string(),
      branch: z.string(),
    }),
  ),
});

type PlanOutput = z.infer<typeof PlanOutput>;

const MergeOutput = z.object({
  merged: z.array(z.string()),
  failed: z.array(
    z.object({
      branch: z.string(),
      reason: z.string(),
    }),
  ),
  testsPassed: z.boolean(),
});

type MergeOutput = z.infer<typeof MergeOutput>;

interface IssueResult {
  issue: { number: number; title: string; branch: string };
  status: "completed" | "failed";
  commits: string[];
  error?: string;
}

async function runPlan(ctx: DispatchContext): Promise<PlanOutput> {
  const { repoDir, model, promptsDir, args } = ctx;
  const maxIssues = (args["max-issues"] as string) ?? "5";

  console.log(`\n[parallel] Running plan phase...`);
  try {
    const result = await run({
      agent: claudeCode(model),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.join(promptsDir, "plan.md"),
      maxIterations: 1,
      promptArgs: { MAX_ISSUES: maxIssues },
      output: Output.object({ tag: "output", schema: PlanOutput }),
      logging: { type: "stdout" },
    });

    console.log(`\n[parallel] Plan phase complete — ${result.output.issues.length} issues selected`);
    for (const issue of result.output.issues) {
      console.log(`  #${issue.number} ${issue.title} → ${issue.branch}`);
    }
    return result.output;
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[parallel] Plan phase failed: malformed agent output`);
      console.error(`[parallel] Tag: <${error.tag}>`);
      console.error(`[parallel] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[parallel] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}

async function implementIssue(ctx: DispatchContext, issue: PlanOutput["issues"][number], maxIterations: number): Promise<IssueResult> {
  const { repoDir, model, promptsDir } = ctx;

  console.log(`[parallel] [#${issue.number}] Starting implementation on branch ${issue.branch}`);

  const sandbox = await createSandbox({
    branch: issue.branch,
    sandbox: noSandbox(),
    cwd: repoDir,
  });

  try {
    const result = await sandbox.run({
      agent: claudeCode(model),
      promptFile: path.join(promptsDir, "implement.md"),
      promptArgs: {
        ISSUE_NUMBER: String(issue.number),
        BRANCH: issue.branch,
      },
      maxIterations,
      completionSignal: "<promise>COMPLETE</promise>",
      logging: { type: "stdout" },
    });

    const shas = result.commits.map((c) => c.sha);
    console.log(`[parallel] [#${issue.number}] Complete — ${shas.length} commits`);

    return { issue, status: "completed", commits: shas };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[parallel] [#${issue.number}] Failed: ${message}`);
    return { issue, status: "failed", commits: [], error: message };
  } finally {
    await sandbox.close();
  }
}

async function runMerge(ctx: DispatchContext, completedBranches: string[]): Promise<MergeOutput> {
  const { repoDir, model, promptsDir } = ctx;

  console.log(`\n[parallel] Running merge phase for ${completedBranches.length} branches...`);
  try {
    const result = await run({
      agent: claudeCode(model),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.join(promptsDir, "merge.md"),
      maxIterations: 1,
      promptArgs: {
        BRANCHES_JSON: JSON.stringify(completedBranches, null, 2),
      },
      output: Output.object({ tag: "output", schema: MergeOutput }),
      logging: { type: "stdout" },
    });

    console.log(`\n[parallel] Merge phase complete`);
    console.log(`  merged: ${result.output.merged.join(", ") || "none"}`);
    if (result.output.failed.length > 0) {
      for (const f of result.output.failed) {
        console.error(`  failed: ${f.branch} — ${f.reason}`);
      }
    }
    console.log(`  tests passed: ${result.output.testsPassed}`);
    return result.output;
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[parallel] Merge phase failed: malformed agent output`);
      console.error(`[parallel] Tag: <${error.tag}>`);
      console.error(`[parallel] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[parallel] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}

export async function runParallel(ctx: DispatchContext): Promise<void> {
  const maxParallel = parseInt((ctx.args["max-parallel"] as string) ?? "4", 10);
  const maxIterations = parseInt((ctx.args["max-iterations"] as string) ?? "1", 10);

  console.log(`[parallel] maxParallel: ${maxParallel}`);

  const plan = await runPlan(ctx);
  const semaphore = new Semaphore(maxParallel);

  const settled = await Promise.allSettled(
    plan.issues.map((issue) =>
      semaphore.run(() => implementIssue(ctx, issue, maxIterations)),
    ),
  );

  const results: IssueResult[] = settled.map((s, i) => {
    if (s.status === "fulfilled") return s.value;
    const message = s.reason instanceof Error ? s.reason.message : String(s.reason);
    return { issue: plan.issues[i]!, status: "failed" as const, commits: [], error: message };
  });

  const completed = results.filter((r) => r.status === "completed" && r.commits.length > 0);
  const failed = results.filter((r) => r.status === "failed");

  console.log(`\n[parallel] ═══ Parallel Execution Report ═══`);
  console.log(`  completed: ${completed.length}`);
  console.log(`  failed: ${failed.length}`);
  for (const r of completed) {
    console.log(`  ✓ #${r.issue.number} ${r.issue.title} (${r.commits.length} commits)`);
  }
  for (const r of failed) {
    console.log(`  ✗ #${r.issue.number} ${r.issue.title} — ${r.error}`);
  }

  if (completed.length > 0) {
    const completedBranches = completed.map((r) => r.issue.branch);
    await runMerge(ctx, completedBranches);
  } else {
    console.log(`\n[parallel] No branches to merge — skipping merge phase`);
  }
}
