#!/usr/bin/env bash
set -euo pipefail

YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$SKILL_DIR/logs"

mkdir -p "$LOG_DIR"
cd "$SKILL_DIR"
source "$HOME/dotfiles/secrets/.venv/bin/activate"

echo "[$YESTERDAY] Daily digest starting at $(date -u +%H:%M:%S)" >> "$LOG_DIR/daily.log"

"$HOME/dotfiles/bin/run-with-secrets.sh" python -m scripts.run_digest \
  --config config.json \
  --cadence daily \
  --since "$YESTERDAY" \
  --until "$YESTERDAY" \
  --dry-run \
  >> "$LOG_DIR/daily.log" 2>&1

echo "[$YESTERDAY] Daily digest complete at $(date -u +%H:%M:%S)" >> "$LOG_DIR/daily.log"
