import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { loadConfig, SandcastleConfig } from "./config.js";

describe("loadConfig", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), "sandcastle-config-"));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it("returns all defaults when config file is missing", async () => {
    const config = await loadConfig({ cwd: tempDir });

    expect(config.model).toBe("claude-opus-4-6");
    expect(config.baseBranch).toBe("main");
    expect(config.sandbox).toBe("none");
    expect(config.promptDir).toBe(".sandcastle/prompts");
    expect(config.codingStandards).toBe(".sandcastle/CODING_STANDARDS.md");
    expect(config.contextDoc).toBe("CONTEXT.md");
    expect(config.adrDir).toBe("docs/adr");
    expect(config.packageManager).toBe("npm");
  });

  it("merges partial config with defaults", async () => {
    writeFileSync(
      join(tempDir, "sandcastle.config.json"),
      JSON.stringify({ model: "claude-sonnet-4-20250514", baseBranch: "dev" }),
    );

    const config = await loadConfig({ cwd: tempDir });

    expect(config.model).toBe("claude-sonnet-4-20250514");
    expect(config.baseBranch).toBe("dev");
    expect(config.sandbox).toBe("none"); // default
    expect(config.packageManager).toBe("npm"); // default
  });

  it("throws on invalid config values", async () => {
    writeFileSync(
      join(tempDir, "sandcastle.config.json"),
      JSON.stringify({ sandbox: "invalid-value" }),
    );

    await expect(loadConfig({ cwd: tempDir })).rejects.toThrow();
  });

  it("accepts all valid sandbox values", async () => {
    for (const sandbox of ["none", "docker", "worktree"] as const) {
      writeFileSync(
        join(tempDir, "sandcastle.config.json"),
        JSON.stringify({ sandbox }),
      );
      const config = await loadConfig({ cwd: tempDir });
      expect(config.sandbox).toBe(sandbox);
    }
  });

  it("accepts all valid package manager values", async () => {
    for (const packageManager of ["npm", "pnpm", "yarn", "bun"] as const) {
      writeFileSync(
        join(tempDir, "sandcastle.config.json"),
        JSON.stringify({ packageManager }),
      );
      const config = await loadConfig({ cwd: tempDir });
      expect(config.packageManager).toBe(packageManager);
    }
  });

  it("respects environment variable overrides", async () => {
    process.env["SANDCASTLE_MODEL"] = "claude-haiku";
    try {
      const config = await loadConfig({ cwd: tempDir });
      expect(config.model).toBe("claude-haiku");
    } finally {
      delete process.env["SANDCASTLE_MODEL"];
    }
  });
});
