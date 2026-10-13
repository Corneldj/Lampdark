#!/usr/bin/env bash
# FND-08: debug tools are stripped from release builds. Exits 1 on a violation.
#  1. Pack listing: no release pack carries a debug/ path (server/debug, client/debug, shared/debug).
#  2. Native flag: no release core library carries a debug-tools marker (check_debug_tools.sh).
#  3. String scan: no script a release pack ships names a debug class (each class_name declared under
#     a debug/ folder), so a release build never needs one; every debug piece is loaded by its path,
#     behind a release check, and that path is absent from the pack.
# Needs the exported packs in build/ (export_all.sh) and the native libraries in native/bin.
set -uo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
LISTER="tools/build/list_pack.py"
status=0

mapfile -t debug_classes < <(grep -rhoE '^class_name [A-Za-z_][A-Za-z0-9_]*' --include='*.gd' server/debug client/debug shared/debug 2>/dev/null | awk '{print $2}' | sort -u)
if [ "${#debug_classes[@]}" -eq 0 ]; then
	echo "FAIL: found no debug classes to scan for" >&2
	exit 1
fi
pattern="$(IFS='|'; echo "\\b(${debug_classes[*]})\\b")"

shopt -s nullglob
packs=(build/*-release/*.pck)
if [ "${#packs[@]}" -eq 0 ]; then
	echo "FAIL: no release packs under build/; run tools/build/export_all.sh first" >&2
	exit 1
fi
for pack in "${packs[@]}"; do
	listing="$(python3 "$LISTER" "$pack")"
	bad="$(grep -E '/debug/' <<<"$listing" || true)"
	if [ -n "$bad" ]; then
		echo "FAIL $pack carries debug paths:" >&2
		sed 's/^/  /' <<<"$bad" >&2
		status=1
	fi
	hits=""
	while IFS= read -r res; do
		src="${res#res://}"
		case "$src" in
			*.gd) ;;
			*) continue ;;
		esac
		[ -f "$src" ] || continue
		found="$(grep -nE "$pattern" "$src" | grep -vE '^[0-9]+:\s*##?' || true)"
		if [ -n "$found" ]; then
			hits="$hits"$'\n'"$src: $(head -1 <<<"$found")"
		fi
	done <<<"$listing"
	hits="$(sed '/^$/d' <<<"$hits")"
	if [ -n "$hits" ]; then
		echo "FAIL $pack ships scripts that name debug classes:" >&2
		sed 's/^/  /' <<<"$hits" >&2
		status=1
	else
		echo "ok   $pack: no debug path, no script naming ${#debug_classes[@]} debug classes"
	fi
done

if ! tools/build/check_debug_tools.sh; then
	status=1
fi
exit "$status"
