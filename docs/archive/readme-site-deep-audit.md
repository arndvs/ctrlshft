# README + Site Deep Audit (2026-04-21)

Scope: `README.md`, `site/index.html`, and parity with shipped scripts/flags in `bin/` and `shft/`.

## Executive summary

The docs are directionally strong, but there are concrete parity drifts after Slice 4–5 landed:

1. A broken roadmap link in `README.md`.
2. A runtime prerequisite naming mismatch between README and site (`srt` vs `sbx`).
3. Missing user-facing documentation for newly shipped bootstrap/client-scope tooling.

## Findings (evidence-based)

### High

1. **Broken link in README roadmap section (pre-fix/historical evidence)**
   - Evidence: at audit time, `README.md:696` linked to `working/observability-benchmarking-plan.md`.
   - Validation: that path did not exist and was not tracked at the time of audit.
   - Impact: before this PR's README fix, external users could hit a 404 / dead reference from core roadmap content.

2. **Prerequisite mismatch between README and site (pre-fix/historical evidence)**
   - Evidence: at audit time:
     - `README.md:791` referenced `srt` (`@anthropic-ai/sandbox-runtime`).
     - `site/index.html:2200` claimed `sbx` was required.
     - Runtime scripts used `srt` (`shft/afk.sh`, `bin/validate-env.sh`).
   - Impact: before this PR's site fix, installation docs were contradictory.
   - Resolution: site updated from `sbx` to `srt` in this PR.

### Medium

3. **README does not document newly shipped scripts from Slice 4–5**
   - Evidence: no occurrences in `README.md` for:
     - `detect-client.sh`
     - `new-client.sh`
     - `migrate.sh`
     - `uninstall.sh`
     - `_adopt.sh`
   - Impact: discoverability gap and hidden capabilities.

4. **Site install narrative does not mention new bootstrap modes**
   - Evidence:
     - `bootstrap --help` includes `--adopt`, `--minimal`, `--check`, `--force`.
     - `site/index.html` does not mention these modes.
   - Impact: users miss safe migration/minimal setup paths.

## Recommended fix order

1. Fix high-severity parity drift first:
   - Replace/remove dead roadmap link.
   - Normalize prerequisite naming to `srt` wherever the site still says `sbx`.
2. Update command inventory/discoverability:
   - Add a "Migration and client-scope tools" section to README.
   - Add concise install-mode guidance to site install step.
3. Run final parity checks:
   - `bash bin/bootstrap.sh --help`
   - `grep` parity pass for documented script names.

## What else should be audited next

1. **Contributing and templates parity**
   - Ensure `CONTRIBUTING.md` references current default branch and current automation behavior.
2. **Hook docs parity**
   - Cross-check `hooks/settings-hooks.json` and hook script behavior against README/site hook claims.
3. **Validation/guardrail docs parity**
   - Ensure `validate-env.sh` and `validate-symlinks.sh` behavior is reflected in Troubleshooting + Installation sections.
4. **Client-scope docs set completeness**
   - Ensure `clients/README.md`, `CLAUDE.base.md` active-client include, and `.gitignore` behavior are described consistently.
5. **External-link integrity**
   - Link-check all GitHub references in `README.md` and `site/index.html`.

## Exit criteria for documentation parity

- No dead internal links in README/site.
- README/site command names match executable script behavior.
- Slice 4–5 user-facing capabilities are discoverable in README and site install flows.
- A single, explicit source-of-truth statement remains consistent across docs.