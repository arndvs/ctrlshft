import { execSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";

export function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required env var: ${name}`);
  return value;
}

export function fail(message: string): never {
  const outputDir = process.env.OUTPUT_DIR ?? "/tmp";
  writeFileSync(join(outputDir, "failure_reason.txt"), message);
  throw new Error(message);
}

export function sh(cmd: string, cwd?: string): string {
  return execSync(cmd, { encoding: "utf8", cwd, stdio: ["ignore", "pipe", "pipe"] });
}

export function safeSh(cmd: string, cwd?: string): string {
  try {
    return sh(cmd, cwd);
  } catch {
    return "";
  }
}
