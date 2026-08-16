#!/usr/bin/env bash
# validate-skills-lock.sh — Verify skills/skills-lock.json matches actual skill content.
#
# Recomputes SHA-256 hashes and compares against the lockfile. Exits non-zero on
# any drift (a skill changed without regenerating the lock) or a missing lockfile.
# Wired into ctrl check and CI so skill edits are held to the provenance contract.
#
# Usage: bash bin/validate-skills-lock.sh          (compare)
#        bash bin/validate-skills-lock.sh --refresh (regenerate then verify)

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SKILLS_ROOT="$ROOT/skills"
LOCKFILE="$SKILLS_ROOT/skills-lock.json"

if [[ "${1:-}" == "--refresh" ]]; then
    bash "$ROOT/bin/generate-skills-lock.sh" "$ROOT"
fi

if [[ ! -f "$LOCKFILE" ]]; then
    echo "skills-lock validation failed: $LOCKFILE does not exist" >&2
    echo "Run: bash bin/generate-skills-lock.sh $ROOT" >&2
    exit 1
fi

python - "$SKILLS_ROOT" "$LOCKFILE" <<'PY'
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

skills_root = Path(sys.argv[1])
lockfile = Path(sys.argv[2])

expected = json.loads(lockfile.read_text(encoding="utf-8"))
errors: list[str] = []
checked = 0

for name, meta in sorted(expected.get("skills", {}).items()):
    path = meta.get("skillPath")
    if not path:
        errors.append(f"{name}: missing skillPath")
        continue
    skill_file = skills_root / path.split("skills/", 1)[-1]
    if not skill_file.exists():
        errors.append(f"{name}: SKILL.md missing at {path}")
        continue
    raw = skill_file.read_bytes().replace(b"\r\n", b"\n")
    digest = hashlib.sha256(raw).hexdigest()
    checked += 1
    if digest != meta.get("computedHash"):
        errors.append(f"{name}: drift detected — content changed, run bin/generate-skills-lock.sh")

# Detect skills on disk not recorded in the lock (new skill without a lock entry).
for child in sorted(skills_root.iterdir()):
    if not child.is_dir():
        continue
    name = child.name
    if name.startswith(".") or name.startswith("_") or name == "__pycache__":
        continue
    if (child / "SKILL.md").exists() and name not in expected.get("skills", {}):
        errors.append(f"{name}: present on disk but not in skills-lock.json — run bin/generate-skills-lock.sh")

if errors:
    for error in errors:
        print(f"  - {error}")
    print(f"skills-lock validation failed ({checked} hashed, {len(errors)} problem(s)).")
    sys.exit(1)

print(f"skills-lock validation passed ({checked} skills match).")
PY