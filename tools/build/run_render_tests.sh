#!/usr/bin/env bash
# VIS-05: the render tests (tests/unit/vis/render) with a real renderer. Godot runs inside a headless
# gamescope compositor (no window appears), with the GL Compatibility renderer, and the tests capture
# the root viewport. In the plain headless suite the same tests are pending: the dummy renderer draws
# nothing. Exits 1 on a failure, 2 when no renderer could start.
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
GAMESCOPE="${GAMESCOPE:-gamescope}"
if ! command -v "$GAMESCOPE" >/dev/null 2>&1; then
	echo "run_render_tests: gamescope not found (set GAMESCOPE)" >&2
	exit 2
fi
"$GODOT" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true
log="$(mktemp)"
timeout 900 "$GAMESCOPE" --backend headless -W 1920 -H 1080 -w 1920 -h 1080 -- \
	"$GODOT" --path "$GAME_DIR" --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd \
	-gconfig=res://tools/build/gut_render.json > "$log" 2>&1
grep -aE "^res://|^\* |Passing Tests|Failing Tests|Pending|\[Failed\]|renderer:" -A2 "$log" | grep -v "^\s*\[[0-9]\]" | grep -v "^--$"
if grep -aq "Failing Tests" "$log" || grep -aq "\[Failed\]" "$log"; then
	rm -f "$log"
	exit 1
fi
if ! grep -aq "Passing Tests" "$log"; then
	echo "run_render_tests: no test totals (the renderer did not start?)" >&2
	tail -20 "$log" >&2
	rm -f "$log"
	exit 2
fi
rm -f "$log"
exit 0
