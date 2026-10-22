param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
# PnP property reads only. Never enables/disables devices or changes bindings.
$keys = @(
    'DEVPKEY_Device_Parent', 'DEVPKEY_Device_Children', 'DEVPKEY_Device_Service',
    'DEVPKEY_Device_DriverInfPath', 'DEVPKEY_Device_DriverVersion',
    'DEVPKEY_Device_DriverProvider', 'DEVPKEY_Device_UpperFilters',
    'DEVPKEY_Device_LowerFilters', 'DEVPKEY_Device_HardwareIds',
    'DEVPKEY_Device_CompatibleIds', 'DEVPKEY_Device_ContainerId'
)
$rows = @(Get-PnpDevice -PresentOnly | Where-Object {
    $_.InstanceId -match 'PID[&_](0324|0265)'
} | ForEach-Object {
    $properties = @{}
    Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName $keys | ForEach-Object {
        $properties[$_.KeyName] = @{ Type = [string]$_.Type; Data = $_.Data }
    }
    [ordered]@{ InstanceId = $_.InstanceId; Class = $_.Class; Name = $_.FriendlyName; Status = [string]$_.Status; Properties = $properties }
})
$json = ConvertTo-Json -InputObject $rows -Depth 8
if ($OutputPath) { [System.IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath), $json) }
$json
