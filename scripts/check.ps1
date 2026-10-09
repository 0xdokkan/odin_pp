# Windows counterpart of scripts/check.sh.
# Usage: .\scripts\check.ps1 [-Headless]
param([switch]$Headless)
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
    Invoke-Odin check src -vet -strict-style
    Invoke-Odin check src -vet -strict-style -disable-assert
    Invoke-Odin test src -all-packages '-define:ODIN_TEST_THREADS=1' '-o:none' "-out:$checkDir\tests.exe"
    Invoke-Odin test src -all-packages '-define:ODIN_TEST_THREADS=1' '-o:none' -disable-assert "-out:$checkDir\tests-no-assert.exe"
    # Engine and minigame packages are tested on their own as well: not every
    # one is reachable from the main package.
    foreach ($dir in @(Get-ChildItem src\engine, src\minigames -Directory -ErrorAction SilentlyContinue)) {
        Invoke-Odin test $dir.FullName -vet -strict-style '-o:none' "-out:$checkDir\$($dir.Name)-tests.exe"
    }
    if (-not $Headless) {
        Invoke-Odin build src '-o:none' "-out:$checkDir\odin_pp.exe"
        Invoke-Odin build src '-o:none' -disable-assert "-out:$checkDir\odin_pp-no-assert.exe"
    }
} finally {
    Remove-Item -LiteralPath $checkDir -Recurse -Force -ErrorAction SilentlyContinue
}
