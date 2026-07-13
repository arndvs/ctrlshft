#!/usr/bin/env bash
# validate-public-promotion.sh tests
#
# Run: bash test/validate-public-promotion.sh

set -euo pipefail

# Hermetic git env: git exports GIT_DIR/GIT_WORK_TREE when invoking hooks and the
# cd-hook can pollute them, which would override `git -C "$repo"` and hijack the
# temp-repo fixtures onto the real repo. Unset them (mirrors test/lifecycle.sh).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR \
      GIT_OBJECT_DIRECTORY GIT_NAMESPACE 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/bin/validate-public-promotion.sh"
REMOTE_VALIDATOR="$ROOT/bin/validate-remotes.sh"
PRE_PUSH="$ROOT/git-hooks/pre-push"
TMP_ROOT="$ROOT/working/tmp/public-promotion-test"

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

echo
echo "Public promotion guard tests"
echo "════════════════════════════════════════════════"

rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"

ignore_repo="$TMP_ROOT/ignore-rules"
make_repo "$ignore_repo"
cp "$ROOT/.gitignore" "$ignore_repo/.gitignore"
run_case "gitignore blocks accidental sandcastle config" pass "sandcastle.config.json" \
    git -C "$ignore_repo" check-ignore sandcastle.config.json
run_case "gitignore blocks accidental agent workflow" pass ".github/workflows/agent-review-issue.yml" \
    git -C "$ignore_repo" check-ignore .github/workflows/agent-review-issue.yml
mkdir -p "$ignore_repo/.sandcastle"
touch "$ignore_repo/.sandcastle/run.ts"
run_case "gitignore allows sanitized sandcastle tree" fail "" \
    git -C "$ignore_repo" check-ignore .sandcastle/run.ts

safe_repo="$TMP_ROOT/safe-productization"
make_repo "$safe_repo"
mkdir -p "$safe_repo/.sandcastle/engine" "$safe_repo/shft/templates/workflows" "$safe_repo/shft/engine" "$safe_repo/shft/docs" "$safe_repo/bin" "$safe_repo/test"
printf 'console.log("sanitized")\n' > "$safe_repo/.sandcastle/run.ts"
printf '{"name":"sandcastle"}\n' > "$safe_repo/.sandcastle/engine/package.json"
printf 'name: Agent Review\n' > "$safe_repo/shft/templates/workflows/agent-review-issue.yml"
printf '{"name":"engine"}\n' > "$safe_repo/shft/engine/package.json"
printf '# Sandcastle\n' > "$safe_repo/shft/docs/platform-spec.md"
printf '#!/usr/bin/env bash\n' > "$safe_repo/bin/init-sandcastle.sh"
printf '#!/usr/bin/env bash\n' > "$safe_repo/test/sandcastle-preflight.sh"
git -C "$safe_repo" add .
run_case "intentional Sandcastle source paths pass" pass "Public promotion guard passed" \
    bash -c "cd '$safe_repo' && bash '$GUARD'"

config_repo="$TMP_ROOT/config"
make_repo "$config_repo"
printf '{}\n' > "$config_repo/sandcastle.config.json"
git -C "$config_repo" add -f sandcastle.config.json
run_case "root sandcastle config is allowed on the host" pass "Public promotion guard passed" \
    bash -c "cd '$config_repo' && bash '$GUARD'"

dogfood_repo="$TMP_ROOT/dogfood"
make_repo "$dogfood_repo"
mkdir -p "$dogfood_repo/.sandcastle"
printf 'console.log(\"dogfood\")\n' > "$dogfood_repo/.sandcastle/run.ts"
git -C "$dogfood_repo" add -f .sandcastle/run.ts
run_case "sanitized .sandcastle artifacts are promotable" pass "Sanitized .sandcastle content is allowed" \
    bash -c "cd '$dogfood_repo' && bash '$GUARD'"

private_sandcastle_repo="$TMP_ROOT/private-sandcastle"
make_repo "$private_sandcastle_repo"
mkdir -p "$private_sandcastle_repo/.sandcastle"
printf 'Use dotfiles-private and ~/dotfiles for local operation.\n' > "$private_sandcastle_repo/.sandcastle/CODING_STANDARDS.md"
git -C "$private_sandcastle_repo" add -f .sandcastle/CODING_STANDARDS.md
run_case "unsanitized .sandcastle private refs fail" fail ".sandcastle contains private repo" \
    bash -c "cd '$private_sandcastle_repo' && bash '$GUARD'"

secret_value_repo="$TMP_ROOT/secret-value"
make_repo "$secret_value_repo"
mkdir -p "$secret_value_repo/.sandcastle"
printf 'token=%s%s\n' "github_pat_" "123456789012345678901234567890" > "$secret_value_repo/.sandcastle/secret.txt"
git -C "$secret_value_repo" add -f .sandcastle/secret.txt
run_case "secret-like values fail without printing value" fail ".sandcastle/secret.txt" \
    bash -c "cd '$secret_value_repo' && bash '$GUARD'"

workflow_repo="$TMP_ROOT/workflow"
make_repo "$workflow_repo"
mkdir -p "$workflow_repo/.github/workflows"
printf 'name: Installed Agent\n' > "$workflow_repo/.github/workflows/agent-review-issue.yml"
git -C "$workflow_repo" add .github/workflows/agent-review-issue.yml
run_case "installed agent workflows are allowed on the host" pass "Public promotion guard passed" \
    bash -c "cd '$workflow_repo' && bash '$GUARD'"

working_readme_repo="$TMP_ROOT/working-readmes"
make_repo "$working_readme_repo"
mkdir -p "$working_readme_repo/working/active" "$working_readme_repo/working/refs" "$working_readme_repo/working/research"
printf '# working active\n' > "$working_readme_repo/working/active/README.md"
printf '# working refs\n' > "$working_readme_repo/working/refs/README.md"
printf '# working research\n' > "$working_readme_repo/working/research/README.md"
git -C "$working_readme_repo" add working/active/README.md working/refs/README.md working/research/README.md
run_case "working lane README scaffolds are public structure" pass "Public promotion guard passed" \
    bash -c "cd '$working_readme_repo' && bash '$GUARD'"

working_repo="$TMP_ROOT/working"
make_repo "$working_repo"
mkdir -p "$working_repo/working/active"
printf '# private plan\n' > "$working_repo/working/active/private.md"
git -C "$working_repo" add working/active/private.md
run_case "working active plans are private-only" fail "working/active/private.md" \
    bash -c "cd '$working_repo' && bash '$GUARD'"

public_refs_repo="$TMP_ROOT/public-refs"
make_repo "$public_refs_repo"
git -C "$public_refs_repo" remote add origin https://github.com/arndvs/ctrlshft.git
mkdir -p "$public_refs_repo/bin"
cat > "$public_refs_repo/bin/validate-remotes.sh" <<'SH'
#!/usr/bin/env bash
# dotfiles-private name references are OK when they are guardrail prose.
echo "Do not push private dotfiles-private work to public ctrlshft."
SH
git -C "$public_refs_repo" add bin/validate-remotes.sh
run_case "public validator allows prose-only private repo references" pass "Content Sanitization" \
    bash -c "cd '$public_refs_repo' && bash '$REMOTE_VALIDATOR'"

private_url_repo="$TMP_ROOT/private-url"
make_repo "$private_url_repo"
git -C "$private_url_repo" remote add origin https://github.com/arndvs/ctrlshft.git
mkdir -p "$private_url_repo/scripts"
printf 'git clone https://github.com/arndvs/dotfiles-private.git\n' > "$private_url_repo/scripts/bootstrap.sh"
git -C "$private_url_repo" add scripts/bootstrap.sh
run_case "public validator blocks private GitHub URLs" fail "dotfiles-private URL" \
    bash -c "cd '$private_url_repo' && bash '$REMOTE_VALIDATOR'"

pre_push_repo="$TMP_ROOT/pre-push"
make_repo "$pre_push_repo"
mkdir -p "$pre_push_repo/working/runtime"
printf '{"state":"private"}\n' > "$pre_push_repo/working/runtime/state.json"
git -C "$pre_push_repo" add -f working/runtime/state.json
run_case "allowed public pre-push still runs promotion guard" fail "working/runtime/state.json" \
    bash -c "cd '$pre_push_repo' && CTRL_ALLOW_PUBLIC_PUSH=1 DOTFILES='$ROOT' bash '$PRE_PUSH' public https://github.com/arndvs/ctrlshft.git"

run_case "ssh public pre-push is blocked without explicit allow" fail "blocked push to public ctrl+shft" \
    bash -c "cd '$pre_push_repo' && DOTFILES='$ROOT' bash '$PRE_PUSH' public git@github.com:arndvs/ctrlshft.git"

run_case "ssh public pre-push still runs promotion guard when allowed" fail "working/runtime/state.json" \
    bash -c "cd '$pre_push_repo' && CTRL_ALLOW_PUBLIC_PUSH=1 DOTFILES='$ROOT' bash '$PRE_PUSH' public ssh://git@github.com/arndvs/ctrlshft.git"

printf "\n  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    for failure in "${FAILURES[@]}"; do
        printf "  \033[31m✗\033[0m %s\n" "$failure"
    done
    exit 1
fi
