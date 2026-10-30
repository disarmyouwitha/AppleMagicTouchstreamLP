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
& $PloverConsole -s plover_plugins install --upgrade $wheel.FullName
if($LASTEXITCODE -ne 0) { throw 'Plover plugin installation failed; see the output above.' }
Write-Host 'Installed. Restart Plover; choose Configure > Machine > AppleMagicTouchstream.'
