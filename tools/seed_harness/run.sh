#!/usr/bin/env bash
# GEN-14: the seed harness (tools/seed_harness/run.gd) from the game's root, with the same
# arguments: run.sh [--seeds N|A..B] [--lists ...] [--report DIR] ... | --repro SEED LIST CHECK [X,Y]
# Needs a dev or QA native library (LbSeedHarness is never in a release one).
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
exec "${GODOT:-godot}" --headless --path . -s tools/seed_harness/run.gd -- "$@"
