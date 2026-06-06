import { ghGraphql } from "./shell-helpers.js";

const RESOLVE_MUTATION = `
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) {
    thread { id isResolved }
  }
}`;

export function resolveThread(opts: { threadId: string; cwd: string }): void {
  ghGraphql({
    query: RESOLVE_MUTATION,
    variables: { threadId: opts.threadId },
    cwd: opts.cwd,
  });
}

export function resolveThreads(opts: { threadIds: string[]; cwd: string }): { resolved: string[]; failed: string[] } {
  const resolved: string[] = [];
  const failed: string[] = [];

  for (const threadId of opts.threadIds) {
    try {
      resolveThread({ threadId, cwd: opts.cwd });
      resolved.push(threadId);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.warn(`[resolve-threads] Failed to resolve ${threadId}: ${message}`);
      failed.push(threadId);
    }
  }

  return { resolved, failed };
}
