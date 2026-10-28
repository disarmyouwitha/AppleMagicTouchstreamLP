# Reproduce the Mac's traced geometry without mirroring either side.
$sourcePath = Join-Path $PSScriptRoot '../../../mac/AppleMagicTouchstream/AppleMagicTouchstream/AppleMagicTouchstream/TrackpadLayoutPreset.swift'
$source = Get-Content -LiteralPath $sourcePath -Raw
$builder = [System.Text.StringBuilder]::new()
[void]$builder.AppendLine('// Traced geometry copied from the Mac gold standard. Regenerate with AppleMagicTouchstream.Core/Tools/Sync-TouchStreamGeometry.ps1.')
[void]$builder.AppendLine('namespace AppleMagicTouchstream;')
[void]$builder.AppendLine('public static class TouchStreamLayoutDefinition {')
[void]$builder.AppendLine('public readonly record struct Key(string Label, NormalizedRect Rect);')
foreach ($side in @('left','right')) {
    $section = [regex]::Match($source, ('static let '+$side+': \[\[Key\]\] = \[(.*?)\n    \]'), 'Singleline').Groups[1].Value
    if (-not $section) { throw "Missing $side geometry" }
    [void]$builder.AppendLine(('public static readonly Key[][] '+$side+' = ['))
    foreach ($row in ($section -split '\r?\n' | Where-Object { $_ -match 'Key\(' })) {
        [void]$builder.AppendLine('[')
        foreach ($key in [regex]::Matches($row, 'Key\(("(?:\\.|[^"\\])*"),([\d.,-]+)\)')) {
            $numbers = $key.Groups[2].Value.Split(',')
            if ($numbers.Count -ne 5) { throw 'Invalid traced key' }
            [void]$builder.AppendLine(('new('+ $key.Groups[1].Value + ',new('+ $numbers[0] + '/260.0,'+ $numbers[1] + '/196.0,'+ $numbers[2] + '/260.0,'+ $numbers[3] + '/196.0) { RotationDegrees='+ $numbers[4] +' }),'))
        }
        [void]$builder.AppendLine('],')
    }
    [void]$builder.AppendLine('];')
}
[void]$builder.AppendLine('public static string[][] Labels(bool mirrored) => (mirrored ? left : right).Select(row=>row.Select(key=>key.Label).ToArray()).ToArray();')
[void]$builder.AppendLine('public static KeyLayout Build(bool mirrored, KeymapStore? keymap) { var keys=mirrored ? left : right; var side=mirrored ? TrackpadSide.Left : TrackpadSide.Right; return new(keys.Select((row,r)=>row.Select((key,c)=>LayoutBuilder.ApplyKeyGeometryOverride(key.Rect,keymap?.ResolveKeyGeometry(GridKeyPosition.StorageKey(side,r,c)) ?? new())).ToArray()).ToArray(),Labels(mirrored)); }')
[void]$builder.AppendLine('}')
Set-Content -LiteralPath (Join-Path $PSScriptRoot '../Layout/TouchStreamLayoutDefinition.cs') -Value $builder.ToString() -Encoding utf8 -NoNewline
