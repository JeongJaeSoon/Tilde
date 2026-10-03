#!/bin/bash
# Downloads the pinned Sparkle release and checks its SHA-256. Used by the
# DMG build (scripts/build_direct.sh) and the appcast step
# (scripts/make_appcast.sh) — see #27.
#
#   scripts/fetch_sparkle.sh [dest-dir]   (default build/Sparkle)
#
# Prints the directory holding Sparkle.framework and bin/ (sign_update,
# generate_keys, …). A no-op once the pinned version is in place.

set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

DEST="${1:-build/Sparkle}"
STAMP="$DEST/.version"

if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$SPARKLE_VERSION" ]]; then
    echo "$DEST"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ARCHIVE="$TMP/Sparkle.tar.xz"

echo "fetching Sparkle $SPARKLE_VERSION" >&2
curl -fsSL -o "$ARCHIVE" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
echo "$SPARKLE_SHA256  $ARCHIVE" | shasum -a 256 -c - >&2

rm -rf "$DEST"
mkdir -p "$DEST"
tar -xJf "$ARCHIVE" -C "$DEST"
echo "$SPARKLE_VERSION" > "$STAMP"
echo "$DEST"
