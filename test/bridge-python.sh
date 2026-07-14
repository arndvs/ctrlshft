#!/usr/bin/env bash
# Run bridge Python unit and integration tests.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_BRIDGE="$(mktemp -d 2>/dev/null || mktemp -d -t ctrlshft-bridge)"
trap 'rm -rf "$TMPDIR_BRIDGE"' EXIT

cd "$ROOT"

if ! python3 -m venv "$TMPDIR_BRIDGE/venv"; then
  printf '%s\n' \
    "Failed to create the bridge test virtualenv." \
    "Install Python's venv/ensurepip support for your platform, then rerun: bash test/bridge-python.sh" >&2
  exit 1
fi
PYTHON="$TMPDIR_BRIDGE/venv/bin/python"
if [[ -x "$TMPDIR_BRIDGE/venv/Scripts/python.exe" ]]; then
  PYTHON="$TMPDIR_BRIDGE/venv/Scripts/python.exe"
fi

"$PYTHON" -m pip install --quiet --upgrade "pip==26.1.2"
"$PYTHON" -m pip install --quiet -r bridge/requirements.lock
"$PYTHON" -m unittest discover -s test/python -p "test_bridge_*.py" -v
