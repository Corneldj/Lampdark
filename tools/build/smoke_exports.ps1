# Runs the exported Windows QA builds with --exit-after-ticks and expects exit code 0 (FND-03).
# Usage: tools/build/smoke_exports.ps1 [-Build <dir>]
param([string]$Build = "")
$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($Build -eq "") { $Build = Join-Path $GameDir "build" }
$Ticks = 40
$Status = 0

function Invoke-Smoke([string]$Name, [string]$Exe, [string[]]$Extra) {
	$out = & $Exe @Extra --exit-after-ticks $Ticks 2>&1 | Out-String
	if ($LASTEXITCODE -eq 0 -and $out -match "exit after $Ticks ticks") {
		Write-Output "ok   $Name"
	} else {
		Write-Output "FAIL $Name (exit $LASTEXITCODE)"
		Write-Output $out
		$script:Status = 1
	}
}

Invoke-Smoke "windows-server-qa" (Join-Path $Build "windows-server-qa\lampblack_server.exe") @()
Invoke-Smoke "windows-client-qa" (Join-Path $Build "windows-client-qa\lampblack.console.exe") @("--headless")
exit $Status
