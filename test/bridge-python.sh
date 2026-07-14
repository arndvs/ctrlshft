#!/usr/bin/env bash
# Run bridge Python unit and integration tests.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"
python -m unittest discover -s test/python -p "test_bridge*.py" -v
