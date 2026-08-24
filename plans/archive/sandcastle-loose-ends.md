# Sandcastle Loose-Ends Remediation — Handoff Plan

Date: 2026-08-17
Status: All executable slices complete. Promotion PR #326 (dev→main) is open, fully green, awaiting HUMAN merge per branch policy.

## What was completed (this session)

### Producer (ctrlshft-public) — Merged
| PR | What | State |
|----|------|-------|
| #320 | Fix invalid setup-node SHA (5 files) + platform-aware mirror test + cspell words | ✅ MERGED |
| #321 | Hooks/guard branch (verify-pr-base, exploration-scope-guard, session-scope-warning) rebased 11→0 behind + skills-lock regen | ✅ MERGED |
| #322 | Dogfood repo-hygiene workflow in producer install (fixed last 5 smoke failures) | ✅ MERGED |
| #324 | Remove consumed MCRDSE working artifacts (unblocked promotion preflight) | ✅ MERGED |

**Full test suite: 21/21 suites pass** (309 smoke assertions, 8/8 mirror-regression).

### Consumer repos (8) — All synced + PRs merged
Each received: `setup-node` SHA pin, `agent-repo-hygiene.yml`, `require-regression-guard.yml`, engine updates, label updates.

| Repo | PR | State |
|------|----|-------|
| cmd-public | #14 | ✅ MERGED |
| aligned | #32 | ✅ MERGED |
| launch | #267 | ✅ MERGED |
| claude-code-copilot | #167 | ✅ MERGED |
| push | #26 | ✅ MERGED |
| mcrdse-ops | #212 | ✅ MERGED |
| rise-awake | #23 | ✅ MERGED |
| arndvs | #50 | ✅ MERGED |

After merge: all 8 report "No drift detected"; 0 bad SHA occurrences anywhere.

## Remaining: dev → main promotion (HITL — HUMAN MERGE REQUIRED)

**PR #326 is OPEN and fully green** (`dev → main`, chore: promote dev to main):
- ✅ check-bot-coauthors (removed a `Co-Authored-By: Claude Opus 4.6` trailer from `a0b50b1` via history rewrite)
- ✅ Validate main PR source (head=dev)
- ✅ engine, Validate skill files, Validate source-of-truth, Test bridge lifecycle
- ✅ Public promotion preflight passed (158 paths, no unsafe paths, no secrets)
- MCRDSE working files removed in #324 (unblocked the preflight)

**ACTION: HUMAN must merge PR #326** (per branch policy, agents never merge dev→main).

## arndvs consumer fixes (this session)
| PR | What | State |
|----|------|-------|
| #51 | `.sandcastle` → `.prettierignore` (vendored engine, 2-space) | ✅ MERGED |
| #52 | `.gitattributes` `eol=lf` (fixed local CRLF breaking format:check) | ✅ MERGED |
| #53 | `.github` → `.prettierignore` (revendor-safe; workflows are producer-owned) | ✅ MERGED |

After #53: future `update-sandcastle` revendors will NOT break arndvs's format check.

## Standing corrections to original handoff
- `GH_TOKEN` vs `GITHUB_TOKEN` — was already resolved (PR #319); both producer + installed copies use `GITHUB_TOKEN:` env key correctly.
- Merge markers in `sandcastle-drift.yml` — already resolved, none present.
- `cast-be` `baseBranch: main` — CORRECT; cast-be has no dev branch (only main). Leave as-is.
- `the-remote` — empty 0-byte `.code-workspace`, no repo exists. No action.
- `skills-lock` — validation now passes; regen script exists but is manual.

## Remaining tech debt (not blocking, optional)
- **Skills-lock auto-regeneration** in CI/commit hook (drift was caught by tests, but manual regen still required).
- **dotfiles SHA policy** (`@v4` floating tag vs pinned SHA) — decide if dotfiles should align.

## Pickup command
@working/active/sandcastle-loose-ends.md — pick up on remaining slices. Start with Slice 8: HUMAN-merge PR #326 (dev→main promotion).