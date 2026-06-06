import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { z } from "zod";

const SandcastleConfig = z.object({
  defaultBranch: z.string().default("main"),
  model: z.string().default("claude-sonnet-4-20250514"),
  maxIterations: z.number().int().positive().default(1),
  maxParallel: z.number().int().positive().default(4),
  maxIssues: z.number().int().positive().default(5),
  promptsDir: z.string().optional(),
  sandbox: z.enum(["none", "docker"]).default("none"),
  maxReviewRounds: z.number().int().positive().default(3),
  scoreThresholds: z.object({
    auto: z.number().int().min(0).max(100).default(75),
    confirm: z.number().int().min(0).max(100).default(40),
  }).default({}),
});

export type SandcastleConfig = z.infer<typeof SandcastleConfig>;

const ENV_OVERRIDES: Record<string, keyof SandcastleConfig> = {
  SANDCASTLE_DEFAULT_BRANCH: "defaultBranch",
  SANDCASTLE_MODEL: "model",
  SANDCASTLE_MAX_ITERATIONS: "maxIterations",
  SANDCASTLE_MAX_PARALLEL: "maxParallel",
  SANDCASTLE_MAX_ISSUES: "maxIssues",
  SANDCASTLE_PROMPTS_DIR: "promptsDir",
  SANDCASTLE_SANDBOX: "sandbox",
  SANDCASTLE_MAX_REVIEW_ROUNDS: "maxReviewRounds",
};

const NUMERIC_KEYS = new Set<string>(["maxIterations", "maxParallel", "maxIssues", "maxReviewRounds"]);

function applyEnvOverrides(config: Record<string, unknown>): Record<string, unknown> {
  const result = { ...config };

  for (const [envKey, configKey] of Object.entries(ENV_OVERRIDES)) {
    const envValue = process.env[envKey];
    if (envValue === undefined) continue;

    if (NUMERIC_KEYS.has(configKey)) {
      const parsed = parseInt(envValue, 10);
      if (!Number.isNaN(parsed)) result[configKey] = parsed;
    } else {
      result[configKey] = envValue;
    }
  }

  return result;
}

export function loadConfig(opts: { cwd: string }): SandcastleConfig {
  const configPath = resolve(opts.cwd, "sandcastle.config.json");

  let raw: Record<string, unknown> = {};
  if (existsSync(configPath)) {
    const content = readFileSync(configPath, "utf8");
    raw = JSON.parse(content) as Record<string, unknown>;
  }

  const withEnv = applyEnvOverrides(raw);
  return SandcastleConfig.parse(withEnv);
}
