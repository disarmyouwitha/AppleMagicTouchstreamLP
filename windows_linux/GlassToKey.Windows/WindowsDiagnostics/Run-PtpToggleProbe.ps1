param(
    [switch]$ObserveOnly,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
$executable = Join-Path $appRoot 'bin/Release/net10.0-windows/GlassToKey.Windows.exe'
if (!(Test-Path -LiteralPath $executable)) {
    throw "Build first: dotnet build `"$(Join-Path $appRoot 'GlassToKey.Windows.csproj')`" -c Release"
}
$mode = if ($ObserveOnly) { 'observe' } else { 'toggle' }
$logPath = Join-Path (Split-Path -Parent $appRoot) ('ptp-{0}-{1}.log' -f $mode, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
Write-Host "Mode: $mode. Log: $logPath"
if ($ObserveOnly) {
    Write-Host 'Records input for 25 seconds without changing touchpad state.'
} else {
    Write-Host 'This test temporarily disables all Windows Precision Touchpads for 10 seconds.'
    Write-Host 'After starting, touch the Magic Trackpad before second 5 and keep a finger moving on it.'
    Write-Host 'While disabled, also try scrolling and a three/four-finger Windows gesture.'
    Write-Host 'Escape restores early. The test ends at 25 seconds; a separate watchdog also restores input.'
}
if (!$NoPrompt) { [void](Read-Host 'Press Enter when ready') }

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $executable
$startInfo.WorkingDirectory = $appRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$startInfo.RedirectStandardError = $true
$startInfo.RedirectStandardOutput = $true
$toggleArgument = if ($ObserveOnly) { '' } else { '--ptp-os-toggle-probe ' }
$startInfo.Arguments = $toggleArgument + '--ptp-diagnostic "' + $logPath + '"'
$probe = New-Object System.Diagnostics.Process
$probe.StartInfo = $startInfo
$started = $false
$reported = @{}
$events = @()
$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
try {
    if (!$probe.Start()) { throw 'Diagnostic process failed to start.' }
    $started = $true
    $stderr = $probe.StandardError.ReadToEndAsync()
    $stdout = $probe.StandardOutput.ReadToEndAsync()
    do {
        if (Test-Path -LiteralPath $logPath) {
            $stream = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = New-Object System.IO.StreamReader($stream)
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $events = @($text -split '\r?\n' | Where-Object { $_ -match '^(START |STARTUP_FAULT|FAULT|PTP_STATUS|WATCHDOG |OS_|SYNTHETIC_MOVE|RELEASE|ACTIVE_CONTACT_FRAME_COUNT|END )' })
            foreach ($eventLine in $events) {
                if (!$reported.ContainsKey($eventLine)) {
                    Write-Host $eventLine
                    $reported[$eventLine] = $true
                }
            }
            if (!$ObserveOnly -and ($events -match '^START .*osToggle=False')) {
                throw 'The executable did not enable the requested toggle mode. The run is invalid; rebuild the app.'
            }
        }
        if ($probe.HasExited) { break }
        if ($elapsed.Elapsed.TotalSeconds -gt 40) {
            throw 'Diagnostic exceeded its deadline. Stopping it; its independent watchdog handles restoration.'
        }
        $seconds = [int]$elapsed.Elapsed.TotalSeconds
        Write-Progress -Activity "Magic Trackpad $mode diagnostic" -Status "$seconds seconds elapsed; Escape releases early" -PercentComplete ([Math]::Min(99, $seconds * 4))
        Start-Sleep -Milliseconds 250
    } while ($true)
    $probe.WaitForExit()
    $errorText = $stderr.GetAwaiter().GetResult()
    $outputText = $stdout.GetAwaiter().GetResult()
    if ($outputText) { Write-Host $outputText }
    if ($errorText) { Write-Host $errorText -ForegroundColor Red }
    if ($probe.ExitCode -ne 0) { throw "Diagnostic failed with exit code $($probe.ExitCode). See $logPath" }
    if (!($events -match '^START ') -or !($events -match '^END ')) { throw "Diagnostic did not record a complete run. See $logPath" }
    if ($events -match '^(STARTUP_FAULT|FAULT)') { throw "Diagnostic reported an error. See $logPath" }
    if (!$ObserveOnly -and !($events -match '^OS_TOGGLE_OFF ')) {
        Write-Warning 'No suppression interval occurred. Keep a finger moving on the Magic Trackpad during seconds 5-12 on the next run.'
    }
    Write-Host "Finished. Log saved: $logPath"
    if (!$ObserveOnly) { Write-Host 'Note whether native movement, scrolling, clicking, and Windows gestures worked during the disabled interval.' }
} finally {
    Write-Progress -Activity "Magic Trackpad $mode diagnostic" -Completed
    if ($started -and !$probe.HasExited) { $probe.Kill() }
    $probe.Dispose()
}
