import { execFileSync, type ExecFileSyncOptions } from "node:child_process";

export interface ShellResult {
  stdout: string;
  ok: boolean;
}

export function sh(opts: { cmd: string; args: string[]; cwd?: string; input?: string; silent?: boolean }): string {
  const stdio: ExecFileSyncOptions["stdio"] = opts.input
    ? ["pipe", "pipe", opts.silent ? "pipe" : "pipe"]
    : ["ignore", "pipe", opts.silent ? "pipe" : "pipe"];

  return execFileSync(opts.cmd, opts.args, {
    encoding: "utf8",
    cwd: opts.cwd,
    stdio,
    input: opts.input,
  }).trim();
}

export function trySh(opts: { cmd: string; args: string[]; cwd?: string; input?: string }): ShellResult {
  try {
    const stdout = sh({ ...opts, silent: true });
    return { stdout, ok: true };
  } catch {
    return { stdout: "", ok: false };
  }
}

export function ghApi(opts: { endpoint: string; cwd?: string; method?: string; input?: string }): string {
  const args = ["api", opts.endpoint];
  if (opts.method) {
    args.push("--method", opts.method);
  }
  if (opts.input) {
    args.push("--input", "-");
  }
  return sh({ cmd: "gh", args, cwd: opts.cwd, input: opts.input });
}

export function ghGraphql(opts: { query: string; variables: Record<string, string>; cwd?: string }): string {
  const args = ["api", "graphql"];
  for (const [key, value] of Object.entries(opts.variables)) {
    args.push("-F", `${key}=${value}`);
  }
  args.push("-f", `query=${opts.query}`);
  return sh({ cmd: "gh", args, cwd: opts.cwd });
}

export function getOwnerRepo(opts: { cwd: string }): { owner: string; repo: string } {
  const nameWithOwner = sh({ cmd: "gh", args: ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"], cwd: opts.cwd });

  const parts = nameWithOwner.split("/");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    throw new Error(`Cannot parse owner/repo from: ${nameWithOwner}`);
  }
  return { owner: parts[0], repo: parts[1] };
}
