#!/usr/bin/env bash
# validate-main-pr-source.sh — Allow main/master PRs only from dev.

set -euo pipefail

base_ref="${GITHUB_BASE_REF:-${1:-}}"
head_ref="${GITHUB_HEAD_REF:-${2:-}}"

if [[ -z "$base_ref" || -z "$head_ref" ]]; then
    echo "validate-main-pr-source: GITHUB_BASE_REF and GITHUB_HEAD_REF are required." >&2
    exit 2
fi

case "$base_ref" in
    main|master)
        if [[ "$head_ref" != "dev" ]]; then
            echo "PRs targeting $base_ref must come from dev, not $head_ref." >&2
            echo "Use the promotion path: feature branch -> dev, then dev -> $base_ref." >&2
            exit 1
        fi
        ;;
esac

echo "PR source accepted: $head_ref -> $base_ref"
