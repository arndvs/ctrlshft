#!/usr/bin/env bash
# sync-hub-templates.sh — Keep the hub's canonical workflow templates in sync
# with the producer's shft/templates mirror.
#
# The hub (arndvs/sandcastle-hub) is the single source of truth for the
# Sandcastle engine AND its workflow templates. The producer (ctrlshft /
# shft/templates) mirrors the shared template contract so consumers installed
# via init-sandcastle get identical stubs regardless of which checkout
# resolves first.
#
# Shared template names (consumer contract):
#   agent-*.yml (12), labels-sync.yml, sandcastle-drift.yml
# Producer-owned templates (NOT synced):
#   check-attribution.yml, require-regression-guard.yml
#
# Usage:
#   bash bin/sync-hub-templates.sh                    # copy hub -> producer
#   bash bin/sync-hub-templates.sh --check            # parity check only
#   bash bin/sync-hub-templates.sh --dry-run         # show what would copy
#
# Exits non-zero on --check if the shared templates differ.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
source "$DOTFILES/bin/_lib.sh"

HUB="${HUB:-$HOME/dev/clients/sandcastle-hub}"
PRODUCER="${PRODUCER:-$HOME/dev/clients/ctrlshft-public}"

CHECK_ONLY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)     CHECK_ONLY=true; shift ;;
        --dry-run)   DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: sync-hub-templates.sh [--check] [--dry-run]"
            echo "  --check     Parity check only — exit non-zero on drift."
            echo "  --dry-run   Show what would be copied without copying."
            echo ""
            echo "Copies shared workflow templates: hub/templates/workflows ->"
            echo "producer shft/templates/workflows for the 14 shared names"
            echo "(12 agent-*, labels-sync, sandcastle-drift)."
            echo "Producer-owned: check-attribution, require-regression-guard kept."
            exit 0
            ;;
        *) red "Unknown arg: $1"; exit 1 ;;
    esac
done

if [[ ! -d "$HUB/templates/workflows" ]]; then
    red "Hub templates dir not found: $HUB/templates/workflows"
    exit 1
fi
if [[ ! -d "$PRODUCER/shft/templates/workflows" ]]; then
    red "Producer templates dir not found: $PRODUCER/shft/templates/workflows"
    exit 1
fi

SHARED_NAMES=()
for f in "$HUB"/templates/workflows/agent-*.yml; do
    [[ -f "$f" ]] && SHARED_NAMES+=("$(basename "$f")")
done
for f in labels-sync.yml sandcastle-drift.yml; do
    [[ -f "$HUB/templates/workflows/$f" ]] && SHARED_NAMES+=("$f")
done

drift=0
copied=0

for name in "${SHARED_NAMES[@]}"; do
    hub_path="$HUB/templates/workflows/$name"
    prod_path="$PRODUCER/shft/templates/workflows/$name"

    if [[ ! -f "$prod_path" ]]; then
        red "MISSING in producer: $name"
        drift=1
        continue
    fi

    if diff -q "$hub_path" "$prod_path" >/dev/null 2>&1; then
        green "$name in sync"
    else
        yellow "DRIFT: $name differs between hub and producer"
        drift=1
        if [[ "$CHECK_ONLY" == false && "$DRY_RUN" == false ]]; then
            cp "$hub_path" "$prod_path"
            echo "    copied -> $prod_path"
            copied=$((copied + 1))
        elif [[ "$DRY_RUN" == true ]]; then
            echo "    (dry-run) would copy -> $prod_path"
        fi
    fi
done

echo ""
if [[ "$CHECK_ONLY" == true || "$DRY_RUN" == true ]]; then
    if [[ "$drift" -eq 0 ]]; then
        green "Parity OK — ${#SHARED_NAMES[@]} shared templates in sync (hub == producer)."
    else
        yellow "Drift detected in $drift template(s) — hub and producer differ."
        exit 1
    fi
else
    if [[ "$copied" -gt 0 ]]; then
        green "Synced $copied template(s) from hub to producer."
    else
        green "Already in sync — ${#SHARED_NAMES[@]} shared templates match."
    fi
    if [[ "$drift" -ne 0 ]]; then
        yellow "$drift template(s) had drifted and were corrected."
    fi
fi

exit 0