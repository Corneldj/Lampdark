#!/usr/bin/env bash
# Runs every GUT test under tests/unit/ and tests/scenario/ headless and writes JUnit XML.
# Usage: tools/build/run_unit_tests.sh [junit_xml_path]
# The engine binary comes from $GODOT (default: godot). It must match versions.json.
# With GUT_SHARD=<i>/<n> it runs shard i of n alone (tools/build/gut_shard.py's balanced split).
set -euo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
JUNIT="${1:-$GAME_DIR/tests/reports/unit.xml}"
mkdir -p "$(dirname "$JUNIT")"

# Import pass, so a fresh clone has its .godot/ cache before tests load resources.
"$GODOT" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true

# GUT skips scripts that fail to parse, so compile everything first and stop on any error.
"$GODOT" --headless --path "$GAME_DIR" -s tools/build/check_scripts.gd

if [ -n "${GUT_SHARD:-}" ]; then
	CONFIG="$GAME_DIR/build/ci/gut_shard.json"
	python3 "$GAME_DIR/tools/build/gut_shard.py" "${GUT_SHARD%/*}" "${GUT_SHARD#*/}" "$CONFIG"
	"$GODOT" --headless --path "$GAME_DIR" -s addons/gut/gut_cmdln.gd -gconfig="$CONFIG" -gexit -gjunit_xml_file="$JUNIT"
else
	"$GODOT" --headless --path "$GAME_DIR" -s addons/gut/gut_cmdln.gd \
		-gconfig=res://.gutconfig.json \
		-gdir=res://tests/unit,res://tests/scenario -ginclude_subdirs -gexit \
		-gjunit_xml_file="$JUNIT"
fi
