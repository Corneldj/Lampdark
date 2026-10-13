#!/usr/bin/env bash
# Exports presets from export_presets.cfg into build/<preset>/ (FND-03).
# Usage: tools/build/export_all.sh [preset ...]     (default: every preset)
# QA and kill-test presets use the debug template; release presets the release template.
# The engine binary comes from $GODOT (default: godot); export templates must match versions.json.
set -euo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
cd "$GAME_DIR"

if [ "$#" -gt 0 ]; then
	presets=("$@")
else
	mapfile -t presets < <(sed -n 's/^name="\(.*\)"$/\1/p' export_presets.cfg)
fi

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

failed=0
for preset in "${presets[@]}"; do
	path="$(awk -v want="$preset" '
		/^name="/ { gsub(/^name="|"$/, ""); name = $0 }
		/^export_path="/ && name == want { gsub(/^export_path="|"$/, ""); print; exit }
	' export_presets.cfg)"
	if [ -z "$path" ]; then
		echo "export_all: unknown preset $preset" >&2
		failed=1
		continue
	fi
	mode="--export-debug"
	case "$preset" in *-release) mode="--export-release" ;; esac
	rm -rf "$(dirname "$path")"
	mkdir -p "$(dirname "$path")"
	log="$(dirname "$path")/export.log"
	if "$GODOT" --headless --path . "$mode" "$preset" "$path" >"$log" 2>&1 && [ -f "$path" ] \
		&& ! grep -q "^ERROR" "$log"; then
		echo "exported $preset -> $path"
	else
		echo "export_all: $preset failed (see $log)" >&2
		grep "^ERROR" -A1 "$log" >&2 || true
		failed=1
	fi
done
exit "$failed"
