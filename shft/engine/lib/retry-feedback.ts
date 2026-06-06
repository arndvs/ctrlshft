export function buildRetryFeedback(opts: { tag: string; rawMatched: string | null; cause: unknown }): string {
  const lines: string[] = [
    "Your previous output could not be parsed as valid structured output.",
    "",
    `Expected XML tag: <${opts.tag}>...</${opts.tag}>`,
  ];

  if (opts.rawMatched) {
    lines.push("", "Raw matched content:", "```", opts.rawMatched.slice(0, 2000), "```");
  } else {
    lines.push("", "No matching tag was found in your output.");
  }

  if (opts.cause instanceof Error) {
    lines.push("", "Validation error:", opts.cause.message.slice(0, 1000));
  }

  lines.push(
    "",
    "Please output the structured data again inside the correct XML tags.",
    `Wrap your output in <${opts.tag}>...</${opts.tag}> tags with valid JSON inside.`,
  );

  return lines.join("\n");
}
