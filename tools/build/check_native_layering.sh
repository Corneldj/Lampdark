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
actual="$(git -C "$GAME_DIR/native/godot-cpp" rev-parse HEAD 2>/dev/null || echo missing)"
if [ "$pinned" != "$actual" ]; then
	echo "FAIL: godot-cpp is at $actual, versions.json pins $pinned" >&2
	status=1
else
	echo "ok   godot-cpp at the pinned commit ${pinned:0:12}"
fi
exit "$status"
