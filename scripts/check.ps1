# Windows counterpart of scripts/check.sh.
# Usage: .\scripts\check.ps1 [-Quick] [-Headless]
param([switch]$Quick, [switch]$Headless)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Join-Path $PSScriptRoot '..')

$odin = if ($env:ODIN) { $env:ODIN } else { 'odin' }
$checkDir = Join-Path ([IO.Path]::GetTempPath()) ("odin_pp-check-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $checkDir | Out-Null

function Invoke-Odin {
    & $odin @args
    if ($LASTEXITCODE -ne 0) { throw "odin $($args -join ' ') failed with exit code $LASTEXITCODE" }
}

try {
    Invoke-Odin version
    $fullTests = if ($Quick) { 'false' } else { 'true' }
    Write-Host ("Test profile: " + $(if ($Quick) { 'quick' } else { 'full' }))
    Invoke-Odin check src -vet -strict-style "-define:ODIN_TEST_FULL=$fullTests"
    Invoke-Odin test src -all-packages '-define:ODIN_TEST_THREADS=1' "-define:ODIN_TEST_FULL=$fullTests" '-o:none' "-out:$checkDir\tests.exe"
    if (-not $Quick) {
        Invoke-Odin check src -vet -strict-style -disable-assert
        Invoke-Odin test src -all-packages '-define:ODIN_TEST_THREADS=1' '-define:ODIN_TEST_FULL=true' '-o:none' -disable-assert "-out:$checkDir\tests-no-assert.exe"
    }
    # All registered engine and minigame packages are reachable from src.
    # Full checks repeat the suite with asserts disabled.
    if (-not $Headless) {
        Invoke-Odin build src '-o:none' "-out:$checkDir\odin_pp.exe"
        if (-not $Quick) {
            Invoke-Odin build src '-o:none' -disable-assert "-out:$checkDir\odin_pp-no-assert.exe"
        }
    }
} finally {
    Remove-Item -LiteralPath $checkDir -Recurse -Force -ErrorAction SilentlyContinue
}
