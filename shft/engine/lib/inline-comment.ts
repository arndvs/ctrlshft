import { ghApi } from "./shell-helpers.js";
import { parseDiffLines } from "./parse-diff-lines.js";
import { sh, trySh } from "./shell-helpers.js";

export interface InlineComment {
  path: string;
  line: number;
  side: "LEFT" | "RIGHT";
  body: string;
}

export function postInlineComment(opts: { prNumber: string; comment: InlineComment; commitSha: string; cwd: string }): void {
  const payload = JSON.stringify({
    commit_id: opts.commitSha,
    path: opts.comment.path,
    line: opts.comment.line,
    side: opts.comment.side,
    body: opts.comment.body,
  });

  ghApi({
    endpoint: `repos/{owner}/{repo}/pulls/${opts.prNumber}/comments`,
    cwd: opts.cwd,
    method: "POST",
    input: payload,
  });
}

export function postReviewWithComments(opts: { prNumber: string; comments: InlineComment[]; summary: string; commitSha: string; cwd: string }): void {
  const { cwd } = opts;

  const diffResult = trySh({ cmd: "gh", args: ["pr", "diff", opts.prNumber], cwd });
  const diffLines = diffResult.ok ? parseDiffLines(diffResult.stdout) : new Map<string, Set<number>>();

  const validComments = opts.comments.filter((c) => {
    const fileLines = diffLines.get(c.path);
    if (!fileLines) {
      console.warn(`[inline-comment] Dropping ${c.path}:${c.line} — file not in diff`);
      return false;
    }
    if (!fileLines.has(c.line)) {
      console.warn(`[inline-comment] Dropping ${c.path}:${c.line} — line not in diff hunks`);
      return false;
    }
    return true;
  });

  const payload = JSON.stringify({
    commit_id: opts.commitSha,
    event: "COMMENT",
    body: opts.summary,
    comments: validComments.map((c) => ({
      path: c.path,
      line: c.line,
      side: c.side,
      body: c.body,
    })),
  });

  ghApi({
    endpoint: `repos/{owner}/{repo}/pulls/${opts.prNumber}/reviews`,
    cwd,
    input: payload,
  });
}
