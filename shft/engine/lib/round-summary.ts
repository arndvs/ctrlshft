import { sh } from "./shell-helpers.js";

export function postRoundSummary(opts: { prNumber: string; round: number; fixed: string[]; deferred: string[]; skipped: string[]; cwd: string }): void {
  const lines: string[] = [
    `## Review Round ${opts.round} Summary`,
    "",
  ];

  if (opts.fixed.length > 0) {
    lines.push(`### Fixed (${opts.fixed.length})`);
    for (const id of opts.fixed) {
      lines.push(`- ${id}`);
    }
    lines.push("");
  }

  if (opts.deferred.length > 0) {
    lines.push(`### Deferred to Issues (${opts.deferred.length})`);
    for (const id of opts.deferred) {
      lines.push(`- ${id}`);
    }
    lines.push("");
  }

  if (opts.skipped.length > 0) {
    lines.push(`### Skipped (${opts.skipped.length})`);
    for (const id of opts.skipped) {
      lines.push(`- ${id}`);
    }
    lines.push("");
  }

  const total = opts.fixed.length + opts.deferred.length + opts.skipped.length;
  lines.push(`---`);
  lines.push(`_Round ${opts.round}: ${opts.fixed.length}/${total} fixed, ${opts.deferred.length} deferred, ${opts.skipped.length} skipped._`);

  const body = lines.join("\n");

  sh({
    cmd: "gh",
    args: ["pr", "comment", opts.prNumber, "--body-file", "-"],
    cwd: opts.cwd,
    input: body,
  });
}
