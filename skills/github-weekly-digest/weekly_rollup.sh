#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$SKILL_DIR/logs"

THIS_MONDAY=$(date -d "last monday" +%Y-%m-%d 2>/dev/null || date -v-sat -v-5d +%Y-%m-%d)
FRIDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

mkdir -p "$LOG_DIR"
cd "$SKILL_DIR"
source "$HOME/dotfiles/secrets/.venv/bin/activate"

echo "[$THIS_MONDAY → $FRIDAY] Weekly rollup starting at $(date -u +%H:%M:%S)" >> "$LOG_DIR/weekly.log"

"$HOME/dotfiles/bin/run-with-secrets.sh" python -m scripts.run_digest \
  --config config.json \
  --cadence rollup \
  --since "$THIS_MONDAY" \
  --until "$FRIDAY" \
  --fill-gaps \
  >> "$LOG_DIR/weekly.log" 2>&1

echo "[$THIS_MONDAY → $FRIDAY] Weekly rollup complete at $(date -u +%H:%M:%S)" >> "$LOG_DIR/weekly.log"
