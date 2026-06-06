import path from "node:path";
import { fileURLToPath } from "node:url";
import { run, Output, StructuredOutputError, claudeCode, createSandbox } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { PlanOutput } from "./schemas/plan-output.js";
import { MergeOutput } from "./schemas/merge-output.js";
import { dispatch, getWorkflow, listWorkflows } from "./lib/dispatch.js";
import { parseCliArgs } from "./lib/parse-cli-args.js";
import { loadConfig } from "./lib/config.js";
import { Semaphore } from "./lib/semaphore.js";
import { registerAllWorkflows } from "./workflows/register.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Register all workflow runners
registerAllWorkflows();

const cliArgs = parseCliArgs();
const config = loadConfig({ cwd: cliArgs.repo });

const repoDir = path.resolve(cliArgs.repo);
const MODEL = cliArgs.model ?? process.env["ANTHROPIC_MODEL"] ?? config.model;
const maxIterations = cliArgs.maxIterations;
const maxParallel = cliArgs.maxParallel;
const workflow = cliArgs.workflow;
const promptsDir = cliArgs.promptsDir ? path.resolve(cliArgs.promptsDir) : path.resolve(__dirname, "prompts");

console.log(`[shft-engine] repo: ${repoDir}`);
console.log(`[shft-engine] workflow: ${workflow}`);
console.log(`[shft-engine] model: ${MODEL}`);
console.log(`[shft-engine] maxIterations: ${maxIterations}`);

const promptArgs: Record<string, string> = {};
if (cliArgs.issue) promptArgs["ISSUE_NUMBER"] = cliArgs.issue;
if (cliArgs.branch) promptArgs["BRANCH"] = cliArgs.branch;
promptArgs["MAX_ISSUES"] = String(cliArgs.maxIssues);

interface IssueResult {
  issue: { number: number; title: string; branch: string };
  status: "completed" | "failed";
  commits: string[];
  error?: string;
}

async function runPlan(): Promise<PlanOutput> {
  console.log(`\n[shft-engine] Running plan phase...`);
  try {
    const result = await run({
      agent: claudeCode(MODEL),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.resolve(promptsDir, "plan.md"),
      maxIterations: 1,
      promptArgs,
      output: Output.object({ tag: "output", schema: PlanOutput }),
      logging: { type: "stdout" },
    });

    console.log(`\n[shft-engine] Plan phase complete — ${result.output.issues.length} issues selected`);
    for (const issue of result.output.issues) {
      console.log(`  #${issue.number} ${issue.title} → ${issue.branch}`);
    }
    return result.output;
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[shft-engine] Plan phase failed: malformed agent output`);
      console.error(`[shft-engine] Tag: <${error.tag}>`);
      console.error(`[shft-engine] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[shft-engine] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}

async function implementIssue(issue: PlanOutput["issues"][number]): Promise<IssueResult> {
  console.log(`[shft-engine] [#${issue.number}] Starting implementation on branch ${issue.branch}`);

  const sandbox = await createSandbox({
    branch: issue.branch,
    sandbox: noSandbox(),
    cwd: repoDir,
  });

  try {
    const result = await sandbox.run({
      agent: claudeCode(MODEL),
      promptFile: path.resolve(promptsDir, "implement.md"),
      promptArgs: {
        ISSUE_NUMBER: String(issue.number),
        BRANCH: issue.branch,
      },
      maxIterations,
      completionSignal: "<promise>COMPLETE</promise>",
      logging: { type: "stdout" },
    });

    const shas = result.commits.map((c) => c.sha);
    console.log(`[shft-engine] [#${issue.number}] Complete — ${shas.length} commits`);

    return { issue, status: "completed", commits: shas };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[shft-engine] [#${issue.number}] Failed: ${message}`);
    return { issue, status: "failed", commits: [], error: message };
  } finally {
    await sandbox.close();
  }
}

async function runMerge(completedBranches: string[]): Promise<MergeOutput> {
  console.log(`\n[shft-engine] Running merge phase for ${completedBranches.length} branches...`);
  try {
    const result = await run({
      agent: claudeCode(MODEL),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.resolve(promptsDir, "merge.md"),
      maxIterations: 1,
      promptArgs: {
        BRANCHES_JSON: JSON.stringify(completedBranches, null, 2),
      },
      output: Output.object({ tag: "output", schema: MergeOutput }),
      logging: { type: "stdout" },
    });

    console.log(`\n[shft-engine] Merge phase complete`);
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
      console.error(`[shft-engine] Merge phase failed: malformed agent output`);
      console.error(`[shft-engine] Tag: <${error.tag}>`);
      console.error(`[shft-engine] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[shft-engine] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}

// Orchestration workflows that need inline logic (plan, parallel, merge)
// stay here. All other workflows dispatch through the registry.
if (workflow === "plan") {
  const plan = await runPlan();
  console.log(`\n[shft-engine] Plan output (JSON):`);
  console.log(JSON.stringify(plan, null, 2));
} else if (workflow === "parallel") {
  console.log(`[shft-engine] maxParallel: ${maxParallel}`);

  const plan = await runPlan();
  const semaphore = new Semaphore(maxParallel);

  const settled = await Promise.allSettled(
    plan.issues.map((issue) =>
      semaphore.run(() => implementIssue(issue)),
    ),
  );

  const results: IssueResult[] = settled.map((s, i) => {
    if (s.status === "fulfilled") return s.value;
    const message = s.reason instanceof Error ? s.reason.message : String(s.reason);
    return { issue: plan.issues[i]!, status: "failed" as const, commits: [], error: message };
  });

  const completed = results.filter((r) => r.status === "completed" && r.commits.length > 0);
  const failed = results.filter((r) => r.status === "failed");

  console.log(`\n[shft-engine] ═══ Parallel Execution Report ═══`);
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
    await runMerge(completedBranches);
  } else {
    console.log(`\n[shft-engine] No branches to merge — skipping merge phase`);
  }
} else {
  // Try dispatch registry first, fall back to generic prompt file execution
  try {
    getWorkflow(workflow);
    await dispatch({
      workflow,
      repoDir,
      model: MODEL,
      promptsDir,
      args: {
        pr: cliArgs.pr,
        issue: cliArgs.issue,
        branch: cliArgs.branch,
        "dry-run": cliArgs.dryRun,
        "max-parallel": String(cliArgs.maxParallel),
        "max-issues": String(cliArgs.maxIssues),
      },
    });
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("Unknown workflow:")) {
      // Fallback: run generic prompt file
      const promptFile = path.resolve(promptsDir, `${workflow}.md`);
      if (!promptFile.startsWith(promptsDir + path.sep)) {
        throw new Error(`Invalid --workflow (path escapes prompts dir): ${workflow}`);
      }

      const result = await run({
        agent: claudeCode(MODEL),
        sandbox: noSandbox(),
        cwd: repoDir,
        promptFile,
        maxIterations,
        promptArgs,
        completionSignal: "<promise>COMPLETE</promise>",
        logging: { type: "stdout" },
      });

      console.log(`\n[shft-engine] Iterations: ${result.iterations.length}`);
      console.log(`[shft-engine] Commits: ${result.commits.map((c) => c.sha).join(", ") || "none"}`);
      console.log(`[shft-engine] Branch: ${result.branch}`);

      if (result.completionSignal) {
        console.log(`[shft-engine] Completion signal received`);
      }
    } else {
      throw error;
    }
  }
}
