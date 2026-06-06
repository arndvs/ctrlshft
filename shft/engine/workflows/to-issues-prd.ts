import path from "node:path";
import { run, Output, StructuredOutputError, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { PrdSlicesOutput } from "../schemas/prd-slices-output.js";
import { sh } from "../lib/shell-helpers.js";
import type { DispatchContext } from "../lib/types.js";

export async function runToIssuesPrd(ctx: DispatchContext): Promise<void> {
  const { repoDir, model, promptsDir, args } = ctx;
  const issueNumber = args.issue as string;
  const dryRun = args["dry-run"] === true;

  if (!issueNumber) {
    throw new Error("--issue is required for to-issues-prd workflow");
  }

  console.log(`[to-issues-prd] Reading PRD from issue #${issueNumber}...`);

  const prdJson = sh({
    cmd: "gh",
    args: ["issue", "view", issueNumber, "--json", "title,body"],
    cwd: repoDir,
  });
  const prd = JSON.parse(prdJson) as { title: string; body: string };

  console.log(`[to-issues-prd] PRD: ${prd.title}`);

  try {
    const result = await run({
      agent: claudeCode(model),
      sandbox: noSandbox(),
      cwd: repoDir,
      promptFile: path.join(promptsDir, "to-issues-prd.md"),
      promptArgs: {
        ISSUE_NUMBER: issueNumber,
      },
      output: Output.object({ tag: "output", schema: PrdSlicesOutput }),
      logging: { type: "stdout" },
    });

    console.log(`\n[to-issues-prd] Generated ${result.output.slices.length} slices`);

    if (dryRun) {
      console.log(`[to-issues-prd] DRY RUN — printing slices without creating issues:\n`);
      for (const slice of result.output.slices) {
        console.log(`  [${slice.type}] ${slice.title}`);
        console.log(`    ${slice.whatToBuild}`);
        for (const ac of slice.acceptanceCriteria) {
          console.log(`    - [ ] ${ac}`);
        }
        if (slice.blockedBy.length > 0) {
          console.log(`    Blocked by: ${slice.blockedBy.join(", ")}`);
        }
        console.log();
      }
      return;
    }

    const createdIssues = new Map<string, number>();

    for (const slice of result.output.slices) {
      const blockedByNumbers = slice.blockedBy
        .map((title) => createdIssues.get(title))
        .filter((n): n is number => n != null);

      const blockedByLine = blockedByNumbers.length > 0
        ? `**Blocked by:** ${blockedByNumbers.map((n) => `#${n}`).join(", ")}`
        : "";

      const body = [
        `# ${slice.title}`,
        "",
        `**Type:** ${slice.type}`,
        `**Parent PRD:** #${issueNumber}`,
        ...(blockedByLine ? [blockedByLine] : []),
        "",
        "## Description",
        "",
        slice.whatToBuild,
        "",
        "## Acceptance Criteria",
        "",
        ...slice.acceptanceCriteria.map((ac) => `- [ ] ${ac}`),
      ].join("\n");

      const issueUrl = sh({
        cmd: "gh",
        args: ["issue", "create", "--title", slice.title, "--body-file", "-"],
        cwd: repoDir,
        input: body,
      });

      const numberMatch = issueUrl.match(/\/(\d+)$/);
      if (!numberMatch?.[1]) {
        throw new Error(`Failed to parse issue number from: ${issueUrl}`);
      }
      const newNumber = parseInt(numberMatch[1], 10);
      createdIssues.set(slice.title, newNumber);

      console.log(`[to-issues-prd] Created #${newNumber}: ${slice.title}`);

      sh({
        cmd: "gh",
        args: ["issue", "edit", String(newNumber), "--add-parent", issueNumber],
        cwd: repoDir,
      });
    }

    console.log(`\n[to-issues-prd] Complete — created ${createdIssues.size} issues as sub-issues of #${issueNumber}`);
  } catch (error) {
    if (error instanceof StructuredOutputError) {
      console.error(`[to-issues-prd] Failed: malformed agent output`);
      console.error(`[to-issues-prd] Tag: <${error.tag}>`);
      console.error(`[to-issues-prd] Raw matched: ${error.rawMatched ?? "(no match found)"}`);
      if (error.cause) console.error(`[to-issues-prd] Cause:`, error.cause);
      process.exit(1);
    }
    throw error;
  }
}
