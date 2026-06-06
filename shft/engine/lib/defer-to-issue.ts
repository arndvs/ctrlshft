import { sh } from "./shell-helpers.js";

export function deferToIssue(opts: { prNumber: string; threadId: string; commentBody: string; path: string | null; line: number | null; score: number; reason: string; cwd: string }): number {
  const locationLine = opts.path
    ? `**Location:** \`${opts.path}\`${opts.line ? `:${opts.line}` : ""}`
    : "**Location:** General";

  const body = [
    `## Deferred Review Comment`,
    "",
    `**From PR:** #${opts.prNumber}`,
    locationLine,
    `**Score:** ${opts.score} (${opts.reason})`,
    "",
    "### Original Comment",
    "",
    opts.commentBody,
    "",
    "---",
    `_Automatically deferred by Sandcastle review loop. Score below auto-fix threshold._`,
  ].join("\n");

  const title = opts.path
    ? `Review: ${opts.path}${opts.line ? `:${opts.line}` : ""} (from PR #${opts.prNumber})`
    : `Review comment from PR #${opts.prNumber}`;

  const issueUrl = sh({
    cmd: "gh",
    args: ["issue", "create", "--title", title, "--body-file", "-", "--label", "review-deferred"],
    cwd: opts.cwd,
    input: body,
  });

  const numberMatch = issueUrl.match(/\/(\d+)$/);
  if (!numberMatch?.[1]) {
    throw new Error(`Failed to parse issue number from: ${issueUrl}`);
  }

  return parseInt(numberMatch[1], 10);
}
