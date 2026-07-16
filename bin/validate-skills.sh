#!/usr/bin/env bash
# validate-skills.sh — Verify skill manifests load cleanly.
#
# Validates public skills and, when present, private skills under skills/_local.
# This catches malformed frontmatter before Copilot/Claude report startup load
# failures. It intentionally ignores helper/reference subdirectories that are
# not direct skill directories.

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SKILLS_ROOT="$ROOT/skills"

if [[ ! -d "$SKILLS_ROOT" ]]; then
    echo "Skill validation failed: $SKILLS_ROOT does not exist" >&2
    exit 1
fi

python - "$SKILLS_ROOT" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

skills_root = Path(sys.argv[1])
errors: list[str] = []
checked = 0
names: dict[str, Path] = {}


def iter_skill_dirs(root: Path):
    for child in sorted(root.iterdir()):
        if not child.is_dir():
            continue
        name = child.name
        if name.startswith(".") or name == "__pycache__":
            continue
        if name == "_local":
            for local_child in sorted(child.iterdir()):
                if not local_child.is_dir():
                    continue
                local_name = local_child.name
                if local_name.startswith(".") or local_name == "__pycache__":
                    continue
                yield local_child
            continue
        if name.startswith("_"):
            continue
        yield child


def strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def parse_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8-sig")
    match = re.match(r"^---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|$)", text, re.S)
    if not match:
        raise ValueError("missing opening/closing YAML frontmatter delimiters")

    data: dict[str, str] = {}
    lines = match.group(1).splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith((" ", "\t")):
            continue
        key, sep, raw_value = line.partition(":")
        if not sep:
            raise ValueError(f"invalid frontmatter line: {line!r}")
        key = key.strip()
        raw_value = raw_value.strip()
        if key in {"name", "description"}:
            if raw_value in {">", "|", ">-", "|-"}:
                block: list[str] = []
                while i < len(lines) and (lines[i].startswith((" ", "\t")) or not lines[i].strip()):
                    block.append(lines[i].strip())
                    i += 1
                data[key] = " ".join(part for part in block if part).strip()
            else:
                # YAML plain scalars cannot contain an unquoted ": " sequence.
                # Copilot's skill loader parses frontmatter as YAML, so catch the
                # exact class of failures that hide local skills at startup.
                if raw_value and raw_value[0] not in {"'", '"'} and ": " in raw_value:
                    raise ValueError(
                        f"{key} contains ': ' but is not quoted or block-style"
                    )
                data[key] = strip_quotes(raw_value)
    return data


for skill_dir in iter_skill_dirs(skills_root):
    skill_file = skill_dir / "SKILL.md"
    if not skill_file.exists():
        errors.append(f"{skill_dir}: missing SKILL.md")
        continue

    checked += 1
    try:
        frontmatter = parse_frontmatter(skill_file)
    except Exception as exc:
        errors.append(f"{skill_file}: {exc}")
        continue

    name = frontmatter.get("name", "").strip()
    description = frontmatter.get("description", "").strip()
    if not name:
        errors.append(f"{skill_file}: missing name")
    elif name != skill_dir.name:
        errors.append(f"{skill_file}: name {name!r} does not match directory {skill_dir.name!r}")
    elif name in names:
        errors.append(f"{skill_file}: duplicate skill name also used by {names[name]}")
    else:
        names[name] = skill_file
    if not description:
        errors.append(f"{skill_file}: missing description")

if errors:
    print("Skill validation failed:")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print(f"Skill validation passed ({checked} skill manifests).")
PY
