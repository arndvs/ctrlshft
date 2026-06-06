import path from "node:path";
import { dispatch } from "./lib/dispatch.js";
import { parseCliArgs } from "./lib/parse-cli-args.js";
import { loadConfig } from "./lib/config.js";
import { resolveTemplatePaths } from "./lib/default-template-paths.js";
import { registerAllWorkflows } from "./workflows/register.js";

registerAllWorkflows();

const cliArgs = parseCliArgs();
const config = loadConfig({ cwd: cliArgs.repo });

const repoDir = path.resolve(cliArgs.repo);
const model = cliArgs.model ?? process.env["ANTHROPIC_MODEL"] ?? config.model;
const workflow = cliArgs.workflow;

const { promptsDir } = cliArgs.promptsDir
  ? { promptsDir: path.resolve(cliArgs.promptsDir) }
  : resolveTemplatePaths({ cwd: repoDir });

console.log(`[shft-engine] repo: ${repoDir}`);
console.log(`[shft-engine] workflow: ${workflow}`);
console.log(`[shft-engine] model: ${model}`);

await dispatch({
  workflow,
  repoDir,
  model,
  promptsDir,
  args: {
    pr: cliArgs.pr,
    issue: cliArgs.issue,
    branch: cliArgs.branch,
    "dry-run": cliArgs.dryRun,
    "max-iterations": String(cliArgs.maxIterations),
    "max-parallel": String(cliArgs.maxParallel),
    "max-issues": String(cliArgs.maxIssues),
  },
});
