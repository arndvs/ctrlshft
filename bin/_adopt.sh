#!/usr/bin/env bash
# _adopt.sh — Adoption mode for bootstrap.sh
#
# Sourced by bootstrap.sh when --adopt flag is passed.
# Handles merging an existing Claude Code setup into ctrl+shft
# rather than overwriting it.
#
# Called as: source "$(dirname "${BASH_SOURCE[0]}")/_adopt.sh"
# Expects: DOTFILES, CLAUDE_DIR, OS already set by bootstrap.sh

# ── Adopt: existing CLAUDE.md ─────────────────────────────────────────────────
adopt_claude_md() {
    local existing=""

    if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]] && [[ ! -L "$CLAUDE_DIR/CLAUDE.md" ]]; then
        existing="$CLAUDE_DIR/CLAUDE.md"
    elif [[ -L "$CLAUDE_DIR/CLAUDE.md" ]]; then
        local target
        target=$(readlink "$CLAUDE_DIR/CLAUDE.md")
        if [[ "$target" != "$DOTFILES"* ]] && [[ -f "$target" ]]; then
            existing="$target"
        fi
    fi

    if [[ -z "$existing" ]]; then
        green "  No pre-existing CLAUDE.md to adopt — proceeding normally"
        return 0
    fi

    green "  Found existing CLAUDE.md: $existing"
    local _lines
    _lines=$(wc -l < "$existing")
    yellow "  Contents: $_lines lines"
    echo ""
    echo "  What would you like to do?"
    echo "    [1] Fold into CLAUDE.base.md (recommended — merges your content)"
    echo "    [2] Back up and replace (your content saved to ~/.claude/CLAUDE.md.pre-ctrlshft)"
    echo "    [3] Skip — leave CLAUDE.md untouched (ctrl+shft won't manage it)"
    echo ""
    read -rp "  Choice [1/2/3]: " _choice

    case "$_choice" in
        1)
            green "  Folding existing content into CLAUDE.base.md..."
            cp "$DOTFILES/CLAUDE.base.md" "$DOTFILES/CLAUDE.base.md.pre-adopt"
            green "  Backed up CLAUDE.base.md → CLAUDE.base.md.pre-adopt"

            {
                printf '\n\n<!-- ── ADOPTED FROM EXISTING CLAUDE.MD (%s) ── -->\n' "$(date '+%Y-%m-%d')"
                printf '<!-- Original: %s -->\n' "$existing"
                printf '<!-- Review and reorganize this content into appropriate sections -->\n\n'
                awk 'BEGIN{skip=0} /^<!-- GENERATED/{skip=1} /-->/{if(skip){skip=0; next}} !skip{print}' "$existing"
            } >> "$DOTFILES/CLAUDE.base.md"

            green "  Folded into CLAUDE.base.md"
            yellow "  Review CLAUDE.base.md and reorganize the adopted content"
            yellow "  Run bootstrap again when ready to regenerate CLAUDE.md"
            ;;
        2)
            cp "$existing" "${existing}.pre-ctrlshft"
            green "  Backed up to ${existing}.pre-ctrlshft"
            [[ -f "$CLAUDE_DIR/CLAUDE.md" ]] && rm "$CLAUDE_DIR/CLAUDE.md"
            green "  Cleared — bootstrap will create symlink"
            ;;
        3)
            yellow "  Skipping CLAUDE.md — ctrl+shft will not manage it"
            ADOPT_SKIP_CLAUDE_MD=true
            ;;
        *)
            yellow "  Invalid choice — skipping CLAUDE.md"
            ADOPT_SKIP_CLAUDE_MD=true
            ;;
    esac
}

# ── Adopt: existing skills/ directory ────────────────────────────────────────
adopt_skills() {
    local skills_path="$CLAUDE_DIR/skills"

    if [[ -L "$skills_path" ]]; then
        local target
        target=$(readlink "$skills_path")
        if [[ "$target" == "$DOTFILES/skills" ]]; then
            yellow "  ~/.claude/skills already symlinked correctly — skipping"
            return 0
        fi
        yellow "  ~/.claude/skills symlinked to $target (not ctrl+shft)"
    elif [[ ! -d "$skills_path" ]]; then
        green "  No existing skills/ — proceeding normally"
        return 0
    fi

    local _count
    _count=$(find "$skills_path" -name "*.md" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
    green "  Found existing skills/: $_count markdown files"

    echo ""
    echo "  What would you like to do?"
    echo "    [1] Merge into skills/_local/ (recommended — preserves your skills privately)"
    echo "    [2] Back up to skills/_local/_imported/ and symlink"
    echo "    [3] Skip — leave skills/ untouched"
    echo ""
    read -rp "  Choice [1/2/3]: " _choice

    case "$_choice" in
        1|2)
            local dest="$DOTFILES/skills/_local"
            if [[ "$_choice" == "2" ]]; then
                dest="$DOTFILES/skills/_local/_imported"
            fi
            mkdir -p "$dest"

            if [[ -L "$skills_path" ]]; then
                local real_skills
                real_skills=$(readlink "$skills_path")
                green "  Copying skills from $real_skills → $dest"
                cp -r "$real_skills"/. "$dest/" 2>/dev/null || true
                unlink "$skills_path"
            elif [[ -d "$skills_path" ]]; then
                green "  Copying skills from $skills_path → $dest"
                cp -r "$skills_path"/. "$dest/" 2>/dev/null || true
                mv "$skills_path" "${skills_path}.pre-ctrlshft"
                green "  Backed up original to ${skills_path}.pre-ctrlshft"
            fi

            green "  Skills preserved in $dest"
            yellow "  Review them — promote anything universal to skills/, leave the rest in _local/"
            ;;
        3)
            yellow "  Skipping skills/ — ctrl+shft will not manage it"
            ADOPT_SKIP_SKILLS=true
            ;;
        *)
            yellow "  Invalid choice — skipping skills/"
            ADOPT_SKIP_SKILLS=true
            ;;
    esac
}

# ── Adopt: existing rules/ directory ─────────────────────────────────────────
adopt_rules() {
    local rules_path="$CLAUDE_DIR/rules"

    if [[ -L "$rules_path" ]]; then
        local target
        target=$(readlink "$rules_path")
        if [[ "$target" == "$DOTFILES/rules" ]]; then
            yellow "  ~/.claude/rules already symlinked correctly — skipping"
            return 0
        fi
    elif [[ ! -d "$rules_path" ]]; then
        green "  No existing rules/ — proceeding normally"
        return 0
    fi

    local _count
    _count=$(find "$rules_path" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    green "  Found existing rules/: $_count files"

    echo ""
    echo "  What would you like to do?"
    echo "    [1] Merge into instructions/_local/ (recommended)"
    echo "    [2] Back up and replace with ctrl+shft rules/"
    echo "    [3] Skip — leave rules/ untouched"
    echo ""
    read -rp "  Choice [1/2/3]: " _choice

    case "$_choice" in
        1)
            mkdir -p "$DOTFILES/instructions/_local"
            if [[ -L "$rules_path" ]]; then
                local real_rules
                real_rules=$(readlink "$rules_path")
                cp -r "$real_rules"/. "$DOTFILES/instructions/_local/" 2>/dev/null || true
                unlink "$rules_path"
            elif [[ -d "$rules_path" ]]; then
                cp -r "$rules_path"/. "$DOTFILES/instructions/_local/" 2>/dev/null || true
                mv "$rules_path" "${rules_path}.pre-ctrlshft"
                green "  Backed up original to ${rules_path}.pre-ctrlshft"
            fi
            green "  Rules merged into instructions/_local/"
            yellow "  Review and promote any universal rules to rules/"
            ;;
        2)
            if [[ -d "$rules_path" ]] && [[ ! -L "$rules_path" ]]; then
                mv "$rules_path" "${rules_path}.pre-ctrlshft"
                green "  Backed up to ${rules_path}.pre-ctrlshft"
            elif [[ -L "$rules_path" ]]; then
                unlink "$rules_path"
            fi
            ;;
        3)
            yellow "  Skipping rules/ — ctrl+shft will not manage it"
            ADOPT_SKIP_RULES=true
            ;;
        *)
            yellow "  Skipping rules/"
            ADOPT_SKIP_RULES=true
            ;;
    esac
}

# ── Adopt: existing agents/ directory ────────────────────────────────────────
adopt_agents() {
    local agents_path="$CLAUDE_DIR/agents"

    if [[ -L "$agents_path" ]]; then
        local target
        target=$(readlink "$agents_path")
        if [[ "$target" == "$DOTFILES/agents" ]]; then
            yellow "  ~/.claude/agents already symlinked correctly — skipping"
            return 0
        fi
    elif [[ ! -d "$agents_path" ]]; then
        green "  No existing agents/ — proceeding normally"
        return 0
    fi

    local _count
    _count=$(find "$agents_path" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    green "  Found existing agents/: $_count agent files"

    echo ""
    echo "  What would you like to do?"
    echo "    [1] Merge into ctrl+shft agents/ (combined)"
    echo "    [2] Back up and replace"
    echo "    [3] Skip — leave agents/ untouched"
    echo ""
    read -rp "  Choice [1/2/3]: " _choice

    case "$_choice" in
        1)
            if [[ -L "$agents_path" ]]; then
                local real_agents
                real_agents=$(readlink "$agents_path")
                for f in "$real_agents"/*.md; do
                    [[ -f "$f" ]] || continue
                    local fname
                    fname=$(basename "$f")
                    if [[ ! -f "$DOTFILES/agents/$fname" ]]; then
                        cp "$f" "$DOTFILES/agents/$fname"
                        green "  Imported agent: $fname"
                    else
                        yellow "  Skipped (already exists): $fname"
                    fi
                done
                unlink "$agents_path"
            elif [[ -d "$agents_path" ]]; then
                for f in "$agents_path"/*.md; do
                    [[ -f "$f" ]] || continue
                    local fname
                    fname=$(basename "$f")
                    if [[ ! -f "$DOTFILES/agents/$fname" ]]; then
                        cp "$f" "$DOTFILES/agents/$fname"
                        green "  Imported agent: $fname"
                    else
                        yellow "  Skipped (already exists): $fname"
                    fi
                done
                mv "$agents_path" "${agents_path}.pre-ctrlshft"
                green "  Backed up original to ${agents_path}.pre-ctrlshft"
            fi
            green "  Agents merged"
            ;;
        2)
            if [[ -d "$agents_path" ]] && [[ ! -L "$agents_path" ]]; then
                mv "$agents_path" "${agents_path}.pre-ctrlshft"
                green "  Backed up to ${agents_path}.pre-ctrlshft"
            elif [[ -L "$agents_path" ]]; then
                unlink "$agents_path"
            fi
            ;;
        3)
            yellow "  Skipping agents/ — ctrl+shft will not manage it"
            ADOPT_SKIP_AGENTS=true
            ;;
        *)
            yellow "  Skipping agents/"
            ADOPT_SKIP_AGENTS=true
            ;;
    esac
}

# ── Adopt: project CLAUDE.md skill extraction ─────────────────────────────────
adopt_extract_skills() {
    echo ""
    green "  Scanning for project CLAUDE.md files with extractable skills..."

    local _found=0
    local _search_dirs=()

    for d in "$HOME/projects" "$HOME/code" "$HOME/dev" "$HOME/work" "$HOME/src" "$HOME/Sites"; do
        [[ -d "$d" ]] && _search_dirs+=("$d")
    done

    [[ ${#_search_dirs[@]} -eq 0 ]] && {
        dim "  No common project directories found — skipping"
        return 0
    }

    while IFS= read -r f; do
        [[ "$f" == "$CLAUDE_DIR/CLAUDE.md" ]] && continue
        [[ "$f" == "$DOTFILES/CLAUDE.md" ]] && continue
        [[ "$f" == "$DOTFILES/CLAUDE.base.md" ]] && continue

        local _project
        _project=$(dirname "$f" | xargs basename)
        local _lines
        _lines=$(wc -l < "$f")

        local _has_procedures=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^[0-9]+\.[[:space:]] ]] || \
               [[ "$line" =~ ^\`\`\` ]] || \
               [[ "$line" =~ (always|never|step [0-9]|checklist|workflow|procedure) ]]; then
                _has_procedures=true
                break
            fi
        done < "$f"

        [[ "$_has_procedures" == false ]] && continue

        (( _found++ )) || true
        echo ""
        yellow "  Project: $_project"
        dim "    Path: $f"
        dim "    Size: $_lines lines"
        echo "    This file contains procedural content that may be worth"
        echo "    extracting as a private skill in skills/_local/"
        echo ""
        echo "    [1] Create a skill stub in skills/_local/$_project/"
        echo "    [2] Skip this project"
        echo ""
        read -rp "    Choice [1/2]: " _proj_choice

        if [[ "$_proj_choice" == "1" ]]; then
            local skill_dir="$DOTFILES/skills/_local/$_project"
            mkdir -p "$skill_dir"

            cat > "$skill_dir/SKILL.md" << SKILLEOF
---
name: ${_project}
description: "TODO: Describe when to invoke this skill and what it does. Be specific."
---

# ${_project}

> Imported from \`$f\` on $(date '+%Y-%m-%d').
> Review and restructure into the standard skill format.
> Delete sections that are context rather than procedure.

## When to invoke

TODO: What triggers this skill?

## Method

TODO: Step-by-step procedure.

---

<!-- IMPORTED CONTENT — review and restructure below this line -->

$(cat "$f")
SKILLEOF

            green "    Created stub: $skill_dir/SKILL.md"
            yellow "    Review and restructure — the imported content is a starting point, not a finished skill"
        fi

    done < <(find "${_search_dirs[@]}" \
        -maxdepth 3 \
        -name "CLAUDE.md" \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -not -path "*/dotfiles/*" \
        2>/dev/null | sort)

    if [[ "$_found" -eq 0 ]]; then
        dim "  No project CLAUDE.md files with extractable procedures found"
    fi
}

# ── Main adopt flow ───────────────────────────────────────────────────────────
run_adopt() {
    echo ""
    echo "  ┌─────────────────────────────────────────────────────┐"
    echo "  │  Adopt mode — merging your existing setup           │"
    echo "  │  You'll be prompted before anything is changed.     │"
    echo "  └─────────────────────────────────────────────────────┘"
    echo ""
    yellow "  Tip: run migrate.sh first for a full read-only preview"
    echo ""

    ADOPT_SKIP_CLAUDE_MD=false
    ADOPT_SKIP_SKILLS=false
    ADOPT_SKIP_RULES=false
    ADOPT_SKIP_AGENTS=false

    echo ""
    green "[adopt 1/5] CLAUDE.md"
    adopt_claude_md

    echo ""
    green "[adopt 2/5] skills/"
    adopt_skills

    echo ""
    green "[adopt 3/5] rules/"
    adopt_rules

    echo ""
    green "[adopt 4/5] agents/"
    adopt_agents

    echo ""
    green "[adopt 5/5] Skill extraction from project CLAUDE.md files"
    read -rp "  Scan project directories for extractable skills? [y/N]: " _scan
    if [[ "$_scan" =~ ^[Yy]$ ]]; then
        adopt_extract_skills
    else
        dim "  Skipping project scan"
    fi

    echo ""
    green "  Adopt phase complete."
    echo ""
    yellow "  bootstrap will now continue with standard setup."
    yellow "  Skipped items will not be touched."
    echo ""
}

export ADOPT_SKIP_CLAUDE_MD
export ADOPT_SKIP_SKILLS
export ADOPT_SKIP_RULES
export ADOPT_SKIP_AGENTS
