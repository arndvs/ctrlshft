#!/usr/bin/env bash
# update-sandcastle.sh — DEPRECATED.
#
# The Sandcastle engine is no longer vendored into consumer repos. It lives in
# the public hub repo `arndvs/ctrlshft-hub` (single source of truth), and
# consumers reference it remotely via `uses: arndvs/ctrlshft-hub/...@<ref>`.
#
# This script previously detected drift between vendored Sandcastle files and
# the source checkout, then re-vendored them. That flow is retired — there is
# nothing to vendor. Consumers hold only thin workflow stubs + a
# `.sandcastle/hub-version.json` SHA-lock.
#
# This wrapper is kept so `ctrl update-sandcastle` and any scripts that call it
# fail with a clear, actionable message instead of a confusing error.
#
# Replacement: hub releases are managed in the hub repo:
#   cd ~/dev/clients/ctrlshft-hub && hub/release.sh [patch|minor|major|<version>]
#
# Consumers pin via `.sandcastle/hub-version.json` (ref + lastPinnedSha) and the
# SHA-drift workflow opens a review PR when the hub advances.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Usage: ctrl update-sandcastle"
            echo ""
            echo "DEPRECATED — the Sandcastle engine is no longer vendored."
            echo ""
            echo "The engine lives in arndvs/ctrlshft-hub (single source of truth)."
            echo "Consumers reference it remotely; nothing is vendored."
            echo ""
            echo "To release a new hub version:"
            echo "  cd ~/dev/clients/ctrlshft-hub && hub/release.sh [patch|minor|major|<version>]"
            echo ""
            echo "Consumers pin via .sandcastle/hub-version.json; the SHA-drift"
            echo "workflow opens a review PR when the hub advances."
            exit 0
            ;;
    esac
done

yellow "update-sandcastle is deprecated — the Sandcastle engine is no longer vendored."
yellow ""
yellow "The engine lives in arndvs/ctrlshft-hub (single source of truth)."
yellow "Consumers reference it remotely via 'uses: arndvs/ctrlshft-hub/...@<ref>'."
yellow ""
yellow "To release a new hub version:"
yellow "  cd ~/dev/clients/ctrlshft-hub && hub/release.sh [patch|minor|major|<version>]"
yellow ""
yellow "Consumers pin via .sandcastle/hub-version.json; the SHA-drift workflow"
yellow "opens a review PR when the hub advances."
echo ""
exit 0
