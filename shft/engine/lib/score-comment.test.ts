import { describe, it, expect } from "vitest";
import { scoreComment } from "./score-comment.js";

describe("scoreComment", () => {
  const base = { commentId: "c1", threadId: "t1", path: "src/index.ts", line: 10, author: "bot" };

  it("classifies high-value comments as auto tier", () => {
    const result = scoreComment({ ...base, body: "There is a missing `await` before this async call on line 10" });
    expect(result.tier).toBe("auto");
    expect(result.score).toBeGreaterThanOrEqual(75);
  });

  it("classifies vague suggestions as hitl tier", () => {
    const result = scoreComment({ ...base, body: "Consider refactoring this" });
    expect(result.tier).toBe("hitl");
    expect(result.score).toBeLessThan(40);
  });

  it("classifies moderate comments as confirm tier", () => {
    const result = scoreComment({ ...base, body: "This function could benefit from better error handling to catch edge cases." });
    expect(result.tier).toBe("confirm");
    expect(result.score).toBeGreaterThanOrEqual(40);
    expect(result.score).toBeLessThan(75);
  });

  it("boosts score for comments with code blocks", () => {
    const withCode = scoreComment({ ...base, body: "Fix this:\n```\nconst x = await foo();\n```" });
    const without = scoreComment({ ...base, body: "Fix this: const x = await foo();" });
    expect(withCode.score).toBeGreaterThan(without.score);
  });

  it("penalizes very short comments", () => {
    const short = scoreComment({ ...base, body: "ok" });
    const longer = scoreComment({ ...base, body: "This looks correct but you should verify the edge case when input is empty." });
    expect(short.score).toBeLessThan(longer.score);
  });

  it("respects custom thresholds", () => {
    const result = scoreComment({
      ...base,
      body: "This needs fixing",
      thresholds: { auto: 90, confirm: 60 },
    });
    // With baseline 50, no high/low patterns, this should be below 60
    expect(result.tier).toBe("hitl");
  });

  it("detects security keywords", () => {
    const result = scoreComment({ ...base, body: "This is vulnerable to SQL injection attacks. Missing null check on the user input at line 42." });
    expect(result.tier).toBe("auto");
    expect(result.score).toBeGreaterThanOrEqual(75);
  });

  it("clamps score to 0-100 range", () => {
    // Multiple low-value patterns should not go below 0
    const result = scoreComment({
      ...base,
      body: "nit: consider optional formatting, personally I prefer whitespace cosmetic changes",
    });
    expect(result.score).toBeGreaterThanOrEqual(0);
    expect(result.score).toBeLessThanOrEqual(100);
  });

  it("provides a reason string", () => {
    const result = scoreComment({ ...base, body: "Missing await on line 42" });
    expect(result.reason).toBeTruthy();
    expect(typeof result.reason).toBe("string");
  });
});
