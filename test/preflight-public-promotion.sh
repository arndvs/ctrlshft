#!/usr/bin/env bash
# preflight-public-promotion.sh tests
#
# Run: bash test/preflight-public-promotion.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFLIGHT="$ROOT/bin/preflight-public-promotion.sh"
TMP_ROOT="$ROOT/working/tmp/public-promotion-preflight-test"

PASS=0
FAIL=0
FAILURES=()

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

record_pass() {
    local label="$1"
    PASS=$((PASS + 1))
    printf "  \033[32m✓\033[0m %s\n" "$label"
}

record_fail() {
    local label="$1"
    local detail="$2"
    FAIL=$((FAIL + 1))
    FAILURES+=("$label — $detail")
    printf "  \033[31m✗\033[0m %s — %s\n" "$label" "$detail"
}

make_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -b main --quiet
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name "Test User"
    printf '# test\n' > "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -m "init" --quiet
}

run_case() {
    local label="$1"
    local expected="$2"
    local expected_text="$3"
    shift 3

    local output status
    set +e
    output=$("$@" 2>&1)
    status=$?
    set -e

    if [[ "$expected" == "pass" && $status -ne 0 ]]; then
        record_fail "$label" "expected pass, got $status: $output"
        return
    fi
    if [[ "$expected" == "fail" && $status -eq 0 ]]; then
        record_fail "$label" "expected failure, got success: $output"
        return
    fi
    if [[ -n "$expected_text" && "$output" != *"$expected_text"* ]]; then
        record_fail "$label" "expected output to contain '$expected_text': $output"
        return
    fi

    record_pass "$label"
}

commit_change() {
    local repo="$1"
    local message="$2"
    shift 2
    "$@"
    git -C "$repo" add .
    git -C "$repo" commit -m "$message" --quiet
}

echo
echo "Public promotion preflight tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

safe_repo="$TMP_ROOT/safe"
make_repo "$safe_repo"
safe_base="$(git -C "$safe_repo" rev-parse HEAD)"
commit_change "$safe_repo" "docs: add public guide" bash -c "mkdir -p '$safe_repo/docs' '$safe_repo/bin' '$safe_repo/.sandcastle'; printf '# Public guide\n' > '$safe_repo/docs/guide.md'; printf '#!/usr/bin/env bash\n' > '$safe_repo/bin/public-tool.sh'; printf 'console.log(\"public\")\n' > '$safe_repo/.sandcastle/run.ts'"
run_case "safe docs scripts and sandcastle pass" pass "Public promotion preflight passed" \
    bash -c "cd '$safe_repo' && bash '$PREFLIGHT' --range '$safe_base..HEAD'"

unsafe_path_repo="$TMP_ROOT/unsafe-path"
make_repo "$unsafe_path_repo"
unsafe_base="$(git -C "$unsafe_path_repo" rev-parse HEAD)"
commit_change "$unsafe_path_repo" "chore: add local sandcastle config" bash -c "printf '{}\n' > '$unsafe_path_repo/sandcastle.config.json'"
run_case "unsafe candidate path blocks promotion" fail "sandcastle.config.json" \
    bash -c "cd '$unsafe_path_repo' && bash '$PREFLIGHT' --range '$unsafe_base..HEAD'"

private_ref_repo="$TMP_ROOT/private-ref"
make_repo "$private_ref_repo"
private_ref_base="$(git -C "$private_ref_repo" rev-parse HEAD)"
commit_change "$private_ref_repo" "docs: add sandcastle standards" bash -c "mkdir -p '$private_ref_repo/.sandcastle'; printf 'Use dotfiles-private locally.\n' > '$private_ref_repo/.sandcastle/CODING_STANDARDS.md'"
run_case "private sandcastle references block promotion" fail ".sandcastle contains private repo" \
    bash -c "cd '$private_ref_repo' && bash '$PREFLIGHT' --range '$private_ref_base..HEAD'"

secret_value_repo="$TMP_ROOT/secret-value"
make_repo "$secret_value_repo"
secret_value_base="$(git -C "$secret_value_repo" rev-parse HEAD)"
commit_change "$secret_value_repo" "docs: add token example" bash -c "mkdir -p '$secret_value_repo/docs'; printf 'token=%s%s\n' 'github_pat_' '123456789012345678901234567890' > '$secret_value_repo/docs/token.txt'"
run_case "secret-like candidate values block promotion" fail "docs/token.txt" \
    bash -c "cd '$secret_value_repo' && bash '$PREFLIGHT' --range '$secret_value_base..HEAD'"

deleted_secret_repo="$TMP_ROOT/deleted-secret"
make_repo "$deleted_secret_repo"
deleted_secret_base="$(git -C "$deleted_secret_repo" rev-parse HEAD)"
commit_change "$deleted_secret_repo" "docs: add token temporarily" bash -c "mkdir -p '$deleted_secret_repo/docs'; printf 'token=%s%s\n' 'github_pat_' '123456789012345678901234567890' > '$deleted_secret_repo/docs/token.txt'"
commit_change "$deleted_secret_repo" "docs: remove token" bash -c "rm '$deleted_secret_repo/docs/token.txt'"
run_case "deleted secret-like values still block promotion history" fail "docs/token.txt" \
    bash -c "cd '$deleted_secret_repo' && bash '$PREFLIGHT' --range '$deleted_secret_base..HEAD'"

sanitized_history_repo="$TMP_ROOT/sanitized-history"
make_repo "$sanitized_history_repo"
sanitized_history_base="$(git -C "$sanitized_history_repo" rev-parse HEAD)"
commit_change "$sanitized_history_repo" "docs: add private sandcastle standard" bash -c "mkdir -p '$sanitized_history_repo/.sandcastle'; printf 'Use dotfiles-private locally.\n' > '$sanitized_history_repo/.sandcastle/CODING_STANDARDS.md'"
commit_change "$sanitized_history_repo" "docs: sanitize sandcastle standard" bash -c "printf 'Use the repository checkout locally.\n' > '$sanitized_history_repo/.sandcastle/CODING_STANDARDS.md'"
run_case "sanitized private sandcastle history still blocks promotion" fail ".sandcastle/CODING_STANDARDS.md" \
    bash -c "cd '$sanitized_history_repo' && bash '$PREFLIGHT' --range '$sanitized_history_base..HEAD'"

containment_repo="$TMP_ROOT/containment"
make_repo "$containment_repo"
containment_base="$(git -C "$containment_repo" rev-parse HEAD)"
commit_change "$containment_repo" "fix: emergency containment local topology" bash -c "mkdir -p '$containment_repo/docs'; printf '# topology\n' > '$containment_repo/docs/topology.md'"
run_case "emergency containment commits block promotion" fail "emergency containment" \
    bash -c "cd '$containment_repo' && bash '$PREFLIGHT' --range '$containment_base..HEAD'"

body_mention_repo="$TMP_ROOT/body-mention"
make_repo "$body_mention_repo"
body_mention_base="$(git -C "$body_mention_repo" rev-parse HEAD)"
mkdir -p "$body_mention_repo/docs"
printf '# public preflight\n' > "$body_mention_repo/docs/preflight.md"
git -C "$body_mention_repo" add docs/preflight.md
git -C "$body_mention_repo" commit -m "docs: explain public preflight" -m "Documents that emergency containment commits must be excluded." --quiet
run_case "explanatory containment body text passes" pass "Public promotion preflight passed" \
    bash -c "cd '$body_mention_repo' && bash '$PREFLIGHT' --range '$body_mention_base..HEAD'"

push_repo="$TMP_ROOT/push-confirmation"
make_repo "$push_repo"
push_base="$(git -C "$push_repo" rev-parse HEAD)"
commit_change "$push_repo" "docs: add public push candidate" bash -c "mkdir -p '$push_repo/docs'; printf '# push\n' > '$push_repo/docs/push.md'"
run_case "push mode requires explicit confirmation" fail "--confirm-public-push" \
    bash -c "cd '$push_repo' && bash '$PREFLIGHT' --range '$push_base..HEAD' --push"

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
