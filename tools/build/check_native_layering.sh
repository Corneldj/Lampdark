#!/usr/bin/env bash
# Checks the native layering rules (FND-02):
#  - no file under native/src/core/ includes a Godot header;
#  - the godot-cpp submodule commit equals versions.json's godot_cpp.godot_cpp_ref.
set -euo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
status=0

offenders="$(grep -rnE '#\s*include\s*[<"](godot_cpp/|gdextension_interface|godot/)' "$GAME_DIR/native/src/core" || true)"
if [ -n "$offenders" ]; then
	echo "FAIL: src/core/ includes Godot headers:" >&2
	echo "$offenders" >&2
	status=1
else
	echo "ok   src/core/ is engine-free"
fi

pinned="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["godot_cpp"]["godot_cpp_ref"])' "$GAME_DIR/versions.json")"
# The commit the repository records for the submodule, which holds even where it is not checked
# out (FND-04's checks job); and the checkout itself, where there is one.
recorded="$(git -C "$GAME_DIR" ls-tree HEAD native/godot-cpp 2>/dev/null | awk '{print $3}')"
recorded="${recorded:-missing}"
checkout=""
if [ -e "$GAME_DIR/native/godot-cpp/.git" ]; then
	checkout="$(git -C "$GAME_DIR/native/godot-cpp" rev-parse HEAD 2>/dev/null || echo missing)"
fi
if [ "$pinned" != "$recorded" ]; then
	echo "FAIL: the repository records godot-cpp at $recorded, versions.json pins $pinned" >&2
	status=1
elif [ -n "$checkout" ] && [ "$checkout" != "$pinned" ]; then
	echo "FAIL: godot-cpp is checked out at $checkout, versions.json pins $pinned" >&2
	status=1
else
	echo "ok   godot-cpp at the pinned commit ${pinned:0:12}"
fi
exit "$status"
