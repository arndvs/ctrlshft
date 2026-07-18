#!/usr/bin/env bash
# Lightweight proxy gate for agent workflows.
#
# Emits should_run=true|false to GITHUB_OUTPUT. This script intentionally does
# not create issues; the central scheduled proxy canary owns proxy incidents.

set -euo pipefail

out="${GITHUB_OUTPUT:-/dev/stdout}"

emit() {
    local should_run="$1" reason="$2" detail="$3"
    {
        echo "should_run=$should_run"
        echo "reason=$reason"
        echo "detail=$detail"
    } >> "$out"
}

base="${ANTHROPIC_BASE_URL:-}"
token="${ANTHROPIC_AUTH_TOKEN:-}"
api_key="${ANTHROPIC_API_KEY:-}"

proxy_enabled="$(node -e 'try { const c = JSON.parse(require("fs").readFileSync("sandcastle.config.json", "utf8")); process.stdout.write(c.proxy === false ? "false" : "true"); } catch { process.stdout.write("true"); }' 2>/dev/null || echo "true")"

if [[ "$proxy_enabled" == "false" ]]; then
    if [[ -z "$api_key" ]]; then
        echo "::warning::Proxy preflight: direct provider mode missing ANTHROPIC_API_KEY; skipping agent run."
        emit "false" "missing-direct-provider-key" "ANTHROPIC_API_KEY is not configured"
        exit 0
    fi
    echo "Proxy preflight: direct provider mode; running agent."
    emit "true" "direct-provider" "sandcastle.config.json proxy=false"
    exit 0
fi

if [[ -z "$base" ]]; then
    echo "::warning::Proxy preflight: proxy mode missing base URL; skipping agent run."
    emit "false" "missing-proxy-base-url" "ANTHROPIC_BASE_URL is not configured"
    exit 0
fi

if [[ -z "$token" ]]; then
    echo "::warning::Proxy preflight: missing proxy auth token; skipping agent run."
    emit "false" "missing-proxy-token" "ANTHROPIC_AUTH_TOKEN is not configured"
    exit 0
fi

base="${base%/}"
base="${base%/v1}"

model="$(node -e 'try { const c = JSON.parse(require("fs").readFileSync("sandcastle.config.json", "utf8")); process.stdout.write(c.model || ""); } catch {}' 2>/dev/null || true)"
if [[ -z "$model" ]]; then
    echo "::warning::Proxy preflight: sandcastle.config.json has no model; skipping agent run."
    emit "false" "missing-model" "sandcastle.config.json does not define model"
    exit 0
fi

ready_body="$(mktemp)"
models_body="$(mktemp)"
trap 'rm -f "$ready_body" "$models_body"' EXIT

ready_code="$(curl -sS -o "$ready_body" -w '%{http_code}' --connect-timeout 5 --max-time 10 "$base/health/readiness" 2>/dev/null || true)"
if [[ "$ready_code" != "200" ]]; then
    echo "::warning::Proxy preflight: readiness returned HTTP ${ready_code:-000}; skipping agent run."
    emit "false" "proxy-not-ready" "readiness returned HTTP ${ready_code:-000}"
    exit 0
fi

models_code="$(curl -sS -o "$models_body" -w '%{http_code}' --connect-timeout 5 --max-time 10 \
    -H "Authorization: Bearer $token" "$base/v1/models" 2>/dev/null || true)"

case "$models_code" in
    200)
        if MODEL="$model" MODELS_BODY="$models_body" node 2>/dev/null <<'NODE'
const fs = require("fs");
const model = process.env.MODEL;
const body = JSON.parse(fs.readFileSync(process.env.MODELS_BODY, "utf8"));
const ids = Array.isArray(body.data) ? body.data.map((m) => m && m.id).filter(Boolean) : [];
process.exit(ids.includes(model) ? 0 : 1);
NODE
        then
            echo "Proxy preflight: proxy ready and model '$model' is available."
            emit "true" "ok" "proxy ready and model available"
        else
            echo "::warning::Proxy preflight: model '$model' not returned by /v1/models; skipping agent run."
            emit "false" "model-unavailable" "model not returned by /v1/models"
        fi
        ;;
    401|403)
        echo "::warning::Proxy preflight: /v1/models returned HTTP $models_code; skipping agent run."
        emit "false" "proxy-auth-failed" "/v1/models returned HTTP $models_code"
        ;;
    *)
        echo "::warning::Proxy preflight: /v1/models returned HTTP ${models_code:-000}; readiness passed, so running agent."
        emit "true" "models-probe-unavailable" "/v1/models returned HTTP ${models_code:-000}"
        ;;
esac
