#!/usr/bin/env bash
# Shared proxy health helpers for shft runtime scripts.
#
# Intended to be sourced by shft/shft and shft/_proxy_env.sh.
# Relies only on curl + shell builtins.

_proxy_health_ok() {
    local _port="${1:-${SHFT_PROXY_DEFAULT_PORT:-4000}}"
    local _check_host
    _check_host=$( (ip route 2>/dev/null || true) | awk '/default/{print $3; exit}')
    _check_host="${_check_host:-localhost}"
    curl -sf --max-time 2 --connect-timeout 1 "http://${_check_host}:${_port}/health/readiness" >/dev/null 2>&1 \
      || curl -sf --max-time 2 --connect-timeout 1 "http://localhost:${_port}/health/readiness" >/dev/null 2>&1
}

_proxy_wait_healthy() {
    local _port="${1:-${SHFT_PROXY_DEFAULT_PORT:-4000}}"
    local _wait_seconds="${2:-30}"
    if [[ ! "$_wait_seconds" =~ ^[0-9]+$ ]]; then
        _wait_seconds=30
    fi
    local _attempts=$((_wait_seconds * 2))
    local _i=0
    while [[ $_i -lt $_attempts ]]; do
        if _proxy_health_ok "$_port"; then
            return 0
        fi
        sleep 0.5
        _i=$((_i + 1))
    done
    return 1
}
