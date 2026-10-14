#!/usr/bin/env bash
# Module dependency rules (VIS-02 and later tickets). Exits 1 on a violation.
#  - The illusion stage (CRT-10) never reaches the light registry: no file whose path names
#    "illusion" may reference LbLightGrid, LightSystem or native/src/core/light.
#  - Creature senses are never rewound (NET-06): no creature, pacing (director), illusion or
#    perception (light, sound, vision) code may reference the Rewind history. Creatures reach
#    lag compensation only through DefenderRule. ROOT overrides the tree checked (for tests).
#  - Flame states are real only (VIS-08): illusion and client prediction code never reach them.
#  - No simulation module depends on the illusion stage (GDD §9.2, NET-08): systems, creatures,
#    pacing, world and the sim core never name it; the illusion stage reads them, never the reverse.
#  - NET-08's audit reference is independent: native/src/audit includes no light, vision or sound
#    code, and tools/stream_audit calls no production visibility, light-query or Road Graph method
#    (it reads geometry, the light grid's source list, NET-04's tokens and the logs only).
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
sim_files="$(find server -type f -name '*.gd' \( -path 'server/systems/*' -o -path 'server/creatures/*' -o -path 'server/director/*' \
	-o -path 'server/world/*' -o -path 'server/sim/*' \) ! -path '*illusion*' 2>/dev/null)"
if [ -n "$sim_files" ]; then
	hits="$(grep -HnE 'Illusion[A-Za-z_]*|illusion_[a-z_]+|/illusion' $sim_files | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
	if [ -n "$hits" ]; then
		echo "FAIL: a simulation module depends on the illusion stage:" >&2
		echo "$hits" | sed 's/^/  /' >&2
		status=1
	fi
fi
audit_native="$(find native/src/audit -type f \( -name '*.cpp' -o -name '*.h' \) 2>/dev/null)"
if [ -n "$audit_native" ]; then
	hits="$(grep -HnE '#include "core/(light|vision|sound)/' $audit_native || true)"
	if [ -n "$hits" ]; then
		echo "FAIL: the audit's reference includes production visibility or Road Graph code:" >&2
		echo "$hits" | sed 's/^/  /' >&2
		status=1
	fi
fi
audit_gd="$(find tools/stream_audit -type f -name '*.gd' 2>/dev/null)"
if [ -n "$audit_gd" ]; then
	hits="$(grep -HnE 'LbVision|LbRoadGraph|vision\.native|frame_for\(|\.propagate\(|\.deliver\(|\.rock_line\(|VoiceRoutes\.[a-z_]+\(|VisionSystem\.[a-z_]+\(|light_at\(|lit_in_sight|tiles_at_or_above|value_at\(|tile_light|owned_lights|owned_radius|seen_entities|margin_band|\.value\(|RoadGraphService\.[a-z_]+\(' $audit_gd | grep -vE 'ref\.light_at\(' || true)"
	if [ -n "$hits" ]; then
		echo "FAIL: the stream audit calls production visibility, light queries or the Road Graph:" >&2
		echo "$hits" | sed 's/^/  /' >&2
		status=1
	fi
fi
[ "$status" -eq 0 ] && echo "ok   module dependencies (illusions never reach the light registry; senses never rewound; flame states real only; no sim module reaches the illusion stage; the audit's reference stands alone)"
exit "$status"
