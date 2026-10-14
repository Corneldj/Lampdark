#!/usr/bin/env bash
# Runs the exported QA builds with --exit-after-ticks and expects exit code 0 (FND-03).
# Linux builds run natively. Windows builds run when $WINE is set (e.g. WINE=wine); on a
# Windows CI runner use smoke_exports.ps1 instead.
set -uo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${1:-$GAME_DIR/build}"
TICKS=40
status=0

run() {
	local name="$1"; shift
	local out
	out="$(timeout 120 "$@" --exit-after-ticks "$TICKS" 2>&1)"
	local code=$?
	if [ "$code" -eq 0 ] && grep -q "exit after $TICKS ticks" <<<"$out"; then
		echo "ok   $name"
	else
		echo "FAIL $name (exit $code)" >&2
		sed 's/^/  /' <<<"$out" | tail -20 >&2
		status=1
	fi
}

run linux-server-qa "$BUILD/linux-server-qa/lampblack_server.x86_64"
# Clients run with --no-steam: a smoke run must never sign a developer's running Steam in to the
# game (STM-01's live check, tools/build/steam_live_check.sh, does that on purpose).
run linux-client-qa "$BUILD/linux-client-qa/lampblack.x86_64" --headless --no-steam
if [ -n "${WINE:-}" ]; then
	run windows-server-qa "$WINE" "$BUILD/windows-server-qa/lampblack_server.exe"
	run windows-client-qa "$WINE" "$BUILD/windows-client-qa/lampblack.console.exe" --headless --no-steam
fi
exit "$status"
