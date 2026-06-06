import path from "node:path";
import { run, Output, StructuredOutputError, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { sh } from "../lib/shell-helpers.js";
import type { DispatchContext } from "../lib/types.js";

export async function runReviewIssue(ctx: DispatchContext): Promise<void> {
  const { repoDir, model, promptsDir, args } = ctx;
  const issueNumber = args.issue as string;

  if (!issueNumber) {
    throw new Error("--issue is required for review-issue workflow");
  }

  console.log(`[review-issue] Reviewing issue #${issueNumber}...`);

  const issueJson = sh({
    cmd: "gh",
    args: ["issue", "view", issueNumber, "--json", "title,body,labels,state"],
    cwd: repoDir,
  });
  const issue = JSON.parse(issueJson) as { title: string; body: string; labels: Array<{ name: string }>; state: string };

  console.log(`[review-issue] Issue: ${issue.title}`);
  console.log(`[review-issue] State: ${issue.state}`);
  console.log(`[review-issue] Labels: ${issue.labels.map((l) => l.name).join(", ") || "none"}`);

  const result = await run({
    agent: claudeCode(model),
    sandbox: noSandbox(),
    cwd: repoDir,
    promptFile: path.join(promptsDir, "review-issue.md"),
    promptArgs: {
      ISSUE_NUMBER: issueNumber,
    },
    completionSignal: "<promise>COMPLETE</promise>",
    logging: { type: "stdout" },
  });

  console.log(`\n[review-issue] Complete`);

  if (result.completionSignal) {
    console.log(`[review-issue] Completion signal received`);
  }
}
