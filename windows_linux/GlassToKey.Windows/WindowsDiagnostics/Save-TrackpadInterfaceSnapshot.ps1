param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
# Read-only inventory. No device state, driver binding, feature report, or input-setting writes.
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PWD ('trackpad-interfaces-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}
New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
Write-Host "Read-only trackpad inventory: $OutputDirectory"
& (Join-Path $PSScriptRoot 'Read-RawInputMetadata.ps1') -OutputPath (Join-Path $OutputDirectory 'raw-input-metadata.json') | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $OutputDirectory 'raw-input-metadata.json'))) {
    throw "Raw Input query failed. Partial results: $OutputDirectory"
}
& (Join-Path $PSScriptRoot 'Read-TrackpadPnpTopology.ps1') -OutputPath (Join-Path $OutputDirectory 'pnp-topology.json') | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $OutputDirectory 'pnp-topology.json'))) {
    throw "PnP query failed. Partial results: $OutputDirectory"
}
$rows = @(Get-Content -LiteralPath (Join-Path $OutputDirectory 'pnp-topology.json') -Raw | ConvertFrom-Json)
$index = 0
foreach ($row in $rows) {
    $index++
    $result = & pnputil.exe /enum-devices /instanceid $row.InstanceId /interfaces /stack /services /relations 2>&1
    $exitCode = $LASTEXITCODE
    $result | Out-File -LiteralPath (Join-Path $OutputDirectory ("device-{0:D2}-interfaces.txt" -f $index)) -Encoding utf8
    if ($exitCode -ne 0) { throw "PnP interface query failed for $($row.InstanceId), exit $exitCode. Partial results: $OutputDirectory" }
}
Write-Host "Saved $($rows.Count) device records and their registered interface/stack information."
Write-Host 'This inventories exposed interfaces; it does not prove that any interface delivers original contact packets.'
