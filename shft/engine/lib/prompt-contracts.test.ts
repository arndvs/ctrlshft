import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const templatesDir = join(__dirname, "..", "..", "templates");

const extractionWorkflows = ["architecture-review", "implement-pr", "update-branch"] as const;

describe("two-phase prompt contracts", () => {
  it.each(extractionWorkflows)("keeps %s produce prompt free of structured-output tags", (workflow) => {
    const prompt = readFileSync(join(templatesDir, "prompts", `${workflow}.md`), "utf8");

    expect(prompt).not.toContain("<output>");
    expect(prompt).not.toContain("</output>");
  });

  it.each(extractionWorkflows)("keeps %s extraction prompt responsible for structured output", (workflow) => {
    const prompt = readFileSync(join(templatesDir, "extractions", `${workflow}.md`), "utf8");

    expect(prompt).toContain("<output>");
    expect(prompt).toContain("</output>");
  });
});