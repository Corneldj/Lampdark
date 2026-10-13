#!/usr/bin/env bash
# FND-04, per push: builds lampblack_core for Linux (native) and Windows (MinGW cross, FND-02),
# both targets, runs the Linux doctests (JUnit beside the binaries), checks the layering and the
# Windows imports, and writes the Linux determinism digest (FND-06). Windows runs its own doctests
# and digest on a Windows runner (ci_windows.ps1).
set -euo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
./tools/build/check_native_layering.sh
./tools/build/build_native.sh --test
./tools/build/build_native.sh --platform windows
./tools/build/check_windows_imports.sh
./tools/build/determinism_digest.sh linux template_release
