#!/usr/bin/env bash
# STM-01's live check against a running, signed-in Steam (manual: never in CI, never in smoke runs).
# A headless dev client from source initialises Steam with the project's app ID, logs the SteamID,
# persona, language, hardware and overlay state, pumps callbacks for a few seconds and shuts Steam
# down in order. While it runs, Steam shows the account as in-game. Exits non-zero unless every step
# appears in the log. Run from anywhere; it runs in game/, where steam_appid.txt sits for editor runs.
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
LOG="$(mktemp --suffix=.log)"
timeout 120 godot --headless --path . -- --exit-after-ticks "${TICKS:-180}" --log "$LOG" > /dev/null 2>&1
code=$?
status=0
for want in "steam: app [0-9]+, user 7656[0-9]+, language [a-z]+, hardware [A-Z_]+, overlay (on|off)" "steam: shut down" "exit after"; do
	if grep -qE "$want" "$LOG"; then echo "ok   $want"; else echo "FAIL missing: $want" >&2; status=1; fi
done
grep -E "steam:" "$LOG" | sed 's/^/  /'
[ "$code" -eq 0 ] || { echo "FAIL client exit $code" >&2; status=1; }
rm -f "$LOG"
exit "$status"
