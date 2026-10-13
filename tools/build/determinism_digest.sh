#!/usr/bin/env bash
# Determinism digest (FND-06): runs lampblack_core_digest (10 million mixed draws across every
# hash domain) and prints the SHA-256 of its output. CI runs it on Windows and Linux and
# compares the digests (FND-04); they must be identical.
# Usage: tools/build/determinism_digest.sh [linux|windows] [template_release|template_debug]
#   windows on a Linux host runs the .exe under $WINE (default: wine).
set -euo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLATFORM="${1:-linux}"
TARGET="${2:-template_release}"
BIN="$GAME_DIR/native/bin/lampblack_core_digest.$PLATFORM.$TARGET.x86_64"
runner=()
if [ "$PLATFORM" = "windows" ]; then
	BIN="$BIN.exe"
	[ "$(uname -s)" = "Linux" ] && runner=("${WINE:-wine}")
fi
if [ ! -f "$BIN" ]; then
	echo "determinism_digest: $BIN not built; run tools/build/build_native.sh --platform $PLATFORM" >&2
	exit 1
fi
digest="$("${runner[@]}" "$BIN" | sha256sum | cut -d' ' -f1)"
mkdir -p "$GAME_DIR/build/digest"
echo "$digest" > "$GAME_DIR/build/digest/$PLATFORM.$TARGET.sha256"
echo "$digest  $PLATFORM.$TARGET"
