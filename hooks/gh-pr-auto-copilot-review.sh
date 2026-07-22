#!/usr/bin/env bash
# FAIL_MODE: open
# gh-pr-auto-copilot-review.sh — PostToolUse hook: auto-request Copilot review after `gh pr create`.
#
# Receives Claude Code PostToolUse JSON on stdin (matcher: Bash).
# If the command was a successful `gh pr create`, this requests the copilot-pull-request-reviewer
# app on the newly created PR via `gh pr edit --add-reviewer` unless Copilot is already
# present in the PR's requested_reviewers.

set -Eeuo pipefail
trap 'exit 0' ERR  # fail-open: any error → allow

if ! command -v jq &>/dev/null; then
    exit 0
fi

if ! command -v gh &>/dev/null; then
    exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# cd into the hook event's working directory
EVENT_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [[ -n "$EVENT_CWD" ]]; then
    cd "$EVENT_CWD" || exit 0
fi

# Skip if the command failed
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // .tool_result.exitCode // "0"')
[[ "$EXIT_CODE" != "0" ]] && exit 0

# Trigger only when gh pr create was executed.
if ! echo "$COMMAND" | grep -qiE '(^|;|&&|\|\||\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
    exit 0
fi

# Skip if command already requested Copilot review explicitly.
if echo "$COMMAND" | grep -qiE -- '--add-reviewer[[:space:]]+copilot-pull-request-reviewer'; then
    exit 0
fi

# Skip if not in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# Resolve repo.
REPO=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name' 2>/dev/null || echo "")
[[ -z "$REPO" ]] && exit 0

# Prefer extracting PR URL/number from tool output, then fall back to current branch context.
TOOL_OUTPUT=$(echo "$INPUT" | jq -r '.tool_result.output // .tool_result.stdout // .tool_result.result // empty')
PR_NUMBER=$(echo "$TOOL_OUTPUT" | grep -Eo 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | tail -n1 | grep -Eo '[0-9]+$' || true)

if [[ -z "$PR_NUMBER" ]]; then
    PR_NUMBER=$(gh pr view --json number --jq '.number' 2>/dev/null || echo "")
fi

[[ -z "$PR_NUMBER" ]] && exit 0

# If Copilot is already in requested_reviewers, avoid duplicates.
HAS_REQUEST=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}" --jq \
    '[.requested_reviewers[]?.login] | map(select(. != null)) | any(test("^(Copilot|copilot-pull-request-reviewer)(\\[bot\\])?$"; "i"))' \
    2>/dev/null || echo "false")

if [[ "$HAS_REQUEST" == "true" ]]; then
    exit 0
fi

if gh pr edit "$PR_NUMBER" -R "$REPO" --add-reviewer copilot-pull-request-reviewer &>/dev/null; then
    jq -cn --arg msg "🤖 Requested Copilot review on PR #${PR_NUMBER} via copilot-pull-request-reviewer." \
        '{"hookSpecificOutput":{"additionalContext":$msg}}' >&2
fi

exit 0