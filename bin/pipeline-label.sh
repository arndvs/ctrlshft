#!/usr/bin/env bash
# pipeline-label.sh — thin wrapper around `gh issue/pr edit` that validates
# label transitions against the pipeline state machine before applying them.
#
# Fail-open: if validation fails to run (missing deps, parse error), the
# label is still applied and a warning is emitted to stderr.
#
# Usage:
#   pipeline-label.sh issue 42 --add-label "agent:review" --remove-label "Sandcastle"
#   pipeline-label.sh pr    99 --add-label "agent:in-progress"
#
# Environment:
#   GH_TOKEN / GITHUB_TOKEN — forwarded to gh CLI
#   PIPELINE_LABEL_STRICT   — if "1", exit non-zero on validation failure
#                              (default: fail-open, warn only)

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────

# Object-type constraints from pipeline-states.ts (keep in sync)
# Format: label|objectType1,objectType2
declare -A LABEL_APPLIES_TO=(
  ["Sandcastle"]="issue"
  ["agent:review"]="issue,pr"
  ["agent:implement"]="issue"
  ["agent:pr-open"]="issue"
  ["agent:fix"]="pr"
  ["agent:merge"]="pr"
  ["agent:update-branch"]="pr"
  ["agent:implement-prd"]="issue"
  ["agent:queued"]="issue"
  ["agent:in-progress"]="issue,pr"
  ["agent:blocked"]="issue,pr"
  ["source:architecture-review"]="issue,pr"
)

# Mutual exclusions (pairs that must not coexist)
MUTUAL_EXCLUSIONS=(
  "agent:in-progress|agent:blocked"
  "agent:fix|agent:merge"
  "agent:implement|agent:queued"
)

# ── Parse args ────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo "Usage: pipeline-label.sh {issue|pr} NUMBER [--add-label LABEL]... [--remove-label LABEL]... [extra gh flags]" >&2
  exit 1
fi

OBJECT_TYPE="$1"; shift
NUMBER="$1"; shift

ADD_LABELS=()
REMOVE_LABELS=()
GH_EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --add-label)
      ADD_LABELS+=("$2"); shift 2 ;;
    --remove-label)
      REMOVE_LABELS+=("$2"); shift 2 ;;
    *)
      GH_EXTRA+=("$1"); shift ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────────────────

WARNINGS=()

validate_label_op() {
  local label="$1"
  local action="$2"  # add or remove

  # Only validate adds — removes are always safe
  if [[ "$action" != "add" ]]; then
    return
  fi

  local allowed="${LABEL_APPLIES_TO[$label]:-}"
  if [[ -z "$allowed" ]]; then
    # Unknown label — not in the state machine, let it through
    return
  fi

  # Check object-type constraint
  if [[ ! ",$allowed," == *",$OBJECT_TYPE,"* ]]; then
    WARNINGS+=("⚠ Label \"$label\" applied to $OBJECT_TYPE but only allowed on: $allowed")
  fi
}

for label in "${ADD_LABELS[@]}"; do
  validate_label_op "$label" "add"
done

# Emit warnings
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  for w in "${WARNINGS[@]}"; do
    echo "$w" >&2
  done
  if [[ "${PIPELINE_LABEL_STRICT:-0}" == "1" ]]; then
    echo "pipeline-label.sh: strict mode — aborting due to validation failures." >&2
    exit 1
  fi
fi

# ── Apply labels via gh CLI ───────────────────────────────────────────────────

for label in "${REMOVE_LABELS[@]}"; do
  gh "$OBJECT_TYPE" edit "$NUMBER" --remove-label "$label" "${GH_EXTRA[@]}" || true
done

for label in "${ADD_LABELS[@]}"; do
  gh "$OBJECT_TYPE" edit "$NUMBER" --add-label "$label" "${GH_EXTRA[@]}"
done
