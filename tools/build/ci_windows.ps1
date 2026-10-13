# FND-04, per push on a Windows runner: the doctest runners of both targets (built by the Linux
# job's MinGW cross-compile, FND-02) to JUnit, then the import pass and GUT over tests/unit and
# tests/scenario with the Windows editor. The engine binary comes from $env:GODOT.
# Usage: tools/build/ci_windows.ps1 [-Only doctest|gut]
param([string]$Only = "")
$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Bin = Join-Path $GameDir "native\bin"
$Reports = Join-Path $GameDir "tests\reports"
New-Item -ItemType Directory -Force -Path $Reports | Out-Null
$Status = 0

if ($Only -ne "gut") {
	foreach ($target in @("template_debug", "template_release")) {
		$runner = Join-Path $Bin "lampblack_core_tests.windows.$target.x86_64.exe"
		& $runner --reporters=junit "--out=$(Join-Path $Reports "doctest.windows.$target.xml")"
		if ($LASTEXITCODE -ne 0) { $Status = 1 }
		& $runner
		Write-Output "doctest windows $target exit $LASTEXITCODE"
		if ($LASTEXITCODE -ne 0) { $Status = 1 }
	}
}

if ($Only -ne "doctest") {
	& (Join-Path $PSScriptRoot "run_unit_tests.ps1") -JUnit (Join-Path $Reports "unit.windows.xml") *>&1 |
		Tee-Object -FilePath (Join-Path $Reports "gut.windows.log") |
		Select-String -Pattern "^Tests|Passing Tests|Failing Tests|Risky|\[Failed\]|sample final"
	$log = Get-Content (Join-Path $Reports "gut.windows.log") -Raw
	if ($log -match "Failing Tests" -or $log -notmatch "Passing Tests") { $Status = 1 }
}
exit $Status
