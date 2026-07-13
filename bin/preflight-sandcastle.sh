#!/usr/bin/env bash
# preflight-sandcastle.sh — Validate a repo's Sandcastle install before smoke runs.
#
# Usage: ctrl preflight-sandcastle [--skip-drift] [--skip-engine] [--skip-github]
#
# Failure classes:
#   CONFIG  Missing install/config, invalid config JSON, drift, or missing tools
#   SYNTAX  Malformed workflow YAML or missing workflow structure
#   SECRETS Missing required Actions secrets or local secret env vars
#   PERMS   Missing workflow permissions blocks

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

SKIP_DRIFT=false
SKIP_ENGINE=false
SKIP_GITHUB=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-drift) SKIP_DRIFT=true; shift ;;
        --skip-engine) SKIP_ENGINE=true; shift ;;
        --skip-github) SKIP_GITHUB=true; shift ;;
        --help|-h)
            echo "Usage: ctrl preflight-sandcastle [--skip-drift] [--skip-engine] [--skip-github]"
            echo ""
            echo "Validates Sandcastle readiness before workflow smoke testing."
            echo ""
            echo "Checks:"
            echo "  CONFIG   install shape, config JSON, vendored drift, package manager"
            echo "  SYNTAX   installed agent workflow YAML shape"
            echo "  SECRETS  LITELLM_BASE_URL, LITELLM_MASTER_KEY, AGENT_PAT"
            echo "  PERMS    workflow permissions blocks"
            echo ""
            echo "Options:"
            echo "  --skip-drift   Skip ctrl update-sandcastle --dry-run drift check"
            echo "  --skip-engine  Skip .sandcastle/engine typecheck/test commands"
            echo "  --skip-github  Do not query GitHub repo secrets; require env vars only"
            exit 0
            ;;
        *) red "Unknown option: $1"; exit 1 ;;
    esac
done

_fail=0
_warn=0

_fail_class() {
    local class="$1"
    local message="$2"
    red "  ✗ ${class}: ${message}"
    _fail=1
}

_pass_class() {
    local class="$1"
    local message="$2"
    green "  ✓ ${class}: ${message}"
}

_warn_class() {
    local class="$1"
    local message="$2"
    yellow "  ~ ${class}: ${message}"
    _warn=1
}

_require_command() {
    local command_name="$1"
    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi
    _fail_class "CONFIG" "Required command not found: $command_name"
    return 1
}

_read_config_value() {
    local key="$1"
    node -e "
const fs = require('fs');
try {
  const config = JSON.parse(fs.readFileSync('sandcastle.config.json', 'utf8'));
  const value = config[process.argv[1]];
  if (value !== undefined && value !== null) process.stdout.write(String(value));
} catch {
  process.exit(1);
}
" "$key"
}

_check_workflow_syntax() {
    local workflow_dir="$1"
    WORKFLOW_DIR="$workflow_dir" python - <<'PY'
import os
import re
import sys

workflow_dir = os.environ["WORKFLOW_DIR"]
errors = []

openers = {"[": "]", "{": "}"}
closers = {"]": "[",
    "}": "{",
}

for name in sorted(os.listdir(workflow_dir)):
    if not name.startswith("agent-") or not name.endswith((".yml", ".yaml")):
        continue
    path = os.path.join(workflow_dir, name)
    with open(path, encoding="utf-8") as handle:
        lines = handle.readlines()

    text = "".join(lines)
    required_top_level = ["name:", "on:", "jobs:"]
    for key in required_top_level:
        if not re.search(rf"^\s*{re.escape(key)}", text, re.MULTILINE):
            errors.append(f"{name}: missing top-level {key}")

    stack = []
    block_indent = None
    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.rstrip("\n")
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "\t" in line[: len(line) - len(line.lstrip())]:
            errors.append(f"{name}:{line_number}: tab indentation is not valid workflow YAML")
        indent = len(line) - len(line.lstrip(" "))
        if block_indent is not None:
            if indent > block_indent:
                continue
            block_indent = None
        if stripped.endswith("|") or stripped.endswith(">"):
            block_indent = indent
        if not stripped.startswith("-") and ":" not in stripped:
            errors.append(f"{name}:{line_number}: expected a mapping key or list item")

        for char in stripped:
            if char in openers:
                stack.append((char, line_number))
            elif char in closers:
                if not stack or stack[-1][0] != closers[char]:
                    errors.append(f"{name}:{line_number}: unmatched {char}")
                else:
                    stack.pop()
    for opener, line_number in stack:
        errors.append(f"{name}:{line_number}: unterminated {opener}")

if errors:
    for error in errors:
        print(error)
    sys.exit(1)
PY
}

_check_workflow_permissions() {
    local workflow_dir="$1"
    WORKFLOW_DIR="$workflow_dir" python - <<'PY'
import os
import re
import sys

workflow_dir = os.environ["WORKFLOW_DIR"]
errors = []

for name in sorted(os.listdir(workflow_dir)):
    if not name.startswith("agent-") or not name.endswith((".yml", ".yaml")):
        continue
    path = os.path.join(workflow_dir, name)
    with open(path, encoding="utf-8") as handle:
        lines = handle.readlines()

    found = False
    for index, raw_line in enumerate(lines):
        if re.match(r"^\s{4}permissions:\s*$", raw_line):
            base_indent = len(raw_line) - len(raw_line.lstrip(" "))
            for child in lines[index + 1:]:
                stripped = child.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                indent = len(child) - len(child.lstrip(" "))
                if indent <= base_indent:
                    break
                if re.match(r"^\s+[a-z-]+:\s+(read|write|none)\s*$", child):
                    found = True
                    break
            break
    if not found:
        errors.append(f"{name}: missing job permissions block")

if errors:
    for error in errors:
        print(error)
    sys.exit(1)
PY
}

_check_required_secrets() {
    local missing=()
    local required=(LITELLM_BASE_URL LITELLM_MASTER_KEY AGENT_PAT)
    local repo_slug=""

    for secret in "${required[@]}"; do
        if _secret_available "$secret"; then
            continue
        fi
        missing+=("$secret")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        _pass_class "SECRETS" "Required secrets are present in environment or run-with-secrets"
        return 0
    fi

    if [[ "$SKIP_GITHUB" == false ]] && command -v gh >/dev/null 2>&1; then
        repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
    fi

    if [[ "$SKIP_GITHUB" == false ]] && [[ -n "$repo_slug" ]]; then
        local configured_names
        local timeout_bin=""
        if command -v timeout >/dev/null 2>&1; then
            timeout_bin="timeout"
        elif command -v gtimeout >/dev/null 2>&1; then
            timeout_bin="gtimeout"
        fi

        if [[ -n "$timeout_bin" ]]; then
            configured_names="$(GH_PROMPT_DISABLED=1 "$timeout_bin" 15 gh secret list -R "$repo_slug" --json name --jq '.[].name' 2>/dev/null || true)"
        else
            configured_names="$(GH_PROMPT_DISABLED=1 gh secret list -R "$repo_slug" --json name --jq '.[].name' 2>/dev/null || true)"
        fi
        local still_missing=()
        local secret
        for secret in "${missing[@]}"; do
            if grep -qx "$secret" <<<"$configured_names"; then
                continue
            fi
            still_missing+=("$secret")
        done
        if [[ ${#still_missing[@]} -eq 0 ]]; then
            _pass_class "SECRETS" "Required repo secrets are configured"
            return 0
        fi
        missing=("${still_missing[@]}")
    fi

    _fail_class "SECRETS" "Missing required secrets: ${missing[*]}"
}

_secret_available() {
    local secret="$1"
    local runner="$DOTFILES/bin/run-with-secrets.sh"
    local output=""
    local status=0

    if [[ -n "${!secret:-}" ]]; then
        return 0
    fi
    if [[ ! -x "$runner" ]]; then
        return 1
    fi

    output="$("$runner" bash -c 'var="$1"; [[ -n "${!var:-}" ]] || exit 3' _ "$secret" 2>&1 >/dev/null)" || status=$?
    if [[ "$status" -eq 0 ]]; then
        return 0
    fi
    if [[ "$status" -ne 3 ]] && [[ -n "$output" ]]; then
        printf '%s\n' "$output" >&2
    fi
    return 1
}

_check_engine() {
    local package_manager="$1"
    local engine_dir=".sandcastle/engine"

    case "$package_manager" in
        npm|pnpm|yarn|bun) ;;
        *) _fail_class "CONFIG" "Invalid package manager in sandcastle.config.json: $package_manager"; return 0 ;;
    esac

    if ! command -v "$package_manager" >/dev/null 2>&1; then
        _fail_class "CONFIG" "Package manager not found: $package_manager"
        return 0
    fi

    if [[ ! -f "$engine_dir/package.json" ]]; then
        _fail_class "CONFIG" "Missing $engine_dir/package.json"
        return 0
    fi

    if [[ ! -d "$engine_dir/node_modules" ]]; then
        case "$package_manager" in
            pnpm) (cd "$engine_dir" && pnpm --ignore-workspace install --frozen-lockfile >/tmp/sandcastle-preflight-install.log 2>&1) ;;
            npm)
                if [[ -f "$engine_dir/package-lock.json" ]]; then
                    (cd "$engine_dir" && npm ci >/tmp/sandcastle-preflight-install.log 2>&1)
                else
                    (cd "$engine_dir" && npm install >/tmp/sandcastle-preflight-install.log 2>&1)
                fi
                ;;
            yarn) (cd "$engine_dir" && yarn install --frozen-lockfile >/tmp/sandcastle-preflight-install.log 2>&1) ;;
            bun) (cd "$engine_dir" && bun install --frozen-lockfile >/tmp/sandcastle-preflight-install.log 2>&1) ;;
        esac || {
            _fail_class "CONFIG" "Engine dependency install failed; see /tmp/sandcastle-preflight-install.log"
            return 0
        }
        _pass_class "CONFIG" "Engine dependencies installed"
    fi

    if (cd "$engine_dir" && "$package_manager" run typecheck >/tmp/sandcastle-preflight-typecheck.log 2>&1); then
        _pass_class "CONFIG" "Engine typecheck passed"
    else
        _fail_class "CONFIG" "Engine typecheck failed; see /tmp/sandcastle-preflight-typecheck.log"
    fi

    if (cd "$engine_dir" && "$package_manager" test >/tmp/sandcastle-preflight-test.log 2>&1); then
        _pass_class "CONFIG" "Engine tests passed"
    else
        _fail_class "CONFIG" "Engine tests failed; see /tmp/sandcastle-preflight-test.log"
    fi
}

green "Sandcastle preflight"
echo ""

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _fail_class "CONFIG" "Not inside a git repository"
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

echo "Repository: $(basename "$REPO_ROOT")"
echo ""

_require_command node >/dev/null || true

if [[ ! -f "sandcastle.config.json" ]]; then
    _fail_class "CONFIG" "Missing sandcastle.config.json"
else
    if node -e "JSON.parse(require('fs').readFileSync('sandcastle.config.json', 'utf8'))" >/dev/null 2>&1; then
        _pass_class "CONFIG" "sandcastle.config.json parses"
    else
        _fail_class "CONFIG" "sandcastle.config.json is not valid JSON"
    fi
fi

for required_path in ".sandcastle/engine" ".github/workflows" ".sandcastle/run.ts"; do
    if [[ -e "$required_path" ]]; then
        _pass_class "CONFIG" "Found $required_path"
    else
        _fail_class "CONFIG" "Missing $required_path"
    fi
done

workflow_count=0
if [[ -d ".github/workflows" ]]; then
    workflow_count=$(find .github/workflows -maxdepth 1 -type f -name 'agent-*.yml' | wc -l | tr -d ' ')
fi
if [[ "$workflow_count" -eq 0 ]]; then
    _fail_class "CONFIG" "No installed agent workflow files found"
else
    _pass_class "CONFIG" "Found $workflow_count installed agent workflow file(s)"
fi

if [[ -d ".github/workflows" ]]; then
    if syntax_output="$(_check_workflow_syntax ".github/workflows" 2>&1)"; then
        _pass_class "SYNTAX" "Workflow YAML shape passed"
    else
        _fail_class "SYNTAX" "$syntax_output"
    fi

    if perms_output="$(_check_workflow_permissions ".github/workflows" 2>&1)"; then
        _pass_class "PERMS" "Workflow permissions blocks present"
    else
        _fail_class "PERMS" "$perms_output"
    fi
fi

_check_required_secrets
if [[ "$_fail" -ne 0 ]]; then
    echo ""
    red "Sandcastle preflight failed."
    exit 1
fi

if [[ "$SKIP_DRIFT" == true ]]; then
    _warn_class "CONFIG" "Skipped Sandcastle drift check"
elif [[ -f "$DOTFILES/bin/update-sandcastle.sh" ]]; then
    if drift_output="$(bash "$DOTFILES/bin/update-sandcastle.sh" --dry-run 2>&1)"; then
        if grep -q "Drift detected" <<<"$drift_output"; then
            _fail_class "CONFIG" "Sandcastle drift detected; run ctrl update-sandcastle --dry-run"
        else
            _pass_class "CONFIG" "No Sandcastle drift detected"
        fi
    else
        _fail_class "CONFIG" "Drift check failed: $drift_output"
    fi
else
    _fail_class "CONFIG" "Missing $DOTFILES/bin/update-sandcastle.sh"
fi

if [[ "$SKIP_ENGINE" == true ]]; then
    _warn_class "CONFIG" "Skipped engine typecheck/tests"
elif [[ -f "sandcastle.config.json" ]]; then
    package_manager="$(_read_config_value packageManager 2>/dev/null || true)"
    package_manager="${package_manager:-pnpm}"
    _check_engine "$package_manager"
fi

echo ""
if [[ "$_fail" -eq 0 ]]; then
    green "Sandcastle preflight passed."
    if [[ "$_warn" -ne 0 ]]; then
        yellow "Completed with skipped checks; run without skip flags for full validation."
    fi
    exit 0
fi

red "Sandcastle preflight failed."
exit 1
