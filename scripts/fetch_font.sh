#!/usr/bin/env bash
# Downloads the Manrope variable TTF (SIL OFL 1.1) into the movez resource bundle.
#
# The source is pinned to the google/fonts commit the committed font came from, and each file is
# checked against its SHA-256 before it replaces anything, so a re-fetch can never silently swap in
# a newer Manrope (which would shift every snapshot). Downloads go to a temporary file first: when
# every source fails, the committed font and licence are left exactly as they were.
set -euo pipefail

DEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Sources/movez/Resources/Fonts"
FONT_FILE="$DEST_DIR/Manrope[wght].ttf"
LICENCE_FILE="$DEST_DIR/OFL.txt"

# google/fonts commit 8f9a401 (2021-08-26), the version bundled since the first release. To move
# to a newer Manrope, change the commit and both checksums together and review the snapshots.
COMMIT="${MANROPE_COMMIT:-8f9a401dbb3793e0d1264b15d96aa253f05280f5}"
FONT_SHA256="d0639be45d0af36e798172419d7bd173c4bd4f29e2b76cbb69db1d11bf8b0a40"
LICENCE_SHA256="e01b637272e0cbdfb240184dd98ea5cc671556d9894dae2668d92ab2c906787c"

# The base URLs can be overridden, which is how the failure path is tested without the network.
PRIMARY_BASE="${MANROPE_PRIMARY_BASE:-https://github.com/google/fonts/raw/$COMMIT/ofl/manrope}"
MIRROR_BASE="${MANROPE_MIRROR_BASE:-https://cdn.jsdelivr.net/gh/google/fonts@$COMMIT/ofl/manrope}"

mkdir -p "$DEST_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fetch() {
  local url="$1" out="$2"
  curl --fail --location --silent --show-error --retry 2 --max-time 60 --output "$out" "$url"
}

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

download() {
  local name="$1" out="$2" sha="$3"
  local tmp="$TMP_DIR/$name"
  local source
  for source in "$PRIMARY_BASE" "$MIRROR_BASE"; do
    rm -f "$tmp"
    if fetch "$source/$name" "$tmp" && [ "$(sha256_of "$tmp")" = "$sha" ]; then
      mv -f "$tmp" "$out"
      echo "$name: fetched and verified from $source"
      return 0
    fi
    echo "$name: $source failed or did not match the pinned checksum" >&2
  done
  echo "$name: every source failed; the existing file is untouched" >&2
  return 1
}

status=0
download "Manrope%5Bwght%5D.ttf" "$FONT_FILE" "$FONT_SHA256" || status=1
download "OFL.txt" "$LICENCE_FILE" "$LICENCE_SHA256" || status=1
exit "$status"
