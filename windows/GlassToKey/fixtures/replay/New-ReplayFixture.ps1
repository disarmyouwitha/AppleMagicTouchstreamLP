param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CapturePath,

    [Parameter(Position = 1)]
    [string]$FixturePath,

    [string]$ProjectPath,

    [switch]$RelativeCapturePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ExistingPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    return (Resolve-Path -LiteralPath $PathValue).Path
}

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri([System.IO.Path]::GetFullPath($TargetPath))
    $relative = $baseUri.MakeRelativeUri($targetUri).ToString()
    return [System.Uri]::UnescapeDataString($relative).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Join-Path $scriptDir "..\..\GlassToKey.csproj"
}
$projectFull = Resolve-ExistingPath -PathValue $ProjectPath
$captureFull = Resolve-ExistingPath -PathValue $CapturePath

if ([string]::IsNullOrWhiteSpace($FixturePath)) {
    $captureDir = Split-Path -Parent $captureFull
    $captureBase = [System.IO.Path]::GetFileNameWithoutExtension($captureFull)
    $FixturePath = Join-Path $captureDir ("{0}.fixture.json" -f $captureBase)
}

$fixtureFull = [System.IO.Path]::GetFullPath($FixturePath)
$fixtureDir = Split-Path -Parent $fixtureFull
if (![string]::IsNullOrWhiteSpace($fixtureDir)) {
    New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("g2k-fixture-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$metricsPath = Join-Path $tempRoot "metrics.json"

try {
    $replayOutput = & dotnet run --project $projectFull -c Release -- --replay $captureFull --metrics-out $metricsPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("Replay command failed with exit code {0}:`n{1}" -f $LASTEXITCODE, ($replayOutput -join [Environment]::NewLine))
    }

    $summaryLine = $replayOutput |
        Where-Object { $_ -is [string] -and $_ -like "Replay '*" } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($summaryLine)) {
        throw ("Could not find replay summary line in output:`n{0}" -f ($replayOutput -join [Environment]::NewLine))
    }

    $summaryPattern = "fingerprint=(0x[0-9A-F]+), .*intentTrace=(0x[0-9A-F]+), intentTransitions=([0-9]+), dispatchTrace=(0x[0-9A-F]+), dispatchEvents=([0-9]+), dispatchEnqueued=([0-9]+), suppressed=([0-9]+), ringFull=([0-9]+), modifierUnbalanced=([0-9]+), repeats=([0-9]+)/([0-9]+),"
    $match = [System.Text.RegularExpressions.Regex]::Match($summaryLine, $summaryPattern)
    if (!$match.Success) {
        throw ("Could not parse replay summary:`n{0}" -f $summaryLine)
    }

    $metricsJson = Get-Content -Raw -LiteralPath $metricsPath | ConvertFrom-Json

    $capturePathForFixture = if ($RelativeCapturePath) {
        Get-RelativePathCompat -BasePath $fixtureDir -TargetPath $captureFull
    }
    else {
        $captureFull
    }

    $fixtureObject = [ordered]@{
        capturePath = $capturePathForFixture
        expected    = [ordered]@{
            fingerprint                     = $match.Groups[1].Value
            intentFingerprint               = $match.Groups[2].Value
            intentTransitions               = [int]$match.Groups[3].Value
            dispatchFingerprint             = $match.Groups[4].Value
            dispatchEvents                  = [int]$match.Groups[5].Value
            dispatchEnqueued                = [long]$match.Groups[6].Value
            dispatchSuppressedTypingDisabled = [long]$match.Groups[7].Value
            dispatchSuppressedRingFull      = [long]$match.Groups[8].Value
            modifierUnbalanced              = [int]$match.Groups[9].Value
            repeatStarts                    = [int]$match.Groups[10].Value
            repeatCancels                   = [int]$match.Groups[11].Value
            framesSeen                      = [long]$metricsJson.framesSeen
            framesParsed                    = [long]$metricsJson.framesParsed
            framesDispatched                = [long]$metricsJson.framesDispatched
            framesDropped                   = [long]$metricsJson.framesDropped
        }
    }

    $fixtureJson = $fixtureObject | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $fixtureFull -Value $fixtureJson -Encoding UTF8
    Write-Host ("Wrote fixture: {0}" -f $fixtureFull)
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
