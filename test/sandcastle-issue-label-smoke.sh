#!/usr/bin/env bash
# test/sandcastle-issue-label-smoke.sh — Verify Sandcastle issue-label smoke harness behavior.
# Usage: bash test/sandcastle-issue-label-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/smoke-sandcastle-issue-labels.sh"
TMP_ROOT="$ROOT/working/tmp/sandcastle-issue-label-smoke-test"

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
    mkdir -p "$repo/.github/workflows"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test User"
    for workflow in agent-review-issue.yml agent-plan-issue.yml agent-implement-issue.yml; do
        cat > "$repo/.github/workflows/$workflow" <<'YAML'
name: Smoke Fixture
on:
  issues:
    types: [labeled]
jobs:
  smoke:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - run: echo ok
YAML
    done
}

install_fake_gh() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/gh" <<'FAKEGH'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${FAKE_GH_STATE_DIR:?FAKE_GH_STATE_DIR required}"
mkdir -p "$state_dir"

if [[ "$1" == "repo" && "${2:-}" == "view" ]]; then
    echo 'owner/repo'
    exit 0
fi

if [[ "$1" == "issue" && "${2:-}" == "create" ]]; then
    : > "$state_dir/issue-created"
    echo 'https://github.com/owner/repo/issues/777'
    exit 0
fi

if [[ "$1" == "issue" && "${2:-}" == "edit" ]]; then
    echo "$*" >> "$state_dir/issue-edit.args"
    if [[ "$*" == *"--add-label Sandcastle"* ]]; then
        : > "$state_dir/sandcastle-labeled"
    fi
    exit 0
fi

if [[ "$1" == "issue" && "${2:-}" == "view" ]]; then
    cat <<'JSON'
{"state":"OPEN","labels":["agent:pr-open"]}
JSON
    exit 0
fi

if [[ "$1" == "issue" && "${2:-}" == "close" ]]; then
    echo "$*" > "$state_dir/issue-close.args"
    exit 0
fi

if [[ "$1" == "run" && "${2:-}" == "list" ]]; then
    workflow=''
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--workflow" ]]; then
            workflow="$2"
            shift 2
            continue
        fi
        shift
    done
    if [[ ! -f "$state_dir/sandcastle-labeled" ]]; then
        echo '[]'
        exit 0
    fi
    case "$workflow" in
        agent-review-issue.yml) id=101 ;;
        agent-plan-issue.yml) id=102 ;;
        agent-implement-issue.yml) id=103 ;;
        *) id=999 ;;
    esac
    skipped_id=$((id + 900))
    cat <<JSON
[{"databaseId":$skipped_id,"url":"https://github.com/owner/repo/actions/runs/$skipped_id","status":"completed","conclusion":"skipped","createdAt":"2026-06-10T00:00:01Z","name":"$workflow","displayTitle":"$workflow skipped fan-out"},{"databaseId":$id,"url":"https://github.com/owner/repo/actions/runs/$id","status":"completed","conclusion":"success","createdAt":"2026-06-10T00:00:00Z","name":"$workflow","displayTitle":"$workflow"}]
JSON
    exit 0
fi

if [[ "$1" == "run" && "${2:-}" == "view" ]]; then
    id="$3"
    cat <<JSON
{"databaseId":$id,"url":"https://github.com/owner/repo/actions/runs/$id","status":"completed","conclusion":"success","name":"run-$id","jobs":[{"name":"smoke","steps":[{"name":"Run smoke","conclusion":"success"}]}]}
JSON
    exit 0
fi

if [[ "$1" == "pr" && "${2:-}" == "list" ]]; then
    echo '{"number":888,"url":"https://github.com/owner/repo/pull/888"}'
    exit 0
fi

if [[ "$1" == "pr" && "${2:-}" == "close" ]]; then
    echo "$*" > "$state_dir/pr-close.args"
    exit 0
fi

if [[ "$1" == "api" ]]; then
    echo "$*" > "$state_dir/api.args"
    exit 0
fi

echo "unexpected gh args: $*" >&2
exit 99
FAKEGH
    chmod +x "$bin_dir/gh"
}

echo
echo "Sandcastle issue-label smoke tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

repo="$TMP_ROOT/repo"
make_repo "$repo"

run_case "dry run previews issue-label chain" pass "Would wait for workflows" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --dry-run --repo owner/repo"

run_case "live run requires side-effect opt-in" fail "Pass --allow-side-effects" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --repo owner/repo"

fake_bin="$TMP_ROOT/fake-bin"
fake_state="$TMP_ROOT/fake-state"
install_fake_gh "$fake_bin"
run_case "successful chain reports run urls and cleans up" pass "Issue-label smoke passed" \
    env PATH="$fake_bin:$PATH" FAKE_GH_STATE_DIR="$fake_state" \
    bash -c "cd '$repo' && DOTFILES='$ROOT' '$SCRIPT' --repo owner/repo --allow-side-effects --poll-seconds 1 --timeout-seconds 20 --title 'Sandcastle smoke fixture test'"

if [[ -f "$fake_state/pr-close.args" && -f "$fake_state/issue-close.args" ]]; then
    _record_pass "cleanup closes disposable PR and issue"
else
    _record_fail "cleanup closes disposable PR and issue" "expected fake cleanup calls"
fi

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
