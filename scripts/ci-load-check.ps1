# Copyright 2026, The DisplayXR Project
# SPDX-License-Identifier: BSL-1.0
#
# Windows twin of ci-load-check.sh: load the COMPILE-CHECK build of the provider
# through the pinned runtime's own loader, with displayxr-cli built from the
# same runtime tree.
#
#   ci-load-check.ps1 -Build <build dir> [-Config Release]
#
# It lays the binaries out the way an INSTALLED machine has them - the runtime
# (displayxr-cli.exe, DisplayXRClient.dll, the sim display plug-in) in one tree,
# the provider in a SEPARATE directory, as this repository's installer puts it
# under Plugins\Ultraleap\ - registers both in HKLM, allowlists the unsigned
# DLLs (the provenance gate enforces on Windows), runs `selftest` twice, and
# removes every row it wrote.
#
#   1. no LeapC anywhere      -> "Ultraleap tracking software NOT FOUND": the
#                                provider must load, report ABSENT, selftest passes
#   2. LEAPC_PATH = stand-in  -> the run-time loader binds LeapC.dll by absolute path
#
# Needs an elevated shell (CI runners are). Proves load / negotiate / bind only.
param(
    [Parameter(Mandatory = $true)][string]$Build,
    [string]$Config = "Release"
)
$ErrorActionPreference = "Stop"
$Build = (Resolve-Path $Build).Path

function Find-One([string]$name) {
    $f = Get-ChildItem -Path $Build -Recurse -Filter $name -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch 'CMakeFiles' -and $_.FullName -notmatch 'vcpkg_installed' } |
        Sort-Object { $_.FullName -notmatch "\\$Config\\" } | Select-Object -First 1
    if (-not $f) { throw "build product not found: $name" }
    return $f
}

$cli  = Find-One "displayxr-cli.exe"
$core = Find-One "DisplayXRClient.dll"
$sim  = Find-One "DisplayXR-SimDisplay.dll"
$prov = Find-One "DisplayXR-Ultraleap-STUBCHECK.dll"
$stub = Find-One "LeapC.dll"

$stage = Join-Path $env:RUNNER_TEMP "ul-load-check"
if (-not $env:RUNNER_TEMP) { $stage = Join-Path $env:TEMP "ul-load-check" }
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
$rtBin = Join-Path $stage "Runtime"
$rtPlugins = Join-Path $rtBin "plugins"
$ulDir = Join-Path $stage "Plugins\Ultraleap"
$leapDir = Join-Path $stage "FakeUltraleap"
New-Item -ItemType Directory -Force -Path $rtBin, $rtPlugins, $ulDir, $leapDir | Out-Null

# The runtime tree: the CLI, the core DLL, and every DLL built next to either
# (vcpkg's app-local dependencies).
foreach ($d in @($cli.Directory, $core.Directory)) {
    Copy-Item -Path (Join-Path $d.FullName "*.dll") -Destination $rtBin -Force -ErrorAction SilentlyContinue
}
Copy-Item $cli.FullName $rtBin -Force
Copy-Item $sim.FullName $rtPlugins -Force
# The provider, alone in its own directory. No LeapC.dll beside it, ever.
Copy-Item $prov.FullName $ulDir -Force
# The stand-in LeapC, somewhere else entirely - reachable only via LEAPC_PATH.
Copy-Item $stub.FullName $leapDir -Force

$cliExe = Join-Path $rtBin "displayxr-cli.exe"
$simDll = Join-Path $rtPlugins "DisplayXR-SimDisplay.dll"
$ulDll  = Join-Path $ulDir "DisplayXR-Ultraleap-STUBCHECK.dll"

$dpKey = "HKLM\Software\DisplayXR\DisplayProcessors\sim-display"
$ipKey = "HKLM\Software\DisplayXR\InputProviders\ultraleap"
$allowRoot = "HKLM\Software\DisplayXR\Trust\Allowlist"
$allowed = @()

function Run-Selftest([string]$label, [string]$leapcPath) {
    $logDir = Join-Path $env:LOCALAPPDATA "DisplayXR"
    $before = Get-Date
    if ($leapcPath) { $env:DXR_INPUT_ULTRALEAP_LEAPC_PATH = $leapcPath } else { Remove-Item Env:DXR_INPUT_ULTRALEAP_LEAPC_PATH -ErrorAction SilentlyContinue }
    # A native command's stderr must not become a terminating error here.
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & $cliExe selftest 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    # U_LOG lines may go to the per-process log file rather than the console.
    $logs = ""
    if (Test-Path $logDir) {
        Get-ChildItem $logDir -Filter "DisplayXR_displayxr-cli*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $before.AddSeconds(-2) } |
            ForEach-Object { $logs += (Get-Content $_.FullName -Raw) }
    }
    $all = $out + "`n" + $logs
    Write-Host "== $label (exit $code)"
    ($all -split "`n") | Where-Object { $_ -match 'ultraleap|input_providers|SELF-TEST|LeapC' } | ForEach-Object { Write-Host ("   " + $_.Trim()) }
    if ($code -ne 0) { Write-Host $all; throw "$label : selftest exit code $code" }
    return $all
}
function Want([string]$text, [string]$pattern, [string]$label) {
    if ($text -notmatch [regex]::Escape($pattern)) { Write-Host $text; throw "$label : expected '$pattern'" }
}

try {
    reg add $dpKey /v Binary /t REG_SZ /d "$simDll" /f | Out-Null
    reg add $dpKey /v ProbeOrder /t REG_DWORD /d 200 /f | Out-Null
    reg add $dpKey /v DisplayName /t REG_SZ /d "Simulated 3D Display" /f | Out-Null
    reg add $ipKey /v Binary /t REG_SZ /d "$ulDll" /f | Out-Null
    reg add $ipKey /v ProbeOrder /t REG_DWORD /d 50 /f | Out-Null
    reg add $ipKey /v DisplayName /t REG_SZ /d "Ultraleap (LeapC STUB CHECK - not a real provider)" /f | Out-Null
    foreach ($dll in @($simDll, $ulDll)) {
        $h = (Get-FileHash -Path $dll -Algorithm SHA256).Hash.ToLower()
        reg add $allowRoot /v $h /t REG_SZ /d "ci $(Split-Path $dll -Leaf)" /f | Out-Null
        $allowed += $h
    }

    Write-Host "== input list"
    & $cliExe input list
    if ($LASTEXITCODE -ne 0) { throw "input list failed" }

    $a = Run-Selftest "selftest, no LeapC (tracking software not found)" ""
    Want $a "provider 'ultraleap' loaded but its hardware is absent" "no LeapC"
    Want $a "SELF-TEST PASSED" "no LeapC"
    if ($a -match 'ultraleap:') { Want $a "Ultraleap tracking software NOT FOUND" "no LeapC" }

    $b = Run-Selftest "selftest, stand-in LeapC bound at run time" $leapDir
    Want $b "SELF-TEST PASSED" "stand-in"
    if ($b -match 'ultraleap:') { Want $b "LeapC loaded from" "stand-in" }
    else { Write-Host "::warning::the provider's own log lines were not captured on this host; only the selftest verdict was checked." }

    Write-Host "load check OK (stand-in LeapC only - no tracking was exercised)"
}
finally {
    Remove-Item Env:DXR_INPUT_ULTRALEAP_LEAPC_PATH -ErrorAction SilentlyContinue
    reg delete $dpKey /f 2>$null | Out-Null
    reg delete $ipKey /f 2>$null | Out-Null
    foreach ($h in $allowed) { reg delete $allowRoot /v $h /f 2>$null | Out-Null }
}
