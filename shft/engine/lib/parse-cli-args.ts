export interface CliArgs {
  workflow: string;
  issue?: string;
  issueTitle?: string;
  pr?: string;
  branch?: string;
  baseRef?: string;
  prdNumber?: string;
  prdTitle?: string;
  dryRun: boolean;
}

export function parseCli(argv: string[]): CliArgs {
  if (argv.length === 0) {
    throw new Error("Missing workflow name. Usage: run.ts <workflow-name> [--issue N] [--issue-title TEXT] [--pr N] [--branch REF] [--base-ref REF] [--prd-number N] [--prd-title TEXT] [--dry-run]");
  }

  const workflow = argv[0]!;
  let issue: string | undefined;
  let issueTitle: string | undefined;
  let pr: string | undefined;
  let branch: string | undefined;
  let baseRef: string | undefined;
  let prdNumber: string | undefined;
  let prdTitle: string | undefined;
  let dryRun = false;

  for (let i = 1; i < argv.length; i++) {
    const arg = argv[i];

    if (arg === "--issue" && i + 1 < argv.length) {
      issue = argv[++i];
    } else if (arg === "--issue-title" && i + 1 < argv.length) {
      issueTitle = argv[++i];
    } else if (arg === "--pr" && i + 1 < argv.length) {
      pr = argv[++i];
    } else if (arg === "--branch" && i + 1 < argv.length) {
      branch = argv[++i];
    } else if (arg === "--base-ref" && i + 1 < argv.length) {
      baseRef = argv[++i];
    } else if (arg === "--prd-number" && i + 1 < argv.length) {
      prdNumber = argv[++i];
    } else if (arg === "--prd-title" && i + 1 < argv.length) {
      prdTitle = argv[++i];
    } else if (arg === "--dry-run") {
      dryRun = true;
    }
  }

  return { workflow, issue, issueTitle, pr, branch, baseRef, prdNumber, prdTitle, dryRun };
}
