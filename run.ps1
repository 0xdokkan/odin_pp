# Development startup for Windows: same contract as run.sh.
# Usage: .\run.ps1 [game arguments], e.g. .\run.ps1 --seed=0xC0FFEE --fast
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$odin = if ($env:ODIN) { $env:ODIN } else { 'odin' }
& $odin run src -o:none -- @args
exit $LASTEXITCODE
