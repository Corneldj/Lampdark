#!/usr/bin/env bash
# FND-04, per push: the static checks, tuning validation and generated-file freshness (FND-05,
# FND-07) and the voice set (SND-13). Runs every check and reports each; fails if any failed.
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
GODOT="${GODOT:-godot}"
status=0
step() {
	local name="$1"; shift
	if "$@" > "build/ci/$name.log" 2>&1; then
		echo "ok   $name"
	else
		echo "FAIL $name"; sed 's/^/  /' "build/ci/$name.log" | tail -30; status=1
	fi
}
mkdir -p build/ci
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
for c in check_client_protocol check_determinism_rules check_module_deps check_native_layering check_voice_privacy \
	check_bot_paths check_noise_entry check_debug_tools; do
	step "$c" "./tools/build/$c.sh"
done
# The design documents sit beside the game folder, outside this repository: without them only the
# keys are checked (FND-05's row matching runs locally, where the vault holds both).
coverage_args=()
[ -f "../../Docs/Design/LAMPBLACK - Gameplay.md" ] || coverage_args=(-- --keys-only)
step tuning_coverage "$GODOT" --headless --path . -s tools/build/check_tuning_coverage.gd "${coverage_args[@]}"
step tuning_client_table "$GODOT" --headless --path . -s tools/build/gen_tuning_client.gd -- --check
step tuning_keys "$GODOT" --headless --path . -s tools/build/gen_tuning_keys.gd -- --check
step voice_set python3 tools/build/voice_import/voice_import.py check --decode
step voice_tool python3 -m unittest discover -s tools/build/voice_import/tests
exit $status
