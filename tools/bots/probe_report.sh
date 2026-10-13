#!/usr/bin/env bash
# NET-12: the criterion-4 report from one command (QA-01 runs it; Q11 at --rtt 200):
#   tools/bots/probe_report.sh --rtt 120 --loss 0.02 [--minutes 1] [--seed S] [--out DIR]
# Exits 0 on a pass, 1 on a fail. The engine binary comes from $GODOT (default: godot).
set -euo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
exec "$GODOT" --headless --path "$GAME_DIR" -s tools/bots/probe_report.gd -- "$@"
