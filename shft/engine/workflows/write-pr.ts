import path from "node:path";
import { run, Output, StructuredOutputError, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { WritePrOutput } from "../schemas/write-pr-output.js";
import { sh } from "../lib/shell-helpers.js";
import type { DispatchContext } from "../lib/types.js";

export async function runWritePr(ctx: DispatchContext): Promise<void> {
  const { repoDir, model, promptsDir, args } = ctx;
  const prNumber = args.pr as string | undefined;
  const branch = args.branch as string | undefined;

  const targetBranch = branch ?? (prNumber
    ? sh({ cmd: "gh", args: ["pr", "view", prNumber, "--json", "headRefName", "--jq", ".headRefName"], cwd: repoDir })
    : sh({ cmd: "git", args: ["branch", "--show-current"], cwd: repoDir }));

  console.log(`[write-pr] Branch: ${targetBranch}`);

  try {
    const result = await run({
      agent: claudeCode(model),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.join(promptsDir, "write-pr.md"),
      promptArgs: {
        BRANCH: targetBranch,
        ...(prNumber ? { PR_NUMBER: prNumber } : {}),
      },
      output: Output.object({ tag: "output", schema: WritePrOutput }),
      logging: { type: "stdout" },
    });

    if (prNumber) {
      // Update existing PR
      const updateArgs = ["pr", "edit", prNumber, "--title", result.output.title, "--body-file", "-"];
      sh({ cmd: "gh", args: updateArgs, cwd: repoDir, input: result.output.body });
      console.log(`[write-pr] Updated PR #${prNumber}`);
    } else {
      // Create new PR
      const createArgs = ["pr", "create", "--head", targetBranch, "--title", result.output.title, "--body-file", "-"];
      for (const label of result.output.labels) {
        createArgs.push("--label", label);
      }
      const prUrl = sh({ cmd: "gh", args: createArgs, cwd: repoDir, input: result.output.body });
      console.log(`[write-pr] Created PR: ${prUrl}`);
    }

    console.log(`\n[write-pr] Complete`);
    console.log(`  title: ${result.output.title}`);
    console.log(`  labels: ${result.output.labels.join(", ") || "none"}`);
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[write-pr] Failed: malformed agent output`);
      console.error(`[write-pr] Tag: <${error.tag}>`);
      console.error(`[write-pr] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[write-pr] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}
