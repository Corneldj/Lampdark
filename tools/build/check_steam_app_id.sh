#!/usr/bin/env bash
# STM-01's Steam build checks. Exits 1 on a violation.
#  1. The release flavour's app ID (lampblack/steam/app_id.lb_release, else lampblack/steam/app_id)
#     is set and is not 480 (Spacewar); so are the playtest and demo overrides when present.
#  2. No export ships steam_appid.txt: not in any pack, not beside any executable.
#  3. No server export can start the client API: no GodotSteam in its pack and no client GodotSteam
#     library beside it. A server may carry GodotSteam Server (the game-server API, STM-04's Path A)
#     in steam_server/ beside the executable, loaded at run time, and only there.
#  4. Only shared/platform/steam/steam_api.gd and steam_server_api.gd name a GodotSteam singleton, and
#     server/ never names SteamApi or SteamService (the client adapter).
set -uo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LISTER="$GAME_DIR/tools/build/list_pack.py"
BUILD="${1:-$GAME_DIR/build}"
cd "$GAME_DIR"
status=0
fail() { echo "FAIL $*" >&2; status=1; }

setting() {
	awk -v key="$1" '
		/^\[/ { section = $0; next }
		section == "[lampblack]" && index($0, key "=") == 1 { sub(/^[^=]*=/, ""); gsub(/"/, ""); print; exit }
	' project.godot
}
base="$(setting "steam/app_id")"
release="$(setting "steam/app_id.lb_release")"
release="${release:-$base}"
if [ -z "$release" ] || [ "$release" = "0" ]; then
	fail "the release app ID is not set (lampblack/steam/app_id.lb_release)"
elif [ "$release" = "480" ]; then
	fail "the release app ID is 480 (Spacewar)"
else
	echo "ok   release app ID $release"
fi
for tag in lb_playtest lb_demo; do
	v="$(setting "steam/app_id.$tag")"
	if [ "$v" = "480" ]; then fail "the $tag app ID is 480 (Spacewar)"; fi
done

shopt -s nullglob
packs=("$BUILD"/*/*.pck)
[ "${#packs[@]}" -gt 0 ] || { echo "check_steam_app_id: no packs under $BUILD" >&2; exit 1; }
for pack in "${packs[@]}"; do
	dir="$(dirname "$pack")"
	preset="$(basename "$dir")"
	if ! contents="$(python3 "$LISTER" "$pack")"; then
		fail "$preset: the pack cannot be listed"
		continue
	fi
	grep -q 'steam_appid\.txt$' <<<"$contents" && fail "$preset: steam_appid.txt in the pack"
	[ -e "$dir/steam_appid.txt" ] && fail "$preset: steam_appid.txt beside the executable"
	case "$preset" in
		*-server-*)
			grep -q '^res://addons/godotsteam/' <<<"$contents" && fail "$preset: GodotSteam in a server pack"
			libs="$(ls "$dir" | grep -E '(lib)?steam_api|godotsteam' || true)"
			[ -n "$libs" ] && fail "$preset: Steam libraries beside a server: $(tr '\n' ' ' <<<"$libs")"
			if [ -d "$dir/steam_server" ]; then
				client_lib="$(find "$dir/steam_server" -name 'libgodotsteam.*' -o -name 'godotsteam.gdextension' | head -1)"
				[ -n "$client_lib" ] && fail "$preset: the client GodotSteam in steam_server/: $client_lib"
			fi
			;;
		*-client-*)
			case "$preset" in
				windows-*) want="steam_api64.dll" ;;
				*) want="libsteam_api.so" ;;
			esac
			[ -e "$dir/$want" ] || fail "$preset: $want missing beside the client"
			;;
	esac
	[ "$status" -eq 0 ] && echo "ok   $preset"
done

singleton="$(grep -rlE '(get_singleton|has_singleton)\(&?"Steam(Server)?"|SINGLETON: StringName = &"Steam(Server)?"|^[^#]*\bSteam(Server)?\.[a-z]' \
	--include='*.gd' client server shared tools 2>/dev/null | grep -vE '^shared/platform/steam/steam(_server)?_api.gd$' || true)"
[ -n "$singleton" ] && fail "only shared/platform/steam/steam_api.gd and steam_server_api.gd may call GodotSteam: $(tr '\n' ' ' <<<"$singleton")"
server_refs="$(grep -rlE '\b(SteamApi|SteamService)\b' --include='*.gd' server 2>/dev/null || true)"
[ -n "$server_refs" ] && fail "server code names the client Steam API: $(tr '\n' ' ' <<<"$server_refs")"
[ "$status" -eq 0 ] && echo "ok   GodotSteam is called only by the adapter, and never by server code"
exit "$status"
