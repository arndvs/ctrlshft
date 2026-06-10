#!/usr/bin/env bash
# test/sandcastle-dispatch-smoke.sh — Verify Sandcastle workflow_dispatch harness behavior.
# Usage: bash test/sandcastle-dispatch-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/smoke-sandcastle-dispatch.sh"
TMP_ROOT="$ROOT/working/tmp/sandcastle-dispatch-smoke-test"

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
    mkdir -p "$repo/.github/workflows" "$repo/bin"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test User"
    cat > "$repo/sandcastle.config.json" <<'JSON'
{
  "baseBranch": "dev"
}
JSON
    cat > "$repo/.github/workflows/agent-check-stale-prs.yml" <<'YAML'
name: "Agent: Check Stale PRs"
on:
  workflow_dispatch:
jobs:
  check-stale:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YAML
    cat > "$repo/.github/workflows/agent-architecture-review.yml" <<'YAML'
name: "Agent: Architecture Review"
on:
  workflow_dispatch:
jobs:
  architecture-review:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YAML
}

install_fake_gh() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/gh" <<'FAKEGH'
#!/usr/bin/env bash
set -euo pipefail
mode="${FAKE_GH_MODE:-success}"
state_dir="${FAKE_GH_STATE_DIR:?FAKE_GH_STATE_DIR required}"
mkdir -p "$state_dir"

if [[ "$1" == "repo" && "${2:-}" == "view" ]]; then
    echo 'owner/repo'
    exit 0
fi

if [[ "$1" == "workflow" && "${2:-}" == "run" ]]; then
    echo "$*" > "$state_dir/workflow-run.args"
    : > "$state_dir/dispatched"
    exit 0
fi

if [[ "$1" == "run" && "${2:-}" == "list" ]]; then
    if [[ -f "$state_dir/dispatched" ]]; then
        cat <<'JSON'
[{"databaseId":12345,"url":"https://github.com/owner/repo/actions/runs/12345","status":"queued","conclusion":null,"createdAt":"2026-06-10T00:00:01Z","name":"Agent: Check Stale PRs","displayTitle":"Agent: Check Stale PRs"}]
JSON
    else
        echo '[]'
    fi
    exit 0
fi

if [[ "$1" == "run" && "${2:-}" == "view" ]]; then
    if [[ "$mode" == "failure" ]]; then
        cat <<'JSON'
{"databaseId":12345,"url":"https://github.com/owner/repo/actions/runs/12345","status":"completed","conclusion":"failure","name":"Agent: Check Stale PRs","jobs":[{"name":"check-stale","steps":[{"name":"Checkout code","conclusion":"success"},{"name":"Check stale PRs","conclusion":"failure"}]}]}
JSON
    else
        cat <<'JSON'
{"databaseId":12345,"url":"https://github.com/owner/repo/actions/runs/12345","status":"completed","conclusion":"success","name":"Agent: Check Stale PRs","jobs":[{"name":"check-stale","steps":[{"name":"Checkout code","conclusion":"success"},{"name":"Check stale PRs","conclusion":"success"}]}]}
JSON
    fi
    exit 0
fi

echo "unexpected gh args: $*" >&2
exit 99
FAKEGH
    chmod +x "$bin_dir/gh"
}

echo
echo "Sandcastle dispatch smoke tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

repo="$TMP_ROOT/repo"
make_repo "$repo"

run_case "dry run reports dispatch command" pass "Would run: gh workflow run agent-check-stale-prs.yml" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --dry-run --repo owner/repo --ref dev"

success_bin="$TMP_ROOT/success-bin"
success_state="$TMP_ROOT/success-state"
install_fake_gh "$success_bin"
run_case "dispatch success reports run url and conclusion" pass "Conclusion: success" \
    env PATH="$success_bin:$PATH" FAKE_GH_MODE=success FAKE_GH_STATE_DIR="$success_state" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --repo owner/repo --ref dev --poll-seconds 1 --timeout-seconds 10"

failure_bin="$TMP_ROOT/failure-bin"
failure_state="$TMP_ROOT/failure-state"
install_fake_gh "$failure_bin"
run_case "dispatch failure reports failed step names" fail "check-stale / Check stale PRs (failure)" \
    env PATH="$failure_bin:$PATH" FAKE_GH_MODE=failure FAKE_GH_STATE_DIR="$failure_state" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --repo owner/repo --ref dev --poll-seconds 1 --timeout-seconds 10"

run_case "side-effect workflow requires explicit opt-in" fail "not in the safe dispatch allowlist" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --workflow agent-architecture-review.yml --dry-run --repo owner/repo --ref dev"

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
