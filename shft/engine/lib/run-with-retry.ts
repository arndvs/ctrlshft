import { run, Output, StructuredOutputError, type RunOptions, type RunResult } from "@ai-hero/sandcastle";
import { buildRetryFeedback } from "./retry-feedback.js";

interface RunWithRetryOptions {
  runOptions: Omit<RunOptions, "output" | "resumeSession">;
  tag: string;
  schema: Parameters<typeof Output.object>[0]["schema"];
  maxRetries?: number;
}

export async function runWithRetry<T>(opts: RunWithRetryOptions): Promise<RunResult & { output: T }> {
  const { runOptions, tag, schema, maxRetries = 1 } = opts;
  const outputDef = Output.object({ tag, schema });

  let lastSessionId: string | undefined;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const result = await run({
        ...runOptions,
        output: outputDef,
        ...(lastSessionId ? { resumeSession: lastSessionId } : {}),
      } as RunOptions & { output: typeof outputDef });

      return result as RunResult & { output: T };
    } catch (error) {
      if (!(error instanceof StructuredOutputError)) {
        throw error;
      }

      if (attempt >= maxRetries) {
        throw error;
      }

      console.warn(`[run-with-retry] Attempt ${attempt + 1} failed, retrying with feedback...`);

      const feedback = buildRetryFeedback({
        tag: error.tag,
        rawMatched: error.rawMatched ?? null,
        cause: error.cause,
      });

      // Resume the failed session with corrective feedback
      const feedbackResult = await run({
        ...runOptions,
        prompt: feedback,
        maxIterations: 1,
      });

      // Extract session ID from the last iteration for resume
      const iterations = feedbackResult.iterations;
      const lastIteration = iterations[iterations.length - 1];
      if (lastIteration && "sessionId" in lastIteration) {
        lastSessionId = lastIteration.sessionId as string;
      }
    }
  }

  throw new Error("[run-with-retry] Exhausted retries without success");
}
