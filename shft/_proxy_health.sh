#!/usr/bin/env bash
# Shared proxy health helpers for shft runtime scripts.
#
# Intended to be sourced by shft/shft and shft/_proxy_env.sh.
# Relies on curl (and shell builtins). Uses ip+awk opportunistically to discover
# a host route, then falls back to localhost.

_proxy_default_host() {
    local _host
    if command -v awk &>/dev/null; then
        _host=$( (command -v ip &>/dev/null && ip route 2>/dev/null || true) | awk '/default/{print $3; exit}')
    fi
    printf '%s' "${_host:-localhost}"
}

_proxy_health_ok() {
    local _port="${1:-${SHFT_PROXY_DEFAULT_PORT:-4000}}"
    local _check_host="${2:-}"
    if [[ -z "$_check_host" ]]; then
        _check_host="$(_proxy_default_host)"
    fi
    curl -sf --max-time 2 --connect-timeout 1 "http://${_check_host}:${_port}/health/readiness" >/dev/null 2>&1 \
      || curl -sf --max-time 2 --connect-timeout 1 "http://localhost:${_port}/health/readiness" >/dev/null 2>&1
}

_proxy_wait_healthy() {
    local _port="${1:-${SHFT_PROXY_DEFAULT_PORT:-4000}}"
    local _wait_seconds="${2:-30}"
    # Coerce to integer — prevents arithmetic errors under set -e if caller
    # passes a non-numeric SHFT_PROXY_HEALTH_WAIT_SECONDS value.
    _wait_seconds="${_wait_seconds%%[!0-9]*}"
    _wait_seconds="${_wait_seconds:-30}"
    local _check_host
    _check_host="$(_proxy_default_host)"
    local _start=$SECONDS
    while (( SECONDS - _start < _wait_seconds )); do
        if _proxy_health_ok "$_port" "$_check_host"; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}
