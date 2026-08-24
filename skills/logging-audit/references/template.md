# Template: repo logging convention

Emit this into a repo when it lacks a written standard and would benefit from
one. **Localize it** — replace every placeholder with what the repo actually
uses, and delete sections that don't apply. A generic doc that doesn't match the
code is worse than none, because it teaches people the doc is decorative.

Only offer this when the repo shows signs of wanting it: multiple contributors,
an existing `docs/` or `CONTRIBUTING.md`, or a linter config. A solo project
doesn't need process.

---

## Template

````markdown
# Logging conventions

The audience is someone opening a failed run with no other context. The test for
every rule here: could they reconstruct what happened from the log alone?

## Use the logger

```
<import line for the repo's logger>
```

Never `<console.log / print / fmt.Println>` — output that bypasses the logger
misses <structure / correlation ids / redaction / flush guarantees>.

Required fields on every call: `<op>`, plus `<err>` on errors. Pass the caught
error itself, not its message — the stack and any wrapped cause are what make it
diagnosable.

`<correlationId>` is set once at startup via `<mechanism>` and inherited by
every subsequent call.

## Levels

| Level | Means |
|---|---|
| `debug` | Detail for reproducing a specific bug. Off by default. |
| `info` | A milestone a reader would look for. Roughly one per phase. |
| `warn` | Degraded but proceeding; someone should look eventually. |
| `error` | This operation failed. Pairs with a thrown or returned failure. |

`error` is not for handled, expected conditions. Reserving it for genuine
failures is what makes searching for errors useful.

## Every catch logs or rethrows — never both, never neither

```
<repo-idiomatic example: swallow / double-log / handle-and-log / wrap-and-rethrow>
```

Wrapping with `<cause mechanism>` preserves the chain so the top-level handler
logs it once with full history.

## Never log

<Secrets used by this repo, by name.> Tokens, auth headers, credential-bearing
request bodies, personal data. Log the shape instead: `{ keyPresent: true }`.

Watch the indirect paths — spreading a config object, logging an error that
embeds the request that caused it, URLs with credentials in them.

## Environment notes

<Only what applies. Buffering, flush-on-exit, stdout-vs-file, masking — pull the
specifics from the matching runtime reference.>

## Enforced in CI

<Only rules that actually run. An unenforced list is aspiration, not convention.>

| Check | Rule |
|---|---|
| No empty catch | `<rule>` |
| No `<console>` outside the logger | `<rule>` |
| Required fields on errors | enforced by types |

Keep this list short. Rules that fire often on reasonable code get disabled
inline, and then protect nothing.
````

---

## Guidance for filling it in

**Derive from the code, not from ideals.** If the repo logs `event` rather than
`op`, the doc says `event`. The goal is writing down what good already looks like
here, so it stops being tribal knowledge.

**Only claim enforcement that exists.** If nothing is wired into CI, either add
the rules in the same change or delete that section. A convention doc listing
checks that don't run is how the whole document loses authority.

**Keep it to one page.** Anything longer is reference material, not a convention,
and won't be read by the person it's aimed at.
