#!/usr/bin/env bash
# Downloads the Manrope variable TTF (SIL OFL 1.1) into the movez resource bundle.
set -euo pipefail

DEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Sources/movez/Resources/Fonts"
FONT_FILE="$DEST_DIR/Manrope[wght].ttf"
LICENCE_FILE="$DEST_DIR/OFL.txt"

PRIMARY="https://github.com/google/fonts/raw/main/ofl/manrope/Manrope%5Bwght%5D.ttf"
MIRROR="https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/manrope/Manrope%5Bwght%5D.ttf"
LICENCE_PRIMARY="https://github.com/google/fonts/raw/main/ofl/manrope/OFL.txt"
LICENCE_MIRROR="https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/manrope/OFL.txt"

mkdir -p "$DEST_DIR"

fetch() {
  local url="$1" out="$2"
  curl --fail --location --silent --show-error --retry 2 --max-time 60 --output "$out" "$url"
}

size_of() { stat -f%z "$1" 2>/dev/null || echo 0; }

download() {
  local primary="$1" mirror="$2" out="$3" min_size="$4" label="$5"
  if fetch "$primary" "$out" && [ "$(size_of "$out")" -gt "$min_size" ]; then
    echo "$label: fetched from googlefonts ($(size_of "$out") bytes)"
    return 0
  fi
  echo "$label: primary source failed, trying jsDelivr mirror" >&2
  if fetch "$mirror" "$out" && [ "$(size_of "$out")" -gt "$min_size" ]; then
    echo "$label: fetched from jsDelivr ($(size_of "$out") bytes)"
    return 0
  fi
  echo "$label: both sources failed" >&2
  rm -f "$out"
  return 1
}

download "$PRIMARY" "$MIRROR" "$FONT_FILE" 51200 "Manrope[wght].ttf"
download "$LICENCE_PRIMARY" "$LICENCE_MIRROR" "$LICENCE_FILE" 1024 "OFL.txt"
