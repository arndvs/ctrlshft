import { parseArgs } from "node:util";

export interface CliArgs {
  repo: string;
  workflow: string;
  pr?: string;
  issue?: string;
  branch?: string;
  maxIterations: number;
  maxParallel: number;
  maxIssues: number;
  dryRun: boolean;
  model?: string;
  promptsDir?: string;
}

export function parseCliArgs(argv?: string[]): CliArgs {
  const { values } = parseArgs({
    args: argv,
    options: {
      repo: { type: "string" },
      workflow: { type: "string", default: "implement" },
      pr: { type: "string" },
      issue: { type: "string" },
      branch: { type: "string" },
      "max-iterations": { type: "string", default: "1" },
      "max-parallel": { type: "string", default: "4" },
      "max-issues": { type: "string", default: "5" },
      "dry-run": { type: "boolean", default: false },
      model: { type: "string" },
      "prompts-dir": { type: "string" },
    },
    strict: true,
  });

  if (!values.repo) {
    throw new Error("--repo is required");
  }

  const maxIterations = parseInt(values["max-iterations"] ?? "1", 10);
  if (Number.isNaN(maxIterations) || maxIterations < 1) {
    throw new Error(`--max-iterations must be a positive integer, got: ${values["max-iterations"]}`);
  }

  const maxParallel = parseInt(values["max-parallel"] ?? "4", 10);
  if (Number.isNaN(maxParallel) || maxParallel < 1) {
    throw new Error(`--max-parallel must be a positive integer, got: ${values["max-parallel"]}`);
  }

  const maxIssues = parseInt(values["max-issues"] ?? "5", 10);
  if (Number.isNaN(maxIssues) || maxIssues < 1) {
    throw new Error(`--max-issues must be a positive integer, got: ${values["max-issues"]}`);
  }

  const workflow = values.workflow ?? "implement";
  if (!/^[a-z0-9-]+$/i.test(workflow)) {
    throw new Error(`Invalid --workflow: ${workflow}`);
  }

  return {
    repo: values.repo,
    workflow,
    pr: values.pr,
    issue: values.issue,
    branch: values.branch,
    maxIterations,
    maxParallel,
    maxIssues,
    dryRun: values["dry-run"] ?? false,
    model: values.model,
    promptsDir: values["prompts-dir"],
  };
}
