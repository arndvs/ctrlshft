import { describe, it, expect } from "vitest";
import { parseCli } from "./parse-cli-args.js";

describe("parseCli", () => {
  it("parses workflow name as first positional arg", () => {
    const result = parseCli(["review-issue"]);
    expect(result.workflow).toBe("review-issue");
  });

  it("parses --issue flag", () => {
    const result = parseCli(["implement-issue", "--issue", "42"]);
    expect(result.workflow).toBe("implement-issue");
    expect(result.issue).toBe("42");
  });

  it("parses --pr flag", () => {
    const result = parseCli(["fix-pr-feedback", "--pr", "99"]);
    expect(result.workflow).toBe("fix-pr-feedback");
    expect(result.pr).toBe("99");
  });

  it("throws when no workflow name is provided", () => {
    expect(() => parseCli([])).toThrow("Missing workflow name");
  });

  it("parses --dry-run flag", () => {
    const result = parseCli(["plan-issue", "--issue", "5", "--dry-run"]);
    expect(result.workflow).toBe("plan-issue");
    expect(result.issue).toBe("5");
    expect(result.dryRun).toBe(true);
  });

  it("defaults dryRun to false", () => {
    const result = parseCli(["review-issue", "--issue", "1"]);
    expect(result.dryRun).toBe(false);
  });
});
