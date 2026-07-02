#!/usr/bin/env bash
# afk-throughput.sh — measure unattended agent throughput.
#
# Counts merged PRs whose head branch starts `ai/` (the convention for AFK /
# Sandcastle agent-produced branches) bucketed by ISO week. This is the
# proof-of-life metric for the agentic layer: how many PRs the system merges
# per week without a human writing code. See docs/research for context.
#
# Usage:
#   bin/afk-throughput.sh [weeks] [owner/repo]
#     weeks       lookback window in weeks (default 8)
#     owner/repo  target repo (default: current repo via gh)
#
# Output: per-week counts, total, and average/week. Requires gh + jq.

set -euo pipefail

WEEKS="${1:-8}"
REPO="${2:-}"

command -v gh >/dev/null 2>&1 || { echo "afk-throughput: gh CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "afk-throughput: jq not found" >&2; exit 1; }
[[ "$WEEKS" =~ ^[0-9]+$ ]] || { echo "afk-throughput: weeks must be an integer" >&2; exit 1; }

[[ -n "$REPO" ]] || REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

# Merged ai/* PRs as "week<TAB>1" rows, one per PR, bucketed by ISO week of mergedAt.
weekly="$(gh pr list -R "$REPO" --state merged --limit 1000 \
    --json headRefName,mergedAt \
    --jq '
      map(select(.headRefName | startswith("ai/")) | .mergedAt | sub("Z$";"+0000"))
      | map(strptime("%Y-%m-%dT%H:%M:%S%z") | mktime | strftime("%G-W%V"))
      | group_by(.) | map("\(.[0])\t\(length)") | .[]' 2>/dev/null || true)"

echo "AFK throughput — $REPO (merged ai/* PRs, last $WEEKS weeks)"
echo "─────────────────────────────────────────────"
if [[ -z "$weekly" ]]; then
    echo "  no merged ai/* PRs found"
    exit 0
fi

# Most recent N weeks; print, total, and average. tr strips CR so awk math is safe.
printf '%s\n' "$weekly" | tr -d '\r' | sort | tail -n "$WEEKS" | awk -v w="$WEEKS" '
    { printf "  %-10s %s\n", $1, $2; t += $2 }
    END {
        print "─────────────────────────────────────────────"
        printf "  total: %d over %d weeks   avg: %.1f PR/week\n", t, w, (w ? t / w : 0)
    }'
