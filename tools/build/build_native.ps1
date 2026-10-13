# Builds lampblack_core on Windows with MSVC (FND-02): template_debug and template_release,
# plus the doctest runner, into native\bin\. Release symbols stay in PDB files beside the
# DLL; CI archives them and never ships them (STM-12).
# Usage: tools/build/build_native.ps1 [-Targets template_debug,template_release] [-Test]
param(
	[string[]]$Targets = @("template_debug", "template_release"),
	[switch]$Test
)
$ErrorActionPreference = "Stop"
$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Native = Join-Path $GameDir "native"

if (-not (Test-Path (Join-Path $Native "godot-cpp\SConstruct"))) {
	git -C $GameDir submodule update --init native/godot-cpp
}
New-Item -ItemType File -Force -Path (Join-Path $Native "godot-cpp\.gdignore") | Out-Null

foreach ($target in $Targets) {
	$extra = @()
	if ($target -eq "template_release") { $extra += "debug_symbols=yes" }
	scons -C $Native "-j$env:NUMBER_OF_PROCESSORS" platform=windows target=$target arch=x86_64 tests=yes @extra
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	if ($Test) {
		$runner = Join-Path $Native "bin\lampblack_core_tests.windows.$target.x86_64.exe"
		& $runner --reporters=junit "--out=$(Join-Path $Native "bin\doctest.windows.$target.x86_64.xml")"
		& $runner
		if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	}
}
