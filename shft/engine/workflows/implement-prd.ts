import path from "node:path";
import { run, claudeCode, createSandbox } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { PrdSlicesOutput } from "../schemas/prd-slices-output.js";
import { sh } from "../lib/shell-helpers.js";
import { Semaphore } from "../lib/semaphore.js";
import type { DispatchContext } from "../lib/types.js";

interface IssueResult {
  issueNumber: number;
  title: string;
  branch: string;
  status: "completed" | "failed";
  commits: string[];
  error?: string;
}

export async function runImplementPrd(ctx: DispatchContext): Promise<void> {
  const { repoDir, model, promptsDir, args } = ctx;
  const issueNumber = args.issue as string;

  if (!issueNumber) {
    throw new Error("--issue is required for implement-prd workflow");
  }

  const maxParallel = parseInt((args["max-parallel"] as string) ?? "4", 10);

  console.log(`[implement-prd] PRD issue: #${issueNumber}`);
  console.log(`[implement-prd] Max parallel: ${maxParallel}`);

  // Fetch sub-issues of the PRD
  const subIssuesJson = sh({
    cmd: "gh",
    args: ["issue", "list", "--search", `parent:${issueNumber}`, "--json", "number,title,state", "--state", "open", "--limit", "50"],
    cwd: repoDir,
  });

  const subIssues = JSON.parse(subIssuesJson) as Array<{ number: number; title: string; state: string }>;
  const openIssues = subIssues.filter((i) => i.state === "OPEN");

  if (openIssues.length === 0) {
    console.log(`[implement-prd] No open sub-issues found for PRD #${issueNumber}`);
    return;
  }

  console.log(`[implement-prd] Found ${openIssues.length} open sub-issues`);
  for (const issue of openIssues) {
    console.log(`  #${issue.number}: ${issue.title}`);
  }

  const semaphore = new Semaphore(maxParallel);

  const settled = await Promise.allSettled(
    openIssues.map((issue) =>
      semaphore.run(async () => {
        const branch = `ai/issue-${issue.number}`;
        console.log(`[implement-prd] [#${issue.number}] Starting on branch ${branch}`);

        const sandbox = await createSandbox({
          branch,
          sandbox: noSandbox(),
          cwd: repoDir,
        });

        try {
          const result = await sandbox.run({
            agent: claudeCode(model),
            promptFile: path.join(promptsDir, "implement-issue.md"),
            promptArgs: {
              ISSUE_NUMBER: String(issue.number),
              BRANCH: branch,
            },
            completionSignal: "<promise>COMPLETE</promise>",
            logging: { type: "stdout" },
          });

          const shas = result.commits.map((c) => c.sha);
          console.log(`[implement-prd] [#${issue.number}] Complete — ${shas.length} commits`);

          return {
            issueNumber: issue.number,
            title: issue.title,
            branch,
            status: "completed" as const,
            commits: shas,
          };
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          console.error(`[implement-prd] [#${issue.number}] Failed: ${message}`);
          return {
            issueNumber: issue.number,
            title: issue.title,
            branch,
            status: "failed" as const,
            commits: [] as string[],
            error: message,
          };
        } finally {
          await sandbox.close();
        }
      }),
    ),
  );

  const results: IssueResult[] = settled.map((s, i) => {
    if (s.status === "fulfilled") return s.value;
    const message = s.reason instanceof Error ? s.reason.message : String(s.reason);
    const issue = openIssues[i]!;
    return { issueNumber: issue.number, title: issue.title, branch: `ai/issue-${issue.number}`, status: "failed" as const, commits: [], error: message };
  });

  const completed = results.filter((r) => r.status === "completed" && r.commits.length > 0);
  const failed = results.filter((r) => r.status === "failed");

  console.log(`\n[implement-prd] ═══ PRD Execution Report ═══`);
  console.log(`  completed: ${completed.length}`);
  console.log(`  failed: ${failed.length}`);
  for (const r of completed) {
    console.log(`  ✓ #${r.issueNumber} ${r.title} (${r.commits.length} commits)`);
  }
  for (const r of failed) {
    console.log(`  ✗ #${r.issueNumber} ${r.title} — ${r.error}`);
  }
}
