import { existsSync, readFileSync } from "node:fs";
import { resolve, join } from "node:path";

export function resolvePrompt(opts: { name: string; projectDir: string; fallbackDir: string }): string {
  const projectPath = resolve(opts.projectDir, opts.name);
  if (existsSync(projectPath)) {
    return projectPath;
  }

  const fallbackPath = resolve(opts.fallbackDir, opts.name);
  if (existsSync(fallbackPath)) {
    return fallbackPath;
  }

  throw new Error(`Prompt not found: ${opts.name} (searched ${opts.projectDir} and ${opts.fallbackDir})`);
}

export function resolvePromptContent(opts: { name: string; projectDir: string; fallbackDir: string }): string {
  const filePath = resolvePrompt(opts);
  return readFileSync(filePath, "utf8");
}

export function resolveExtraction(opts: { name: string; projectDir: string; fallbackDir: string }): string | null {
  const projectPath = resolve(opts.projectDir, opts.name);
  if (existsSync(projectPath)) {
    return projectPath;
  }

  const fallbackPath = resolve(opts.fallbackDir, opts.name);
  if (existsSync(fallbackPath)) {
    return fallbackPath;
  }

  return null;
}
