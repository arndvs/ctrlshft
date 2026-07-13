#!/usr/bin/env bash
# test/pipeline-label-wrapper.sh — focused checks for bin/pipeline-label.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/pipeline-label.sh"
TMP_ROOT="$ROOT/working/tmp/pipeline-label-wrapper-test"

PASS=0
FAIL=0
FAILURES=()

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1 — $2")
    printf "  \033[31m✗\033[0m %s — %s\n" "$1" "$2"
}

install_fake_gh() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/gh" <<'FAKEGH'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${FAKE_GH_STATE_DIR:?FAKE_GH_STATE_DIR required}"
mkdir -p "$state_dir"

if [[ "$1" == "issue" && "${2:-}" == "view" ]]; then
    echo "agent:blocked"
    exit 0
fi

if [[ "$1" == "issue" && "${2:-}" == "edit" ]]; then
    echo "$*" >> "$state_dir/edit.args"
    exit 0
fi

echo "unexpected gh args: $*" >&2
exit 99
FAKEGH
    chmod +x "$bin_dir/gh"
}

echo
echo "Pipeline label wrapper tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"
fake_bin="$TMP_ROOT/fake-bin"
fake_state="$TMP_ROOT/fake-state"
install_fake_gh "$fake_bin"

set +e
output=$(env PATH="$fake_bin:$PATH" FAKE_GH_STATE_DIR="$fake_state" PIPELINE_LABEL_STRICT=1 \
    "$SCRIPT" issue 42 --add-label "agent:in-progress" 2>&1)
status=$?
set -e

if [[ $status -eq 0 ]]; then
    fail "strict mode rejects mutually exclusive labels" "expected failure, got success: $output"
elif [[ "$output" != *"Mutual exclusion violated"* ]]; then
    fail "strict mode rejects mutually exclusive labels" "expected mutual-exclusion warning: $output"
elif [[ -f "$fake_state/edit.args" ]]; then
    fail "strict mode rejects mutually exclusive labels" "gh edit should not be called"
else
    pass "strict mode rejects mutually exclusive labels"
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
