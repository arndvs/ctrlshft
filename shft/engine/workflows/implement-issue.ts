import path from "node:path";
import { fileURLToPath } from "node:url";
import { run, claudeCode } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { loadConfig } from "../lib/config.js";
import { resolvePrompt, configPromptArgs } from "../lib/resolve-prompt.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultTemplatesDir = path.resolve(__dirname, "..", "..", "templates", "prompts");

export interface ImplementIssueResult {
  commitCount: number;
}

export async function runImplementIssue(opts: {
  issueNumber: string;
  issueTitle: string;
  branch: string;
  repoDir: string;
  model?: string;
  templatesDir?: string;
}): Promise<ImplementIssueResult> {
  const config = await loadConfig({ cwd: opts.repoDir });
  const model = opts.model ?? config.model;
  const templatesDir = opts.templatesDir ?? defaultTemplatesDir;

  console.log(`[implement-issue] Issue #${opts.issueNumber} — ${opts.issueTitle}`);
  console.log(`[implement-issue] Branch: ${opts.branch}`);

  const promptFile = await resolvePrompt({ name: "implement-issue", config, repoDir: opts.repoDir, templatesDir });

  const result = await run({
    name: `implement-issue-#${opts.issueNumber}`,
    agent: claudeCode(model),
    sandbox: noSandbox(),
    cwd: opts.repoDir,
    promptFile,
    promptArgs: {
      ...configPromptArgs(config),
      ISSUE_NUMBER: opts.issueNumber,
      ISSUE_TITLE: opts.issueTitle,
      BRANCH: opts.branch,
    },
    logging: { type: "stdout" },
  });

  console.log(`[implement-issue] Finished issue #${opts.issueNumber}. Commits this run: ${result.commits.length}`);

  return { commitCount: result.commits.length };
}