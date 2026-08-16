#!/usr/bin/env bash
# generate-skills-lock.sh — Generate skills/skills-lock.json provenance manifest.
#
# Computes a SHA-256 content hash of every skill directory's SKILL.md and writes
# a lockfile recording path + hash + source provenance. Used for drift detection:
# if a skill's content changes without regenerating the lock, the validator
# (validate-skills-lock.sh) flags it — the same "convention is a lint rule"
# thesis as the saas-starter's skills-lock.json.
#
# Usage: bash bin/generate-skills-lock.sh [--dry-run]
#
# Deterministic: sorts entries, normalizes line endings, idempotent on re-run.

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SKILLS_ROOT="$ROOT/skills"
LOCKFILE="$SKILLS_ROOT/skills-lock.json"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

if [[ ! -d "$SKILLS_ROOT" ]]; then
    echo "skills-lock generation failed: $SKILLS_ROOT does not exist" >&2
    exit 1
fi

python - "$SKILLS_ROOT" "$LOCKFILE" "$DRY_RUN" <<'PY'
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

skills_root = Path(sys.argv[1])
lockfile = Path(sys.argv[2])
dry_run = sys.argv[3] == "True"

# Public skills are directories with a SKILL.md directly inside skills/.
# _local/ is private (gitignored) and excluded from the manifest.
skills: dict[str, dict[str, str]] = {}

for child in sorted(skills_root.iterdir()):
    if not child.is_dir():
        continue
    name = child.name
    if name.startswith(".") or name.startswith("_") or name == "__pycache__":
        continue
    skill_file = child / "SKILL.md"
    if not skill_file.exists():
        continue
    # Normalize CRLF → LF so hashes are stable across Windows/macOS/Linux.
    raw = skill_file.read_bytes().replace(b"\r\n", b"\n")
    digest = hashlib.sha256(raw).hexdigest()
    skills[name] = {
        "source": "arndvs/ctrlshft",
        "sourceType": "local",
        "skillPath": f"skills/{name}/SKILL.md",
        "computedHash": digest,
    }

manifest = {"version": 1, "skills": skills}
payload = json.dumps(manifest, indent=2, sort_keys=True) + "\n"

if dry_run:
    existing = lockfile.read_text(encoding="utf-8") if lockfile.exists() else ""
    if existing == payload:
        print("skills-lock.json up to date.")
    else:
        print("skills-lock.json would change:")
        for skill, meta in sorted(skills.items()):
            print(f"  {skill}: {meta['computedHash'][:12]}...")
    sys.exit(0)

lockfile.write_text(payload, encoding="utf-8")
print(f"Wrote {lockfile.name} with {len(skills)} skills.")
PY
