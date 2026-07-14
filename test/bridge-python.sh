#!/usr/bin/env bash
# Run bridge Python unit and integration tests.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_BRIDGE="$(mktemp -d 2>/dev/null || mktemp -d -t ctrlshft-bridge)"
trap 'rm -rf "$TMPDIR_BRIDGE"' EXIT

cd "$ROOT"

python3 -m venv "$TMPDIR_BRIDGE/venv"
PYTHON="$TMPDIR_BRIDGE/venv/bin/python"
if [[ -x "$TMPDIR_BRIDGE/venv/Scripts/python.exe" ]]; then
  PYTHON="$TMPDIR_BRIDGE/venv/Scripts/python.exe"
fi

"$PYTHON" -m pip install --quiet --upgrade pip
"$PYTHON" -m pip install --quiet -r bridge/requirements.txt
"$PYTHON" -m unittest discover -s test/python -p "test_bridge*.py" -v
