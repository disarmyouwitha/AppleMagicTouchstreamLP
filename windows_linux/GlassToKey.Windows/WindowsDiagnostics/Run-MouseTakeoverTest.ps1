param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
$output = Join-Path $appRoot 'bin/MouseTakeoverTestV2'
if (-not $SkipBuild) {
    & dotnet build (Join-Path $appRoot 'GlassToKey.Windows.csproj') -c Release -o $output --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Test build failed; takeover was not started.' }
}
$exe = Join-Path $output 'GlassToKey.Windows.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Test executable missing. Run without -SkipBuild first.' }
$log = Join-Path (Split-Path -Parent $appRoot) ('mouse-takeover-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
Write-Host 'Opening an UNCHECKED Mouse Takeover test window. No settings are saved.'
Write-Host 'Click 30sec test when ready. Release: Ctrl+Alt+F10 (or fallback shown in window), or Escape.'
Write-Host "Log: $log"
$info = New-Object System.Diagnostics.ProcessStartInfo
$info.FileName = $exe
$info.UseShellExecute = $false
$info.Arguments = '--mouse-takeover-test "' + $log + '"'
# This is the visible interactive test window requested by the user.
$process = [System.Diagnostics.Process]::Start($info)
if ($null -eq $process) { throw 'Test window did not start.' }
