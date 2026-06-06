import path from "node:path";
import { run, Output, StructuredOutputError, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { UpdateBranchOutput } from "../schemas/update-branch-output.js";
import { sh } from "../lib/shell-helpers.js";
import type { DispatchContext } from "../lib/types.js";

export async function runUpdateBranch(ctx: DispatchContext): Promise<void> {
  const { repoDir, model, promptsDir, args } = ctx;
  const prNumber = args.pr as string | undefined;
  const branch = args.branch as string | undefined;

  const targetBranch = branch ?? (prNumber
    ? sh({ cmd: "gh", args: ["pr", "view", prNumber, "--json", "headRefName", "--jq", ".headRefName"], cwd: repoDir })
    : sh({ cmd: "git", args: ["branch", "--show-current"], cwd: repoDir }));

  console.log(`[update-branch] Branch: ${targetBranch}`);

  try {
    const result = await run({
      agent: claudeCode(model),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.join(promptsDir, "update-branch.md"),
      promptArgs: {
        BRANCH: targetBranch,
        ...(prNumber ? { PR_NUMBER: prNumber } : {}),
      },
      output: Output.object({ tag: "output", schema: UpdateBranchOutput }),
      logging: { type: "stdout" },
    });

    console.log(`\n[update-branch] Complete`);
    console.log(`  strategy: ${result.output.strategy}`);
    console.log(`  success: ${result.output.success}`);
    if (result.output.conflictsResolved.length > 0) {
      console.log(`  conflicts resolved: ${result.output.conflictsResolved.join(", ")}`);
    }
    if (result.output.conflictsRemaining.length > 0) {
      console.log(`  conflicts remaining: ${result.output.conflictsRemaining.join(", ")}`);
    }
    if (result.output.commitSha) {
      console.log(`  commit: ${result.output.commitSha}`);
    }

    if (!result.output.success) {
      console.error(`[update-branch] Branch update failed with unresolved conflicts`);
      process.exit(1);
    }
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[update-branch] Failed: malformed agent output`);
      console.error(`[update-branch] Tag: <${error.tag}>`);
      console.error(`[update-branch] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[update-branch] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}
