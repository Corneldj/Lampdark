#!/usr/bin/env bash
# Runs a soak (FND-09): run_soak.sh <soak> [--servers N] [--bots M] [--minutes T] [--seed S]
#   [--link rtt,loss] [--out DIR] [--port P] [--accelerated]
# Soaks live in tools/bots/soaks/<soak>.gd. The engine binary comes from $GODOT (default: godot).
# Writes <out>/report.json (default build/soaks/<soak>/) and exits non-zero on a crash, an
# unscripted disconnect or a failed verify.
set -euo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
exec "$GODOT" --headless --path "$GAME_DIR" -s tools/bots/orchestrator.gd -- "$@"
