#!/usr/bin/env bash
# FND-04, per push: builds lampblack_core for Linux (native) and Windows (MinGW cross, FND-02),
# both targets, runs the Linux doctests (JUnit beside the binaries), checks the layering and the
# Windows imports, and writes the Linux determinism digest (FND-06). Windows runs its own doctests
# and digest on a Windows runner (ci_windows.ps1).
set -euo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
./tools/build/check_native_layering.sh
# With a cache (LB_SCONS_CACHE), SCons logs every cache entry it reads or writes, so the entries this
# build never touched can be pruned below: the cache holds one build's objects, not every build's.
# (--cache-debug=- writes to stdout: a file would be overwritten by each SCons call.)
used="$(mktemp)"
if [ -n "${LB_SCONS_CACHE:-}" ]; then
	export SCONSFLAGS="${SCONSFLAGS:-} --cache-debug=-"
fi
./tools/build/build_native.sh --test 2>&1 | tee -a "$used"
./tools/build/build_native.sh --platform windows 2>&1 | tee -a "$used"
./tools/build/check_windows_imports.sh
./tools/build/determinism_digest.sh linux template_release
if [ -n "${LB_SCONS_CACHE:-}" ] && [ -d "$LB_SCONS_CACHE" ]; then
	python3 tools/build/prune_scons_cache.py "$LB_SCONS_CACHE" "$used"
fi
