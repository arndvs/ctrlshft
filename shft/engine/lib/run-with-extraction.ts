import { run, Output, type RunOptions, type RunResult } from "@ai-hero/sandcastle";

interface RunWithExtractionOptions {
  /** Options for the produce phase (side effects — commits, file changes). No structured output. */
  produceOptions: Omit<RunOptions, "output">;
  /** Options for the extract phase. Uses the same cwd but a different prompt to extract structured data. */
  extractOptions: Omit<RunOptions, "output">;
  /** XML tag for the structured output. */
  tag: string;
  /** Zod schema for the structured output. */
  schema: Parameters<typeof Output.object>[0]["schema"];
}

interface ExtractionResult<T> {
  produceResult: RunResult;
  extractResult: RunResult & { output: T };
}

export async function runWithExtraction<T>(opts: RunWithExtractionOptions): Promise<ExtractionResult<T>> {
  const { produceOptions, extractOptions, tag, schema } = opts;

  // Phase 1: Produce — run agent with side effects (commits, file changes)
  const produceResult = await run(produceOptions);

  // Phase 2: Extract — run a second pass to extract structured output
  const outputDef = Output.object({ tag, schema });
  const extractResult = await run({
    ...extractOptions,
    output: outputDef,
    maxIterations: 1,
  }) as RunResult & { output: T };

  return { produceResult, extractResult };
}
