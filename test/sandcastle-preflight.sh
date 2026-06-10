#!/usr/bin/env bash
# test/sandcastle-preflight.sh — Verify ctrl preflight-sandcastle behavior.
# Usage: bash test/sandcastle-preflight.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTRL="$ROOT/bin/ctrl"
TMP_ROOT="$ROOT/working/tmp/sandcastle-preflight-test"

PASS=0
FAIL=0
FAILURES=()

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

_record_pass() {
    local label="$1"
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s\n" "$label"
}

_record_fail() {
    local label="$1"
    local detail="$2"
    FAIL=$((FAIL + 1))
    FAILURES+=("$label — $detail")
    printf "  \033[31m✗\033[0m %s — %s\n" "$label" "$detail"
}

run_case() {
    local label="$1"
    local expected_status="$2"
    local expected_text="$3"
    shift 3

    local output status
    set +e
    output=$("$@" 2>&1)
    status=$?
    set -e

    if [[ "$expected_status" == "pass" && $status -ne 0 ]]; then
        _record_fail "$label" "expected success, got exit $status: $output"
        return
    fi
    if [[ "$expected_status" == "fail" && $status -eq 0 ]]; then
        _record_fail "$label" "expected failure, got success: $output"
        return
    fi
    if [[ -n "$expected_text" && "$output" != *"$expected_text"* ]]; then
        _record_fail "$label" "expected output to contain '$expected_text': $output"
        return
    fi

    _record_pass "$label"
}

make_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test User"
}

seed_minimal_sandcastle() {
    local repo="$1"
    mkdir -p "$repo/.github/workflows" "$repo/.sandcastle/engine"
    cp "$ROOT/.github/workflows/agent-review-issue.yml" "$repo/.github/workflows/agent-review-issue.yml"
    cp "$ROOT/.sandcastle/run.ts" "$repo/.sandcastle/run.ts"
    cp "$ROOT/.sandcastle/engine/package.json" "$repo/.sandcastle/engine/package.json"
    cp "$ROOT/.sandcastle/engine/tsconfig.json" "$repo/.sandcastle/engine/tsconfig.json"
    cp "$ROOT/.sandcastle/engine/pnpm-lock.yaml" "$repo/.sandcastle/engine/pnpm-lock.yaml"
    cat > "$repo/sandcastle.config.json" <<'JSON'
{
  "model": "claude-opus-4-6",
  "baseBranch": "dev",
  "sandbox": "none",
  "packageManager": "pnpm"
}
JSON
}

echo
echo "Sandcastle preflight tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

missing_install="$TMP_ROOT/missing-install"
make_repo "$missing_install"
run_case "missing Sandcastle install reports CONFIG" fail "CONFIG" bash -c "cd '$missing_install' && DOTFILES='$ROOT' '$CTRL' preflight-sandcastle --skip-drift --skip-engine --skip-github"

missing_secret="$TMP_ROOT/missing-secret"
make_repo "$missing_secret"
seed_minimal_sandcastle "$missing_secret"
run_case "missing secrets report SECRETS" fail "SECRETS" bash -c "cd '$missing_secret' && DOTFILES='$ROOT' '$CTRL' preflight-sandcastle --skip-drift --skip-engine --skip-github"

malformed_workflow="$TMP_ROOT/malformed-workflow"
make_repo "$malformed_workflow"
seed_minimal_sandcastle "$malformed_workflow"
printf 'name: [unterminated\n' > "$malformed_workflow/.github/workflows/agent-review-issue.yml"
run_case "malformed workflow reports SYNTAX" fail "SYNTAX" bash -c "cd '$malformed_workflow' && DOTFILES='$ROOT' CLAUDE_CODE_OAUTH_TOKEN=dummy LITELLM_BASE_URL=dummy LITELLM_MASTER_KEY=dummy AGENT_PAT=dummy '$CTRL' preflight-sandcastle --skip-drift --skip-engine --skip-github"

missing_permissions="$TMP_ROOT/missing-permissions"
make_repo "$missing_permissions"
seed_minimal_sandcastle "$missing_permissions"
python - "$missing_permissions/.github/workflows/agent-review-issue.yml" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = re.sub(r"\n    permissions:\n      contents: read\n      issues: write\n", "\n", text)
open(path, "w", encoding="utf-8").write(text)
PY
run_case "missing workflow permissions reports PERMS" fail "PERMS" bash -c "cd '$missing_permissions' && DOTFILES='$ROOT' CLAUDE_CODE_OAUTH_TOKEN=dummy LITELLM_BASE_URL=dummy LITELLM_MASTER_KEY=dummy AGENT_PAT=dummy '$CTRL' preflight-sandcastle --skip-drift --skip-engine --skip-github"

healthy="$TMP_ROOT/healthy"
make_repo "$healthy"
seed_minimal_sandcastle "$healthy"
run_case "healthy minimal repo passes skipped external gates" pass "Sandcastle preflight passed" bash -c "cd '$healthy' && DOTFILES='$ROOT' CLAUDE_CODE_OAUTH_TOKEN=dummy LITELLM_BASE_URL=dummy LITELLM_MASTER_KEY=dummy AGENT_PAT=dummy '$CTRL' preflight-sandcastle --skip-drift --skip-engine --skip-github"

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
