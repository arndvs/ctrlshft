#!/usr/bin/env bash
# _build_prompt.sh — Shared prompt builder for shft scripts.
# Sources into afk.sh / once.sh. Exports $PROMPT and $PROMPT_FILE.
#
# Requires: SCRIPT_DIR set by the caller.

PREVIOUS_COMMITS=$(git log --oneline -5 2>/dev/null || echo "No commits yet")

_resolve_repo_slug() {
    local _from_env="${GH_REPO:-}"
    local _origin_url=""

    if [[ -n "$_from_env" ]]; then
        printf '%s\n' "$_from_env"
        return 0
    fi

    _origin_url=$(git remote get-url origin 2>/dev/null || true)
    if [[ -z "$_origin_url" ]]; then
        return 1
    fi

    # https://github.com/owner/repo(.git) and git@github.com:owner/repo(.git)
    printf '%s\n' "$_origin_url" \
        | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' \
        | sed -E 's#/$##'
}

_repo_slug="$(_resolve_repo_slug || true)"
if [[ -z "$_repo_slug" ]]; then
    echo "ERROR: Unable to resolve target repository for AFK issue discovery." >&2
    echo "  Set GH_REPO=owner/repo or ensure git remote 'origin' points to GitHub." >&2
    return 1
fi

if ! issues=$(gh issue list --repo "$_repo_slug" --state open --json number,title,body,comments 2>/dev/null); then
    echo "ERROR: Failed to fetch open issues for $_repo_slug." >&2
    echo "  Verify GH auth/token and GitHub App installation access for this repository." >&2
    return 1
fi

# Sanitize issue content — escape ALL XML-like tags to prevent prompt injection.
# Our wrapper tags (<github-issues>, <previous-commits>) are added AFTER this step.
issues=$(printf '%s' "$issues" | sed -E 's|<(/?[a-zA-Z][a-zA-Z0-9_-]*[^>]*)>|\&lt;\1\&gt;|g')

_target_directive=""
if [[ -n "${SHFT_TARGET_ISSUE:-}" ]]; then
    _target_directive="
PRIORITY OVERRIDE: You MUST work on issue #${SHFT_TARGET_ISSUE} first. Skip task selection priority — this issue has been explicitly targeted. If the issue does not exist in the list above, report it and stop.
"
fi

_worktree_directive=""
if [[ -n "${SHFT_ISOLATED_WORKTREE:-}" ]]; then
    _worktree_directive="
## Isolated AFK Worktree Mode

You are running in an isolated git worktree for AFK execution.

- Work only in this current worktree: ${SHFT_WORKTREE_PATH:-$PWD}
- Stay on this AFK branch for the whole run: ${SHFT_WORKTREE_BRANCH:-unknown}
- Later issues in this AFK run may depend on commits from earlier issues; build on the existing branch history instead of creating a new branch per issue.
- When completing an issue, include the AFK branch name and final commit SHA in the issue comment/closure note so the human can inspect or promote the branch later.
- Do NOT navigate back to the source checkout: ${SHFT_SOURCE_REPO_ROOT:-unknown}
"
fi

PROMPT="<github-issues>
$issues
</github-issues>

<previous-commits>
$PREVIOUS_COMMITS
</previous-commits>
${_target_directive}
$(cat "$SCRIPT_DIR/prompt.md")
${_worktree_directive}"

# Clean up internal variables — only PROMPT and PROMPT_FILE should leak to caller
unset PREVIOUS_COMMITS issues _target_directive _worktree_directive _repo_slug

# Write prompt to a temp file to avoid ARG_MAX limits on large backlogs
PROMPT_FILE=$(mktemp /tmp/shft-prompt.XXXXXX)
printf '%s' "$PROMPT" > "$PROMPT_FILE"
