# Runtime reference: containers and serverless

Load when the repo has a `Dockerfile`, Kubernetes manifests, ECS task
definitions, `serverless.yml`, or Lambda/Cloud Run handlers.

## stdout is the transport

The container convention is that a process logs to stdout and stderr and does
nothing else. A collector — the Docker log driver, a k8s node agent, Fluent Bit,
CloudWatch — picks it up from there.

This inverts advice that makes sense in CI:

- **Don't write log files.** A sidecar file inside a container is invisible to
  the collector and vanishes with the container. Flag code that writes logs to
  disk in a containerised service; it's usually a leftover from a VM deployment.
- **Don't rotate or manage retention in-process.** That's the platform's job, and
  in-process rotation on an ephemeral filesystem does nothing useful.
- **One event per line.** Collectors split on newlines. A multi-line log entry
  becomes several unrelated records.

Structured JSON to stdout is the default worth recommending, since every
mainstream collector parses it into queryable fields.

## Multi-line stack traces

The most common real breakage. A stack trace printed raw becomes N separate log
records, none of which carries the error message, and the trace can't be
reassembled in the query UI.

Fix by serialising the error into a single JSON record with the stack as a string
field. All the structured loggers do this correctly — `pino`, `zap`, `zerolog`,
`slog`, `structlog` — which is a strong argument for routing exception handling
through the house logger rather than printing.

## Buffering and shutdown

- Non-TTY stdout is block-buffered here too. Flag `python` without `-u` or
  `PYTHONUNBUFFERED`, and any runtime with an async transport on a path that can
  terminate abruptly.
- **SIGTERM.** Orchestrators send SIGTERM, wait a grace period, then SIGKILL.
  Logs buffered at SIGKILL are gone. Code with an async log transport needs a
  shutdown handler that flushes; flag its absence in services that handle
  signals at all.
- **Lambda freezes between invocations.** Anything buffered when the handler
  returns may not appear until the next invocation, or ever. Log synchronously,
  or flush before returning.

## Correlation

In a distributed system this is the difference between a usable log and a pile of
lines. Check for a trace or request id propagated across service boundaries —
`traceparent` under W3C Trace Context, or the platform's own header. Flag handlers
that log without it when the rest of the codebase propagates one.

If the repo uses OpenTelemetry, logs should carry trace and span ids so they join
against traces. Emitting both independently, with no shared id, is a common and
costly miss.

## Levels and volume

Per-request logging at `info` is affordable at low traffic and ruinous at high
traffic — both in collector cost and in signal. Look for level configuration by
environment, and for sampling on high-frequency paths.

Flag `debug` logging that can't be switched on in production without a redeploy.
Being unable to raise verbosity on a running service is what turns a one-hour
investigation into a one-week one.

## Secrets

No automatic redaction exists here — unlike CI, nothing is scrubbing the stream.
Whatever is logged is what lands in the aggregator, where it's typically
searchable by a much wider audience and retained for months. Treat secret
exposure findings as more severe in this environment, not less.
