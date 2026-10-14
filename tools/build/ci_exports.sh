#!/usr/bin/env bash
# FND-04, per push: every export preset (FND-03; Windows presets too, from Linux), the pack-content
# check, the release-strip check (FND-08), STM-01's Steam checks and the Linux smoke runs. The Windows smoke runs on a
# Windows runner (smoke_exports.ps1) from these exports.
set -euo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
./tools/build/export_all.sh
./tools/build/check_pack_contents.sh
./tools/build/check_release_strip.sh
./tools/build/check_steam_app_id.sh
./tools/build/smoke_exports.sh
