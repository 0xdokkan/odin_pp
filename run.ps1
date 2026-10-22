# Same contract as run.sh: optional --release before the game arguments.
# Usage: .\run.ps1 --release --expedition
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$odin = if ($env:ODIN) { $env:ODIN } else { 'odin' }
New-Item -ItemType Directory -Path 'build' -Force | Out-Null
$optimization = 'none'
$gameArgs = @($args)
if ($gameArgs.Count -gt 0 -and $gameArgs[0] -eq '--release') {
    $optimization = 'speed'
    $gameArgs = @($gameArgs | Select-Object -Skip 1)
}
& $odin run src "-o:$optimization" '-out:build/odin_pp.exe' -- @gameArgs
exit $LASTEXITCODE
