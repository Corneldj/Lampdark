#!/usr/bin/env bash
# Lists every exported pack in build/ and checks it against the export filter rules (FND-03).
# Client packs: nothing under server/, tests/, tools/ or addons/gut/; release clients also
# nothing in any debug/ folder. Server packs: nothing under client/, tests/, tools/ or
# addons/gut/; release servers nothing in debug/ either. Client packs carry exactly one tuning
# file, data/tuning/_client.json. Exits 1 on any violation.
set -euo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LISTER="$GAME_DIR/tools/build/list_pack.py"
BUILD="${1:-$GAME_DIR/build}"

shopt -s nullglob
packs=("$BUILD"/*/*.pck)
if [ "${#packs[@]}" -eq 0 ]; then
	echo "check_pack_contents: no packs under $BUILD" >&2
	exit 1
fi

status=0
for pack in "${packs[@]}"; do
	preset="$(basename "$(dirname "$pack")")"
	forbidden='^res://(tests|tools|addons/gut)/'
	case "$preset" in
		*-client-*) forbidden="$forbidden|^res://server/|^res://data/(maps|templates|world)/" ;;
		*-server-*) forbidden="$forbidden|^res://client/" ;;
		*) echo "check_pack_contents: cannot tell the role of $preset" >&2; status=1; continue ;;
	esac
	case "$preset" in
		*-release) forbidden="$forbidden|/debug/" ;;
	esac
	contents="$(python3 "$LISTER" "$pack")"
	bad="$(grep -E "$forbidden" <<<"$contents" || true)"
	case "$preset" in
		*-client-*)
			# Clients ship the client tuning table only, never a domain file (FND-05).
			tuning="$(grep -E '^res://data/tuning/' <<<"$contents" || true)"
			if [ "$tuning" != "res://data/tuning/_client.json" ]; then
				bad="$bad"$'\n'"tuning files must be exactly res://data/tuning/_client.json, got: $(tr '\n' ' ' <<<"$tuning")"
			fi
			;;
	esac
	bad="$(sed '/^$/d' <<<"$bad")"
	count="$(wc -l <<<"$contents")"
	if [ -n "$bad" ]; then
		echo "FAIL $preset: forbidden files in pack:" >&2
		sed 's/^/  /' <<<"$bad" >&2
		status=1
	else
		echo "ok   $preset ($count files)"
	fi
done
exit "$status"
