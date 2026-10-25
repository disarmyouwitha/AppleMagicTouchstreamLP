param(
    [ValidateSet('Open', 'Doctor', 'InspectUsb', 'InspectBluetooth')]
    [string]$Mode = 'Open'
)

$ErrorActionPreference = 'Stop'
$toolsRoot = Join-Path $env:TEMP 'glasstokey-re-tools'
$ghidraRoot = Join-Path $toolsRoot 'ghidra_12.1.4_PUBLIC'
$node = Join-Path $toolsRoot 'node-v24.11.0-win-x64/node.exe'
$rea = Join-Path $toolsRoot 'rea/node_modules/rea-agents/scripts/rea.mjs'
$project = Join-Path $toolsRoot 'projects/AppleTrackpadWindows.gpr'
$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.5.11-hotspot'
$env:GHIDRA_INSTALL_DIR = $ghidraRoot
$env:REA_ANALYSIS_PROVIDER = 'ghidra'
$env:APPDATA = Join-Path $toolsRoot 'appdata'
$env:LOCALAPPDATA = Join-Path $toolsRoot 'localappdata'

if (!(Test-Path -LiteralPath $env:JAVA_HOME)) { throw "JDK 21 missing: $env:JAVA_HOME" }
if (!(Test-Path -LiteralPath $ghidraRoot)) { throw "Ghidra missing: $ghidraRoot" }

if ($Mode -eq 'Open') {
    if (!(Test-Path -LiteralPath $project)) { throw "Ghidra project missing: $project" }
    & (Join-Path $ghidraRoot 'ghidraRun.bat') $project
    exit $LASTEXITCODE
}

if (!(Test-Path -LiteralPath $node) -or !(Test-Path -LiteralPath $rea)) {
    throw "Portable REA runtime missing under $toolsRoot"
}
if ($Mode -eq 'Doctor') {
    & $node $rea doctor --provider ghidra --json
    exit $LASTEXITCODE
}

$package = Join-Path $PSScriptRoot '../../../ApplePrecisionTrackpad_amd64.USB-C'
$driver = if ($Mode -eq 'InspectUsb') {
    Join-Path $package 'ApplePrecisionTrackpadUSB/ApplePrecisionTrackpadUSB.sys'
} else {
    Join-Path $package 'ApplePrecisionTrackpadBluetooth/ApplePrecisionTrackpadBluetooth.sys'
}
if (!(Test-Path -LiteralPath $driver)) { throw "Driver binary missing: $driver" }
& $node $rea inspect $driver --provider ghidra --format json
exit $LASTEXITCODE
