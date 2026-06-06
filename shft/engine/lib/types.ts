export interface EngineContext {
  repoDir: string;
  model: string;
  promptsDir: string;
}

export interface DispatchContext extends EngineContext {
  workflow: string;
  args: Record<string, string | boolean | undefined>;
}

export type WorkflowRunner = (ctx: DispatchContext) => Promise<void>;

export type CommentTier = "auto" | "confirm" | "hitl";

export interface ScoredComment {
  commentId: string;
  threadId: string;
  path: string | null;
  line: number | null;
  author: string;
  body: string;
  score: number;
  tier: CommentTier;
  reason: string;
}

export interface RoundResult {
  round: number;
  fixed: string[];
  deferred: string[];
  skipped: string[];
}
