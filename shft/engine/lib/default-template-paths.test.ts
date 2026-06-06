import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { writeFileSync, mkdirSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { resolveTemplatePaths } from "./default-template-paths.js";

function makeTempDir(): string {
  const dir = join(tmpdir(), `tpl-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
  mkdirSync(dir, { recursive: true });
  return dir;
}

describe("resolveTemplatePaths", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = makeTempDir();
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it("uses .sandcastle/ paths when directory exists", () => {
    mkdirSync(join(tempDir, ".sandcastle"), { recursive: true });
    const paths = resolveTemplatePaths({ cwd: tempDir });
    expect(paths.promptsDir).toBe(join(tempDir, ".sandcastle", "prompts"));
    expect(paths.extractionsDir).toBe(join(tempDir, ".sandcastle", "extractions"));
  });

  it("falls back to shft/templates/ when no .sandcastle/", () => {
    const paths = resolveTemplatePaths({ cwd: tempDir });
    expect(paths.promptsDir).toBe(join(tempDir, "shft", "templates", "prompts"));
    expect(paths.extractionsDir).toBe(join(tempDir, "shft", "templates", "extractions"));
  });

  it("respects overridePromptsDir", () => {
    mkdirSync(join(tempDir, ".sandcastle"), { recursive: true });
    const overridePath = join(tempDir, "custom-prompts");
    const paths = resolveTemplatePaths({ cwd: tempDir, overridePromptsDir: overridePath });
    expect(paths.promptsDir).toBe(resolve(overridePath));
    // extractions still from .sandcastle since override only affects prompts
    expect(paths.extractionsDir).toBe(join(tempDir, ".sandcastle", "extractions"));
  });
});
