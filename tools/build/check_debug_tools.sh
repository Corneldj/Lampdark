#!/usr/bin/env bash
# Debug-only tools stay out of release builds (FND-06, FND-09, SND-04). Exits 1 on a violation.
# Each marker below is compiled only with LB_DEBUG_TOOLS: every template_debug core library
# must carry it and no template_release one may.
#  - script_values: LbRng's scripted rolls (FND-09).
#  - set_screen_up: the listener's screen-up A/B mode for criterion 5 (SND-04).
#  - LbAuditReference: NET-08's reference visibility for the stream audit.
#  - LbSeedHarness: GEN-14's seed harness.
set -uo pipefail

MARKERS=(script_values set_screen_up LbAuditReference LbSeedHarness)

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR/native/bin"
status=0
found=0
for lib in liblampblack_core.*.template_debug.*; do
	[ -e "$lib" ] || continue
	found=1
	for marker in "${MARKERS[@]}"; do
		if ! grep -qa "$marker" "$lib"; then
			echo "FAIL: $lib lacks $marker (a debug build should have it)" >&2
			status=1
		fi
	done
done
for lib in liblampblack_core.*.template_release.*; do
	[ -e "$lib" ] || continue
	found=1
	clean=1
	for marker in "${MARKERS[@]}"; do
		if grep -qa "$marker" "$lib"; then
			echo "FAIL: $lib carries $marker; it must be absent from release builds" >&2
			status=1
			clean=0
		fi
	done
	[ "$clean" -eq 1 ] && echo "ok   $lib has no debug tools (${MARKERS[*]})"
done
if [ "$found" -eq 0 ]; then
	echo "FAIL: no core libraries in native/bin; build them first" >&2
	status=1
fi
exit "$status"
