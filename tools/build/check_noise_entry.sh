#!/usr/bin/env bash
# SND-02: every sound goes through NoiseSystem.emit, so nothing outside the noise module calls
# the Road Graph's propagation directly. Exits 1 on a violation. Tests are exempt (SND-01's
# own tests exercise propagation); a line marked "noise-entry: allow" is too.
set -uo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
hits="$(grep -rnE '\.propagate\(' server shared client tools --include='*.gd' \
	| grep -vE '^server/systems/sound/(noise|road_graph_service)\.gd:' \
	| grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v 'noise-entry: allow' || true)"
if [ -n "$hits" ]; then
	echo "FAIL: Road Graph propagation outside NoiseSystem (use run.noise.emit):" >&2
	echo "$hits" | sed 's/^/  /' >&2
	exit 1
fi
echo "ok   every sound enters through NoiseSystem.emit"
