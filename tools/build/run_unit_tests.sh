#!/usr/bin/env bash
# Runs every GUT test under tests/unit/ headless and writes JUnit XML.
# Usage: tools/build/run_unit_tests.sh [junit_xml_path]
# The engine binary comes from $GODOT (default: godot). It must match versions.json.
set -euo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
JUNIT="${1:-$GAME_DIR/tests/reports/unit.xml}"
mkdir -p "$(dirname "$JUNIT")"

# Import pass, so a fresh clone has its .godot/ cache before tests load resources.
"$GODOT" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true

# GUT skips scripts that fail to parse, so compile everything first and stop on any error.
"$GODOT" --headless --path "$GAME_DIR" -s tools/build/check_scripts.gd

"$GODOT" --headless --path "$GAME_DIR" -s addons/gut/gut_cmdln.gd \
	-gconfig=res://.gutconfig.json \
	-gdir=res://tests/unit,res://tests/scenario -ginclude_subdirs -gexit \
	-gjunit_xml_file="$JUNIT"
