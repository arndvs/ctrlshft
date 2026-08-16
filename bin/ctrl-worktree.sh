#!/usr/bin/env bash
# ctrl-worktree.sh — Create and prune git worktrees with a safety model.
#
# Ported from saas-starter's create-worktree.ts + prune-worktrees.ts. The
# safety invariants are the value:
#
#   1. New worktrees branch from a FRESHLY FETCHED origin/<trunk>, never a
#      stale local branch.
#   2. '[gone]' upstream alone NEVER deletes a branch. Deletion requires a
#      confirmed merge: git ancestry OR a merged GitHub PR whose recorded
#      head SHA byte-equals the local tip.
#   3. Contribution branches (explicit pushRemote marker) accept ONLY the
#      SHA-matched merged PR — ancestry is disabled there because a fresh
#      scaffold has tip == remote trunk and `is-ancestor X X` exits 0.
#   4. Dirty worktrees are skipped unless --force.
#   5. Trunk fast-forward is best-effort --ff-only. Never reset/stash/force.
#
# Usage:
#   ctrl worktree <type/short-description>   # create + setup
#   ctrl worktree --setup-only               # setup existing worktree (Cursor UI)
#   ctrl worktree prune [--dry-run] [--force]
#
# Env:
#   CTRL_WORKTREE_BASE   — base branch override (default: origin/<trunk>)
#   CTRL_WORKTREE_NO_FETCH — skip the initial fetch

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

# ── Colors (local — _lib.sh has green/yellow/red) ────────────────────────────
dim() { printf '\033[2m%s\033[0m\n' "$*"; }

# ── Git helpers ──────────────────────────────────────────────────────────────
run_git() {
    git "$@" 2>&1
}

# Resolve the main worktree root (first line of `git worktree list --porcelain`).
get_root_worktree() {
    local out
    out="$(git worktree list --porcelain 2>/dev/null | head -1)" || {
        red "Not in a git repository."
        exit 1
    }
    printf '%s\n' "${out#worktree }"
}

# Resolve a remote's trunk branch from its HEAD, falling back to "main".
get_trunk() {
    local remote="${1:-origin}"
    local out
    out="$(git symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
    if [[ -n "$out" && "$out" == "$remote/"* ]]; then
        printf '%s\n' "${out#$remote/}"
    else
        printf '%s\n' "main"
    fi
}

# ── Create ───────────────────────────────────────────────────────────────────
create_worktree() {
    local description="${1:-}"
    local remote="${CTRL_WORKTREE_REMOTE:-origin}"
    local trunk
    trunk="$(get_trunk "$remote")"

    if [[ -z "$description" ]]; then
        red "Usage: ctrl worktree <type/short-description>"
        exit 1
    fi

    # Sanitize: lowercase, slashes → dashes, strip leading/trailing dashes.
    local slug
    slug="$(printf '%s\n' "$description" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
    if [[ -z "$slug" ]]; then
        red "Description produced an empty slug: $description"
        exit 1
    fi

    local root
    root="$(get_root_worktree)"
    local worktrees_dir
    worktrees_dir="$(dirname "$root").worktrees"
    local worktree_path="$worktrees_dir/$slug"
    local branch="feat/$slug"

    # Collision check: the flattened slug may collide with an existing worktree.
    if [[ -d "$worktree_path" ]]; then
        red "Worktree already exists at $worktree_path"
        red "  (branch slashes are flattened: 'feat/sentry' and 'feat-sentry' both map to 'feat-sentry')"
        exit 1
    fi

    # Fetch fresh trunk — never branch from a stale local branch.
    if [[ "${CTRL_WORKTREE_NO_FETCH:-}" != "1" ]]; then
        echo "Fetching $remote..."
        git fetch "$remote" || { red "Fetch failed."; exit 1; }
    fi

    echo "Creating worktree at $worktree_path (branch $branch, base $remote/$trunk)..."
    git worktree add -b "$branch" "$worktree_path" "$remote/$trunk" || {
        red "Worktree creation failed."
        exit 1
    }

    # Setup: copy env files if present, install deps.
    setup_worktree "$worktree_path"

    green "Worktree ready: $worktree_path"
    green "  cd $worktree_path"
    green "  Branch: $branch (base: $remote/$trunk)"
}

setup_worktree() {
    local path="$1"
    local root
    root="$(get_root_worktree)"

    # Copy env files from the main checkout (best-effort).
    for env_file in .env.local .env.test .env.agent.example .env.secrets.example; do
        if [[ -f "$root/$env_file" ]] && [[ ! -f "$path/$env_file" ]]; then
            cp "$root/$env_file" "$path/$env_file" 2>/dev/null || true
        fi
    done

    # Install deps if a package manager is present.
    if [[ -f "$path/package.json" ]]; then
        if command -v pnpm &>/dev/null && [[ -f "$path/pnpm-lock.yaml" ]]; then
            (cd "$path" && pnpm install --frozen-lockfile 2>/dev/null || pnpm install) || true
        elif command -v bun &>/dev/null && [[ -f "$path/bun.lockb" ]]; then
            (cd "$path" && bun install) || true
        elif command -v npm &>/dev/null; then
            (cd "$path" && npm install) || true
        fi
    fi
}

# ── Prune ────────────────────────────────────────────────────────────────────
# Parse `git worktree list --porcelain` into "branch|path" lines.
parse_worktrees() {
    git worktree list --porcelain 2>/dev/null | awk '
        /^worktree / { path = substr($0, 10); next }
        /^branch / && path != "" {
            branch = substr($0, 8)
            sub(/^refs\/heads\//, "", branch)
            print branch "|" path
            path = ""
        }
        /^$/ { path = "" }
    '
}

# Extract owner/repo from a GitHub remote URL (https or ssh). Empty for non-GitHub.
parse_remote_slug() {
    local url="${1:-}"
    case "$url" in
        https://github.com/*)
            printf '%s\n' "${url#https://github.com/}" | sed -E 's#\.git/?$##'
            ;;
        git@github.com:*|ssh://git@github.com/*)
            printf '%s\n' "${url#*github.com[:/]}" | sed -E 's#\.git/?$##'
            ;;
        *)
            printf '%s\n' ""
            ;;
    esac
}

# True iff a merged PR's head SHA byte-equals the local tip.
match_merged_pr_by_sha() {
    local prs_json="$1" local_tip="$2"
    [[ -n "$local_tip" ]] || return 1
    printf '%s\n' "$prs_json" | grep -q "\"headRefOid\": \"$local_tip\""
}

# Decide merge verdict from probe results.
classify_merge() {
    local gh_succeeded="$1" gh_sha_matched="$2" git_ancestor="$3"
    if [[ "$git_ancestor" == "1" ]]; then
        printf '%s\n' "merged"
    elif [[ "$gh_succeeded" == "1" ]]; then
        if [[ "$gh_sha_matched" == "1" ]]; then
            printf '%s\n' "merged"
        else
            printf '%s\n' "not-merged"
        fi
    else
        printf '%s\n' "unknown"
    fi
}

# Probe gh + git to decide whether a branch's content is really merged.
confirm_merged() {
    local branch="$1" remote="$2" trunk="$3" contribution="${4:-0}"
    local tip url slug gh_succeeded=0 gh_sha_matched=0 ancestor=0

    tip="$(git rev-parse "refs/heads/$branch" 2>/dev/null || true)"
    url="$(git remote get-url "$remote" 2>/dev/null || true)"
    slug="$(parse_remote_slug "$url")"

    if [[ -n "$tip" && -n "$slug" ]]; then
        local args=("pr" "list" "--repo" "$slug" "--head" "$branch" "--state" "merged" "--json" "number,headRefOid" "--limit" "10")
        if [[ "$contribution" == "1" ]]; then
            args+=("--base" "$trunk")
        fi
        local pr_out
        if pr_out="$(gh "${args[@]}" 2>/dev/null)"; then
            gh_succeeded=1
            if match_merged_pr_by_sha "$pr_out" "$tip"; then
                gh_sha_matched=1
            fi
        fi
    fi

    # Ancestry is never consulted for contribution branches (see header).
    if [[ "$contribution" != "1" ]]; then
        if git merge-base --is-ancestor "refs/heads/$branch" "$remote/$trunk" 2>/dev/null; then
            ancestor=1
        fi
    fi

    classify_merge "$gh_succeeded" "$gh_sha_matched" "$ancestor"
}

# Fast-forward the trunk in the main checkout — best effort only.
fast_forward_trunk() {
    local root_path="$1" trunk="$2" dry_run="${3:-0}"
    local head dirty behind ahead

    head="$(git -C "$root_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [[ "$head" != "$trunk" ]]; then
        yellow "Skipping trunk fast-forward: \"$head\" is checked out in the main worktree, not \"$trunk\"."
        return
    fi

    dirty="$(git -C "$root_path" status --porcelain 2>/dev/null || true)"
    if [[ -n "$dirty" ]]; then
        yellow "Skipping trunk fast-forward: main checkout has uncommitted changes."
        return
    fi

    behind="$(git -C "$root_path" rev-list --count "$trunk..origin/$trunk" 2>/dev/null || echo "0")"
    if [[ "$behind" == "0" ]]; then
        green "Local $trunk already up to date with origin."
        return
    fi

    ahead="$(git -C "$root_path" rev-list --count "origin/$trunk..$trunk" 2>/dev/null || echo "0")"
    if [[ "$ahead" != "0" ]]; then
        yellow "Skipping trunk fast-forward: local $trunk diverged ($ahead local commit(s), $behind on origin). Reconcile manually."
        return
    fi

    if [[ "$dry_run" == "1" ]]; then
        echo "[dry-run] would fast-forward $trunk by $behind commit(s)"
        return
    fi

    if git -C "$root_path" merge --ff-only "origin/$trunk" 2>&1; then
        green "Fast-forwarded $trunk by $behind commit(s)."
    fi
}

# Remove a confirmed-merged branch's worktree and delete the branch.
prune_branch() {
    local branch="$1" verdict="$2" not_merged_reason="$3" dry_run="${4:-0}" force="${5:-0}"
    local path=""

    if [[ "$verdict" != "merged" ]]; then
        local reason
        if [[ "$verdict" == "not-merged" ]]; then
            reason="$not_merged_reason"
        else
            reason="cannot confirm the merge (gh unavailable)"
        fi
        yellow "  skip $branch: $reason. Delete manually with \`git branch -D $branch\` if intended."
        return
    fi

    # Find the worktree path for this branch.
    while IFS='|' read -r wt_branch wt_path; do
        [[ -n "$wt_branch" ]] || continue
        if [[ "$wt_branch" == "$branch" ]]; then
            path="$wt_path"
            break
        fi
    done < <(parse_worktrees)

    if [[ -n "$path" ]]; then
        local dirty
        dirty="$(git -C "$path" status --porcelain 2>/dev/null || true)"
        if [[ -n "$dirty" && "$force" != "1" ]]; then
            yellow "  skip $branch: merged, but its worktree has uncommitted changes (use --force to discard)."
            yellow "       $path"
            return
        fi
        if [[ "$dry_run" == "1" ]]; then
            echo "  [dry-run] would remove worktree $path and branch $branch (merged)"
            return
        fi
        local remove_args=("worktree" "remove" "$path")
        if [[ "$force" == "1" ]]; then
            remove_args+=("--force")
        fi
        if git "${remove_args[@]}" 2>&1; then
            green "  removed worktree $path"
        else
            yellow "  could not remove worktree $path; leaving branch $branch in place."
            return
        fi
    fi

    if [[ "$dry_run" == "1" ]]; then
        if [[ -z "$path" ]]; then
            echo "  [dry-run] would delete branch $branch (merged)"
        fi
        return
    fi

    local deleted
    if deleted="$(git branch -D "$branch" 2>&1)"; then
        # Surface the deleted branch's SHA as a reflog anchor.
        local was_sha
        was_sha="$(printf '%s\n' "$deleted" | grep -o '(was [0-9a-f]\+)' || true)"
        green "  deleted branch $branch ${was_sha}"
    else
        yellow "  could not delete branch $branch"
    fi
}

prune_worktrees() {
    local dry_run=0 force=0
    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=1 ;;
            --force) force=1 ;;
        esac
    done

    local remote="${CTRL_WORKTREE_REMOTE:-origin}"
    local trunk
    trunk="$(get_trunk "$remote")"
    local root
    root="$(get_root_worktree)"
    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

    echo "Fetching $remote (--prune) so merged branches surface as [gone]..."
    git fetch "$remote" --prune 2>/dev/null || yellow "  fetch failed (warning only — deletion still requires a confirmed merge)"

    # Collect branches with [gone] upstream or explicit pushRemote markers.
    local gone_branches=()
    local contribution_branches=()
    local branch track push_remote

    while IFS=$'\t' read -r branch track push_remote; do
        [[ -n "$branch" ]] || continue
        if [[ "$branch" == "$trunk" || "$branch" == "$current_branch" ]]; then
            continue
        fi
        if [[ "$track" == "[gone]" ]]; then
            gone_branches+=("$branch")
        fi
        if [[ -n "$push_remote" && "$push_remote" != "$remote" ]]; then
            contribution_branches+=("$branch")
        fi
    done < <(git for-each-ref --format='%(refname:short)%09%(upstream:track)%09%(push:remotename)' refs/heads 2>/dev/null)

    echo ""
    echo "Checking ${#gone_branches[@]} [gone] branch(es) and ${#contribution_branches[@]} contribution branch(es)..."

    for branch in "${gone_branches[@]}"; do
        local verdict
        verdict="$(confirm_merged "$branch" "$remote" "$trunk" 0)"
        prune_branch "$branch" "$verdict" "PR closed unmerged or branch deleted by hand" "$dry_run" "$force"
    done

    for branch in "${contribution_branches[@]}"; do
        local verdict
        verdict="$(confirm_merged "$branch" "$remote" "$trunk" 1)"
        prune_branch "$branch" "$verdict" "contribution PR not merged (SHA mismatch)" "$dry_run" "$force"
    done

    # Best-effort trunk fast-forward.
    echo ""
    fast_forward_trunk "$root" "$trunk" "$dry_run"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
    create|new)
        create_worktree "${1:-}"
        ;;
    prune)
        prune_worktrees "$@"
        ;;
    --setup-only)
        # Setup an existing worktree (Cursor UI flow).
        local root
        root="$(get_root_worktree)"
        local cwd
        cwd="$(pwd)"
        if [[ "$cwd" == "$root" ]]; then
            red "Run --setup-only from inside the worktree, not the main checkout."
            exit 1
        fi
        setup_worktree "$cwd"
        green "Worktree setup complete: $cwd"
        ;;
    help|-h|--help)
        cat <<'HELP'
ctrl worktree — create and prune git worktrees with a safety model.

Usage:
  ctrl worktree <type/short-description>   Create a worktree from fresh origin/<trunk>
  ctrl worktree prune [--dry-run] [--force]  Remove merged worktrees + branches
  ctrl worktree --setup-only               Setup an existing worktree (Cursor UI)

Safety invariants:
  - New worktrees branch from freshly-fetched origin/<trunk>
  - [gone] upstream alone never deletes — requires confirmed merge
  - Dirty worktrees skipped unless --force
  - Trunk fast-forward is best-effort --ff-only
HELP
        ;;
    *)
        red "Unknown ctrl worktree command: $CMD"
        exit 1
        ;;
esac