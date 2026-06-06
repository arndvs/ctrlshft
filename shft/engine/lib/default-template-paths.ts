import { resolve, join } from "node:path";
import { existsSync } from "node:fs";

export interface TemplatePaths {
  promptsDir: string;
  extractionsDir: string;
  workflowsDir: string;
}

export function resolveTemplatePaths(opts: { cwd: string; overridePromptsDir?: string }): TemplatePaths {
  const sandcastleDir = resolve(opts.cwd, ".sandcastle");
  const hasSandcastle = existsSync(sandcastleDir);

  const promptsDir = opts.overridePromptsDir
    ? resolve(opts.overridePromptsDir)
    : hasSandcastle
      ? join(sandcastleDir, "prompts")
      : resolve(opts.cwd, "shft", "templates", "prompts");

  const extractionsDir = hasSandcastle
    ? join(sandcastleDir, "extractions")
    : resolve(opts.cwd, "shft", "templates", "extractions");

  const workflowsDir = hasSandcastle
    ? join(sandcastleDir, "workflows")
    : resolve(opts.cwd, "shft", "templates", "workflows");

  return { promptsDir, extractionsDir, workflowsDir };
}
