param([string]$PloverConsole)
$ErrorActionPreference='Stop'
$wheel=Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'dist') -Filter '*.whl' | Select-Object -First 1
if(-not $wheel) { throw 'The bundled plugin wheel is missing.' }
if(-not $PloverConsole) {
    $roots=@("${env:ProgramFiles}\Open Steno Project","${env:ProgramFiles(x86)}\Open Steno Project","$env:LOCALAPPDATA\Programs\Plover")
    $candidates=@(foreach($root in $roots) { if(Test-Path -LiteralPath $root) { Get-ChildItem -LiteralPath $root -Filter plover_console.exe -Recurse -ErrorAction SilentlyContinue } })
    if($candidates.Count -eq 1) { $PloverConsole=$candidates[0].FullName }
    else {
        Add-Type -AssemblyName System.Windows.Forms
        $picker=[System.Windows.Forms.OpenFileDialog]::new()
        $picker.Title='Select plover_console.exe in your Plover installation'
        $picker.Filter='Plover console|plover_console.exe'
        if($picker.ShowDialog() -ne 'OK') { exit 1 }
        $PloverConsole=$picker.FileName
    }
}
if(-not (Test-Path -LiteralPath $PloverConsole -PathType Leaf)) { throw 'Plover console executable not found.' }
Write-Host 'Installing into Plover only. Close Plover first, then restart it after installation.'
$ploverRoot=Split-Path -Parent (Resolve-Path -LiteralPath $PloverConsole).Path
$bundledPython=Join-Path $ploverRoot 'data/python.exe'
if(Test-Path -LiteralPath $bundledPython) {
    # The distributed Windows launcher spawns a detached child. Invoke its
    # bundled interpreter directly so failures and completion are observable.
    $pluginBase=& $bundledPython -B -c 'import os; from plover.oslayer.config import CONFIG_DIR, PLUGINS_PLATFORM; print(os.path.join(CONFIG_DIR,"plugins",PLUGINS_PLATFORM))'
    if($LASTEXITCODE -ne 0 -or -not $pluginBase) { throw 'Could not locate Plover user plugins.' }
    $previousUserBase=$env:PYTHONUSERBASE
    try {
        $env:PYTHONUSERBASE=$pluginBase.Trim()
        & $bundledPython -B -m plover.scripts.main -s plover_plugins install --no-index --no-deps --upgrade $wheel.FullName
        if($LASTEXITCODE -ne 0) { throw 'Plover plugin installation failed; see the output above.' }
    } finally { $env:PYTHONUSERBASE=$previousUserBase }
} else {
    Push-Location -LiteralPath $ploverRoot
    try {
        & $PloverConsole -s plover_plugins install --no-index --no-deps --upgrade $wheel.FullName
        if($LASTEXITCODE -ne 0) { throw 'Plover plugin installation failed; see the output above.' }
    } finally { Pop-Location }
}
Write-Host 'Installed. Restart Plover; choose Configure > Machine > AppleMagicTouchstream.'
