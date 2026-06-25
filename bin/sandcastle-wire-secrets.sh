#!/usr/bin/env bash
# sandcastle-wire-secrets.sh — Set the hosted-proxy GitHub Actions secrets on a
# Sandcastle repo from secrets/.env.secrets (the local source of truth).
#
# Reads LITELLM_BASE_URL + LITELLM_MASTER_KEY via run-with-secrets.sh (process-
# scoped, --only filtered) and writes them as repository Actions secrets with
# `gh secret set` over stdin, so the values never enter the parent shell, argv,
# shell history, or this command's output. AGENT_PAT is managed separately and
# left untouched.
#
# This productizes the manual `.sandcastle/scripts/setup-github-secrets.sh` paste
# flow into one repeatable, source-of-truth-driven command (PRD #70 / slice #75).
#
# Usage: ctrl sandcastle-wire-secrets [--repo OWNER/REPO] [--dry-run]

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

REPO=""
DRY_RUN=false
SECRETS_FILE="$DOTFILES/secrets/.env.secrets"
PROXY_SECRETS=(LITELLM_BASE_URL LITELLM_MASTER_KEY)

_usage() {
    cat <<'EOF'
Usage: ctrl sandcastle-wire-secrets [options]

Sets the hosted-proxy GitHub Actions secrets (LITELLM_BASE_URL, LITELLM_MASTER_KEY)
on a Sandcastle repo, sourced from secrets/.env.secrets. Values flow from the
local secrets file straight to GitHub over stdin — never printed, never in argv
or shell history. AGENT_PAT is managed separately and left untouched.

Options:
  --repo OWNER/REPO     Target repo (default: gh repo view in the current repo)
  --dry-run             Show what would be set (names only) without writing
  --secrets-file PATH   Source file (default: ~/dotfiles/secrets/.env.secrets)
  --help, -h            Show this help

After running, 'gh secret list -R <repo>' confirms the secrets by name only.
EOF
}

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            REPO="${2:-}"; [[ -n "$REPO" ]] || { red "Missing value for --repo"; exit 1; }; shift 2 ;;
        --secrets-file)
            SECRETS_FILE="${2:-}"; [[ -n "$SECRETS_FILE" ]] || { red "Missing value for --secrets-file"; exit 1; }; shift 2 ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --help|-h)
            _usage; exit 0 ;;
        *)
            red "Unknown option: $1"; echo ""; _usage; exit 1 ;;
    esac
done

if ! command -v gh >/dev/null 2>&1; then
    red "GitHub CLI (gh) is required."
    exit 1
fi
if [[ -z "$REPO" ]]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi
[[ -n "$REPO" ]] || { red "Could not determine repo. Pass --repo OWNER/REPO."; exit 1; }

# ── Inner phase: proxy secrets are injected into the environment by
#    run-with-secrets.sh. Validate and write them. ─────────────────────────────
if [[ "${_SWS_INNER:-}" == "1" ]]; then
    _fail=0
    for _name in "${PROXY_SECRETS[@]}"; do
        _val="${!_name:-}"
        if [[ -z "$_val" ]]; then
            red "  ✗ $_name is empty in $(basename "$SECRETS_FILE") — set it there first"
            _fail=1; continue
        fi
        if [[ "$_name" == "LITELLM_BASE_URL" ]]; then
            case "$_val" in
                https://*) : ;;
                http://localhost*|http://127.0.0.1*|http://0.0.0.0*)
                    red "  ✗ $_name is a localhost URL — GitHub Actions runners cannot reach it"
                    _fail=1; continue ;;
                http://*)
                    yellow "  ⚠ $_name is plain http (no TLS) — proceeding, but https is strongly recommended" ;;
                *)
                    red "  ✗ $_name is not an absolute http(s) URL"
                    _fail=1; continue ;;
            esac
        fi
        if printf '%s' "$_val" | gh secret set "$_name" --repo "$REPO" >/dev/null 2>&1; then
            green "  ✓ set $_name"
        else
            red "  ✗ failed to set $_name (check 'gh auth status' and repo admin access)"
            _fail=1
        fi
    done
    echo ""
    echo "Secrets on $REPO (names only):"
    gh secret list --repo "$REPO" 2>/dev/null | sed 's/^/  /' || true
    exit "$_fail"
fi

# ── Outer phase: banner, dry-run, then re-exec under run-with-secrets ─────────
green "Wire Sandcastle proxy secrets → $REPO"
echo "  Source:  $SECRETS_FILE"
echo "  Secrets: ${PROXY_SECRETS[*]}  (AGENT_PAT left untouched)"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    yellow "Dry run — nothing was written."
    for _s in "${PROXY_SECRETS[@]}"; do
        echo "  would set: $_s on $REPO (from $SECRETS_FILE)"
    done
    exit 0
fi

[[ -f "$SECRETS_FILE" ]] || { red "Secrets file not found: $SECRETS_FILE"; exit 1; }
[[ -f "$DOTFILES/bin/run-with-secrets.sh" ]] || { red "run-with-secrets.sh not found."; exit 1; }

_csv="$(IFS=,; echo "${PROXY_SECRETS[*]}")"
exec "$DOTFILES/bin/run-with-secrets.sh" --only "$_csv" -- \
    env _SWS_INNER=1 SECRETS_FILE="$SECRETS_FILE" bash "$0" --repo "$REPO"
