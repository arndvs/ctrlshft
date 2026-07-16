#!/usr/bin/env bash
# test/skills.sh — Verify skill manifests are loadable.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$ROOT/bin/validate-skills.sh" "$ROOT"
