import type { CommentTier, ScoredComment } from "./types.js";

interface ScoreThresholds {
  auto: number;
  confirm: number;
}

const DEFAULT_THRESHOLDS: ScoreThresholds = { auto: 75, confirm: 40 };

const HIGH_VALUE_PATTERNS = [
  /\bmissing\s+`?await\b/i,
  /\bnull\s*(?:pointer|reference|dereference)\b/i,
  /\brace\s+condition\b/i,
  /\bsql\s+injection\b/i,
  /\bxss\b/i,
  /\bmemory\s+leak\b/i,
  /\boff.by.one\b/i,
  /\bundefined\s+(?:variable|reference|is\s+not)\b/i,
  /\btype\s*error\b/i,
  /\bwrong\s+(?:type|return\s+type)\b/i,
  /\bunused\s+(?:import|variable|parameter)\b/i,
  /\bdead\s+code\b/i,
  /\bmissing\s+(?:error|null)\s*(?:handling|check)\b/i,
  /\bsecurity\s+(?:vulnerability|issue|risk|flaw)\b/i,
  /\bbreaking\s+change\b/i,
];

const LOW_VALUE_PATTERNS = [
  /\bconsider\b/i,
  /\byou\s+(?:might|could|may)\s+want\b/i,
  /\bnit(?:pick)?\b/i,
  /\bstyle\s+(?:preference|suggestion|nit)\b/i,
  /\bminor\s+(?:suggestion|nit|thing)\b/i,
  /\boptional(?:ly)?\b/i,
  /\bjust\s+a\s+thought\b/i,
  /\bfood\s+for\s+thought\b/i,
  /\bpersonal(?:ly)?\s+(?:I|prefer)\b/i,
  /\brefactor(?:ing)?\s+(?:suggestion|idea|opportunity)\b/i,
  /\bcosmetic\b/i,
  /\bformatting\b/i,
  /\bwhitespace\b/i,
];

function computeScore(body: string): { score: number; reason: string } {
  let score = 50;
  const reasons: string[] = [];

  const highHits = HIGH_VALUE_PATTERNS.filter((p) => p.test(body));
  if (highHits.length > 0) {
    score += 20 * highHits.length;
    reasons.push(`high-value pattern(s): ${highHits.length}`);
  }

  const lowHits = LOW_VALUE_PATTERNS.filter((p) => p.test(body));
  if (lowHits.length > 0) {
    score -= 20 * lowHits.length;
    reasons.push(`low-value pattern(s): ${lowHits.length}`);
  }

  // Specificity bonus: code blocks suggest a concrete fix
  const codeBlockCount = (body.match(/```/g) ?? []).length / 2;
  if (codeBlockCount >= 1) {
    score += 10;
    reasons.push("has code suggestion");
  }

  // Penalty for very short comments (likely drive-by)
  if (body.length < 30) {
    score -= 10;
    reasons.push("very short comment");
  }

  // Bonus for line-specific references
  if (/line\s+\d+/i.test(body) || /L\d+/i.test(body)) {
    score += 5;
    reasons.push("references specific line");
  }

  score = Math.max(0, Math.min(100, score));

  return { score, reason: reasons.length > 0 ? reasons.join("; ") : "baseline score" };
}

function classifyTier(score: number, thresholds: ScoreThresholds): CommentTier {
  if (score >= thresholds.auto) return "auto";
  if (score >= thresholds.confirm) return "confirm";
  return "hitl";
}

export function scoreComment(opts: { commentId: string; threadId: string; path: string | null; line: number | null; author: string; body: string; thresholds?: ScoreThresholds }): ScoredComment {
  const thresholds = opts.thresholds ?? DEFAULT_THRESHOLDS;
  const { score, reason } = computeScore(opts.body);
  const tier = classifyTier(score, thresholds);

  return {
    commentId: opts.commentId,
    threadId: opts.threadId,
    path: opts.path,
    line: opts.line,
    author: opts.author,
    body: opts.body,
    score,
    tier,
    reason,
  };
}
