# Runs every GUT test under tests/unit/ headless and writes JUnit XML.
# Usage: tools/build/run_unit_tests.ps1 [-JUnit <path>]
# The engine binary comes from $env:GODOT (default: godot). It must match versions.json.
param(
	[string]$JUnit = ""
)
$ErrorActionPreference = "Stop"

$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
if ($JUnit -eq "") { $JUnit = Join-Path $GameDir "tests\reports\unit.xml" }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $JUnit) | Out-Null

# Import pass, so a fresh clone has its .godot/ cache before tests load resources.
& $Godot --headless --path $GameDir --import *> $null

# GUT skips scripts that fail to parse, so compile everything first and stop on any error.
& $Godot --headless --path $GameDir -s tools/build/check_scripts.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Godot --headless --path $GameDir -s addons/gut/gut_cmdln.gd `
	-gconfig=res://.gutconfig.json `
	-gdir=res://tests/unit,res://tests/scenario -ginclude_subdirs -gexit `
	"-gjunit_xml_file=$JUnit"
exit $LASTEXITCODE
