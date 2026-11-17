#!/usr/bin/env bash
# Renders every snapshot and copies the one that best matches each approved design screen to
# $RELAY_DESIGN_CHECK_DIR/<screen id>.png, so the built screens can be laid beside the design's.
#
#     RELAY_DESIGN_CHECK_DIR=<dir> bash scripts/capture_design_check.sh
#
# The folder comes only from that variable, so no review path is ever written into the product.
set -euo pipefail

if [[ -z "${RELAY_DESIGN_CHECK_DIR:-}" ]]; then
  echo "capture_design_check.sh: set RELAY_DESIGN_CHECK_DIR to the folder the captures go in" >&2
  exit 2
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOTS="$REPO/build/snapshots"

# Each approved screen id, then the snapshot surface that shows it. Where the ids match, the
# surface has the design's name.
PAIRS=(
  "strength-set overlay-strength-set"
  "endrange-break overlay-endrange"
  "strength-headsup headsup-strength"
  "strength-micro micro-strength-running"
  "menu-strength menu-strength"
  "menu-icons menu-icons"
  "mode-badges mode-badges"
  "settings-strength settings-strength"
  "overlay overlay-full"
  "micro-panel micro-running"
  "headsup headsup"
  "menu menu-sitting"
  "settings settings"
)

(cd "$REPO" && make snapshots)

mkdir -p "$RELAY_DESIGN_CHECK_DIR"
missing=0
for pair in "${PAIRS[@]}"; do
  read -r id surface <<< "$pair"
  source="$SNAPSHOTS/$surface.png"
  if [[ -f "$source" ]]; then
    cp "$source" "$RELAY_DESIGN_CHECK_DIR/$id.png"
    echo "captured $id <- $surface"
  else
    echo "missing snapshot for $id: $surface.png" >&2
    missing=$((missing + 1))
  fi
done

[[ $missing -eq 0 ]] || exit 1
