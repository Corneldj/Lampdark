#!/usr/bin/env bash
# QA-01: a dry run of criterion 2's instrument. Runs the kit scenario that makes a dev server write
# real "voice loss" lines, then checks them against Gameplay §6.2 with voice_log_check.py.
# Usage: tools/kill_test/voice_dry_run.sh [--json]
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
LOG="$(mktemp --suffix=.log)"
timeout 900 "${GODOT:-godot}" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/scenario/kill_test \
	-gselect=test_voice_log_dry_run -gexit > "$LOG" 2>&1
if ! grep -q "Passing Tests" "$LOG"; then
	echo "voice_dry_run: the scenario did not finish" >&2
	tail -20 "$LOG" >&2
	rm -f "$LOG"
	exit 2
fi
python3 tools/kill_test/voice_log_check.py "$@" "$LOG"
code=$?
rm -f "$LOG"
exit "$code"
