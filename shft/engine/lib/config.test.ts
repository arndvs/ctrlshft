import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { writeFileSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { loadConfig } from "./config.js";

function makeTempDir(): string {
  const dir = join(tmpdir(), `config-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
  mkdirSync(dir, { recursive: true });
  return dir;
}

describe("loadConfig", () => {
  let tempDir: string;
  const savedEnv: Record<string, string | undefined> = {};

  beforeEach(() => {
    tempDir = makeTempDir();
    for (const key of Object.keys(process.env)) {
      if (key.startsWith("SANDCASTLE_")) {
        savedEnv[key] = process.env[key];
        delete process.env[key];
      }
    }
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
    for (const [key, value] of Object.entries(savedEnv)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  });

  it("returns defaults when no config file exists", () => {
    const config = loadConfig({ cwd: tempDir });
    expect(config.defaultBranch).toBe("main");
    expect(config.model).toBe("claude-sonnet-4-20250514");
    expect(config.maxIterations).toBe(1);
    expect(config.maxParallel).toBe(4);
    expect(config.sandbox).toBe("none");
    expect(config.maxReviewRounds).toBe(3);
    expect(config.scoreThresholds.auto).toBe(75);
    expect(config.scoreThresholds.confirm).toBe(40);
  });

  it("reads from sandcastle.config.json", () => {
    writeFileSync(join(tempDir, "sandcastle.config.json"), JSON.stringify({
      defaultBranch: "dev",
      maxParallel: 2,
      scoreThresholds: { auto: 80, confirm: 50 },
    }));
    const config = loadConfig({ cwd: tempDir });
    expect(config.defaultBranch).toBe("dev");
    expect(config.maxParallel).toBe(2);
    expect(config.scoreThresholds.auto).toBe(80);
    expect(config.scoreThresholds.confirm).toBe(50);
  });

  it("applies env overrides over file values", () => {
    writeFileSync(join(tempDir, "sandcastle.config.json"), JSON.stringify({
      defaultBranch: "dev",
      maxParallel: 2,
    }));
    process.env["SANDCASTLE_MAX_PARALLEL"] = "8";
    process.env["SANDCASTLE_DEFAULT_BRANCH"] = "staging";

    const config = loadConfig({ cwd: tempDir });
    expect(config.maxParallel).toBe(8);
    expect(config.defaultBranch).toBe("staging");
  });

  it("ignores invalid numeric env values", () => {
    process.env["SANDCASTLE_MAX_PARALLEL"] = "not-a-number";
    const config = loadConfig({ cwd: tempDir });
    expect(config.maxParallel).toBe(4);
  });
});
