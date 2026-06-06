import path from "node:path";
import { run, claudeCode, createSandbox } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { sh } from "../lib/shell-helpers.js";
import type { DispatchContext } from "../lib/types.js";

export async function runImplementIssue(ctx: DispatchContext): Promise<void> {
  const { repoDir, model, promptsDir, args } = ctx;
  const issueNumber = args.issue as string;

  if (!issueNumber) {
    throw new Error("--issue is required for implement-issue workflow");
  }

  const branch = (args.branch as string | undefined) ?? `ai/issue-${issueNumber}`;

  console.log(`[implement-issue] Issue: #${issueNumber}`);
  console.log(`[implement-issue] Branch: ${branch}`);

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
        ISSUE_NUMBER: issueNumber,
        BRANCH: branch,
      },
      completionSignal: "<promise>COMPLETE</promise>",
      logging: { type: "stdout" },
    });

    const shas = result.commits.map((c) => c.sha);
    console.log(`\n[implement-issue] Complete`);
    console.log(`  commits: ${shas.length}`);
    console.log(`  branch: ${branch}`);

    if (shas.length === 0) {
      console.warn(`[implement-issue] No commits produced — issue may not have been implemented`);
    }

    if (result.completionSignal) {
      console.log(`[implement-issue] Completion signal received`);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[implement-issue] Failed: ${message}`);
    process.exit(1);
  } finally {
    await sandbox.close();
  }
}
