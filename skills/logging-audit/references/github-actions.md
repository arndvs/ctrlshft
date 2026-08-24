# Runtime reference: GitHub Actions

Load when the repo has `.github/workflows/` and the code under audit runs inside
a workflow step.

## Log output goes to stdout

GitHub parses workflow commands — `::group::`, `::endgroup::`, `::warning::`,
`::error::`, `::notice::`, `::add-mask::` — from **stdout**. That's what the
documentation specifies, and it's the channel `@actions/core` writes to.

Putting log output on stderr means grouping and annotations silently stop
working. This inverts the usual Unix convention, so flag it when audited code
sends its own logs to stderr under Actions.

Both streams are captured into the step log either way. What differs is whether
the `::` lines are interpreted or displayed literally.

## Buffering and truncation

Under a runner, stdout is a **pipe, not a TTY**. Consequences that cause real
data loss:

- **Block buffering.** Most runtimes switch from line-buffered to block-buffered
  (typically 4KB) when stdout isn't a terminal. A job that prints steadily on a
  laptop can appear silent for minutes, then dump everything at once.
- **Abrupt exit discards the buffer.** In Node, `process.exit()` with a piped
  stdout drops queued asynchronous writes — reliably eating the last thing logged
  before a crash, which is the line most needed. Python's `os._exit()` skips
  flushing for the same reason. Set an exit code and return instead.

Flags worth proposing: `process.exitCode = 1` over `process.exit(1)`; `PYTHONUNBUFFERED=1`
or `python -u`; `stdbuf -oL` for wrapped commands; explicit flush on crash paths.

The durable fix is making the shared logger write synchronously
(`fs.appendFileSync`, `flush=True`) so no caller has to remember.

## Capturing evidence beyond the step log

Step logs are transient and unstructured. If the job matters, tee to a file and
upload it:

```bash
cmd 2>&1 | tee "$RUNNER_TEMP/run.log"
```

`2>&1` must precede the pipe so stderr is merged **before** tee sees it —
otherwise unbuffered stderr and buffered stdout interleave out of order. Set
`set -o pipefail` or tee masks the real exit code.

For retries, write one log file per attempt. Otherwise attempt 2's evidence is
indistinguishable from attempt 1's.

## Shell patterns to flag

```bash
# Discards the reason. A broken token looks identical to "already exists".
gh label create "$LABEL" >/dev/null 2>&1 || true

# Tolerate the expected case, surface everything else.
if ! err=$(gh label create "$LABEL" 2>&1); then
  case "$err" in
    *"already exists"*) : ;;
    *) echo "::warning::label create failed: $err" ;;
  esac
fi
```

Also flag: missing `set -euo pipefail`; `if/elif` chains over a status value with
no `else`, which silently produce nothing for unexpected values; steps that can
fail without writing their result file, leaving downstream steps unable to
distinguish a crash from a no-op.

## Masking

Registered secrets are redacted from logs automatically, but only by exact string
match — a derived, truncated, base64'd, or reformatted secret passes through. For
values constructed at runtime, register them explicitly:

```bash
echo "::add-mask::$value"
```

`@actions/core` exposes `setSecret()` for the same thing from Node. Prefer
logging the shape over the value: `{ keyPresent: true, keyLength: 51 }`.

## Structured output for later analysis

Actions logs don't aggregate across runs. If a job's history matters, have it
write a JSONL sidecar (one object per event, run id on every line) and upload it
as an artifact. Keep it separate from the result file: the result answers *what
did this run decide*, the event stream answers *how did it get there*.
