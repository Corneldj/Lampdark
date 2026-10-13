#!/usr/bin/env bash
# Module dependency rules (VIS-02 and later tickets). Exits 1 on a violation.
#  - The illusion stage (CRT-10) never reaches the light registry: no file whose path names
#    "illusion" may reference LbLightGrid, LightSystem or native/src/core/light.
#  - Creature senses are never rewound (NET-06): no creature, pacing (director), illusion or
#    perception (light, sound, vision) code may reference the Rewind history. Creatures reach
#    lag compensation only through DefenderRule. ROOT overrides the tree checked (for tests).
#  - Flame states are real only (VIS-08): illusion and client prediction code never reach them.
set -uo pipefail

GAME_DIR="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$GAME_DIR"
status=0

illusion_files="$(find server shared native/src -path '*illusion*' -type f \( -name '*.gd' -o -name '*.cpp' -o -name '*.h' \) 2>/dev/null)"
if [ -n "$illusion_files" ]; then
	hits="$(grep -nE 'LbLightGrid|LightSystem|core/light/' $illusion_files || true)"
	if [ -n "$hits" ]; then
		echo "FAIL: the illusion module depends on the light registry:" >&2
		echo "$hits" | sed 's/^/  /' >&2
		status=1
	fi
fi
sense_files="$(find server shared -type f -name '*.gd' \( -path '*creature*' -o -path '*director*' -o -path '*pacing*' \
	-o -path '*illusion*' -o -path 'server/systems/light/*' -o -path 'server/systems/sound/*' -o -path 'server/systems/vision/*' \) 2>/dev/null)"
if [ -n "$sense_files" ]; then
	hits="$(grep -nE '\bRewind\b|rewind\.gd|\.rewind\b' $sense_files || true)"
	if [ -n "$hits" ]; then
		echo "FAIL: creature perception, pacing or illusion code depends on the rewind history:" >&2
		echo "$hits" | sed 's/^/  /' >&2
		status=1
	fi
fi
# VIS-08 (Clause 4): flame states come only from the real world. Neither the illusion stage nor
# client prediction may set or read the server's flame states.
flame_files="$(find server shared client -type f -name '*.gd' \( -path '*illusion*' -o -path 'client/net/prediction.gd' \
	-o -path 'client/net/reconciler.gd' \) 2>/dev/null)"
if [ -n "$flame_files" ]; then
	hits="$(grep -nE '\bFlameStates\b|flame_states|set_flare_up' $flame_files || true)"
	if [ -n "$hits" ]; then
		echo "FAIL: the illusion stage or client prediction reaches the flame states:" >&2
		echo "$hits" | sed 's/^/  /' >&2
		status=1
	fi
fi
[ "$status" -eq 0 ] && echo "ok   module dependencies (illusions never reach the light registry; senses never rewound; flame states real only)"
exit "$status"
