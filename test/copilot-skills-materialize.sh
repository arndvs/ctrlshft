#!/usr/bin/env bash
# Verify Copilot skill deployment is flat and excludes non-skill wrappers.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/_lib.sh"

TMPDIR_RUN="$(mktemp -d 2>/dev/null || mktemp -d -t ctrlshft-copilot-skills)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

SOURCE="$TMPDIR_RUN/source/skills"
TARGET="$TMPDIR_RUN/copilot/skills"
mkdir -p \
  "$SOURCE/public-one" \
  "$SOURCE/_local/local-one" \
  "$SOURCE/_local/.git" \
  "$SOURCE/_local/__pycache__" \
  "$SOURCE/helper-only" \
  "$SOURCE/_private-helper"

cat > "$SOURCE/public-one/SKILL.md" <<'EOF'
---
name: public-one
description: Public test skill
---
EOF

cat > "$SOURCE/_local/local-one/SKILL.md" <<'EOF'
---
name: local-one
description: Local test skill
---
EOF

materialize_copilot_skills "$SOURCE" "$TARGET" "~/.copilot/skills" >/dev/null

mapfile -t actual < <(find "$TARGET" -mindepth 1 -maxdepth 1 -type d -exec basename '{}' ';' | sort)
expected=("local-one" "public-one")

if [[ "${actual[*]}" != "${expected[*]}" ]]; then
    echo "Unexpected Copilot skill inventory" >&2
    printf 'Expected: %s\n' "${expected[*]}" >&2
    printf 'Actual:   %s\n' "${actual[*]}" >&2
    exit 1
fi

for skill in "${expected[@]}"; do
    if [[ ! -f "$TARGET/$skill/SKILL.md" ]]; then
        echo "Missing SKILL.md for materialized skill: $skill" >&2
        exit 1
    fi
done

for forbidden in _local .git __pycache__ helper-only _private-helper; do
    if [[ -e "$TARGET/$forbidden" ]]; then
        echo "Forbidden runtime entry was materialized: $forbidden" >&2
        exit 1
    fi
done

echo "Copilot skill materialization passed."
