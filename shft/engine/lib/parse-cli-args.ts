export interface CliArgs {
  workflow: string;
  issue?: string;
  pr?: string;
  dryRun: boolean;
}

export function parseCli(argv: string[]): CliArgs {
  if (argv.length === 0) {
    throw new Error("Missing workflow name. Usage: run.ts <workflow-name> [--issue N] [--pr N] [--dry-run]");
  }

  const workflow = argv[0]!;
  let issue: string | undefined;
  let pr: string | undefined;
  let dryRun = false;

  for (let i = 1; i < argv.length; i++) {
    const arg = argv[i];

    if (arg === "--issue" && i + 1 < argv.length) {
      issue = argv[++i];
    } else if (arg === "--pr" && i + 1 < argv.length) {
      pr = argv[++i];
    } else if (arg === "--dry-run") {
      dryRun = true;
    }
  }

  return { workflow, issue, pr, dryRun };
}
