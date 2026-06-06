import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { writeFileSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { resolvePrompt, resolvePromptContent, resolveExtraction } from "./resolve-prompt.js";

function makeTempDir(): string {
  const dir = join(tmpdir(), `prompt-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
  mkdirSync(dir, { recursive: true });
  return dir;
}

describe("resolvePrompt", () => {
  let projectDir: string;
  let fallbackDir: string;

  beforeEach(() => {
    projectDir = makeTempDir();
    fallbackDir = makeTempDir();
  });

  afterEach(() => {
    rmSync(projectDir, { recursive: true, force: true });
    rmSync(fallbackDir, { recursive: true, force: true });
  });

  it("prefers project dir when file exists in both", () => {
    writeFileSync(join(projectDir, "review.md"), "project version");
    writeFileSync(join(fallbackDir, "review.md"), "fallback version");
    const path = resolvePrompt({ name: "review.md", projectDir, fallbackDir });
    expect(path).toBe(join(projectDir, "review.md"));
  });

  it("falls back when only fallback exists", () => {
    writeFileSync(join(fallbackDir, "review.md"), "fallback version");
    const path = resolvePrompt({ name: "review.md", projectDir, fallbackDir });
    expect(path).toBe(join(fallbackDir, "review.md"));
  });

  it("throws when neither exists", () => {
    expect(() => resolvePrompt({ name: "missing.md", projectDir, fallbackDir })).toThrow(/Prompt not found/);
  });
});

describe("resolvePromptContent", () => {
  let projectDir: string;
  let fallbackDir: string;

  beforeEach(() => {
    projectDir = makeTempDir();
    fallbackDir = makeTempDir();
  });

  afterEach(() => {
    rmSync(projectDir, { recursive: true, force: true });
    rmSync(fallbackDir, { recursive: true, force: true });
  });

  it("returns file content from project dir", () => {
    writeFileSync(join(projectDir, "test.md"), "hello world");
    const content = resolvePromptContent({ name: "test.md", projectDir, fallbackDir });
    expect(content).toBe("hello world");
  });
});

describe("resolveExtraction", () => {
  let projectDir: string;
  let fallbackDir: string;

  beforeEach(() => {
    projectDir = makeTempDir();
    fallbackDir = makeTempDir();
  });

  afterEach(() => {
    rmSync(projectDir, { recursive: true, force: true });
    rmSync(fallbackDir, { recursive: true, force: true });
  });

  it("returns null when neither exists", () => {
    const path = resolveExtraction({ name: "missing.md", projectDir, fallbackDir });
    expect(path).toBeNull();
  });

  it("returns fallback path when only fallback exists", () => {
    writeFileSync(join(fallbackDir, "extract.md"), "content");
    const path = resolveExtraction({ name: "extract.md", projectDir, fallbackDir });
    expect(path).toBe(join(fallbackDir, "extract.md"));
  });
});
