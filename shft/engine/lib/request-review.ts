import { trySh } from "./shell-helpers.js";

export function requestReview(opts: { prNumber: string; reviewer: string; cwd: string }): boolean {
  const result = trySh({
    cmd: "gh",
    args: ["pr", "edit", opts.prNumber, "--add-reviewer", opts.reviewer],
    cwd: opts.cwd,
  });

  if (!result.ok) {
    console.warn(`[request-review] Failed to request review from ${opts.reviewer} on PR #${opts.prNumber}`);
  }

  return result.ok;
}

export function requestCopilotReview(opts: { prNumber: string; cwd: string }): boolean {
  return requestReview({ prNumber: opts.prNumber, reviewer: "copilot", cwd: opts.cwd });
}
