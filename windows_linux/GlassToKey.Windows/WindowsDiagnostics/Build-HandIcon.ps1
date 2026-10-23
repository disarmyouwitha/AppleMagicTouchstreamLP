# Rasterize the existing Mac vector with a black fill; no app/input is opened.
param([switch]$TrayOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase
$assetDir = Join-Path $PSScriptRoot '../Assets'
[void](New-Item -ItemType Directory -Force -Path $assetDir)
if ($TrayOnly) {
    $svgText = [IO.File]::ReadAllText((Join-Path $assetDir 'StatusHand.svg'))
} else {
    $macSvg = Join-Path $PSScriptRoot '../../../mac/AppleMagicTouchstream/AppleMagicTouchstream/AppleMagicTouchstream/Assets.xcassets/StatusHand.imageset/StatusHand.svg'
    $svgText = [IO.File]::ReadAllText([IO.Path]::GetFullPath($macSvg)).Replace('fill="white"','fill="black"')
    [IO.File]::WriteAllText((Join-Path $assetDir 'StatusHand.svg'),$svgText)
}
[xml]$svg = $svgText
$geometry = [Windows.Media.Geometry]::Parse('F1 ' + $svg.svg.path.d)
$geometry.Freeze()
$sizes = @(16,20,24,32,40,48,64,128,256)
function Write-HandIcon([string]$baseName, [bool]$fitBounds) {
$images = [Collections.Generic.List[byte[]]]::new()
foreach ($size in $sizes) {
    $drawing = [Windows.Media.DrawingVisual]::new()
    $context = $drawing.RenderOpen()
    if ($fitBounds) {
        # Use the actual outline bounds, keeping a small antialiasing margin.
        $bounds = $geometry.Bounds
        $scale = ($size * 0.96875) / [Math]::Max($bounds.Width,$bounds.Height)
        $x = ($size-$bounds.Width*$scale)/2-$bounds.X*$scale
        $y = ($size-$bounds.Height*$scale)/2-$bounds.Y*$scale
    } else {
        $scale = $size / 96.0
        $x = ($size-86*$scale)/2
        $y = 0
    }
    $context.PushTransform([Windows.Media.TranslateTransform]::new($x,$y))
    $context.PushTransform([Windows.Media.ScaleTransform]::new($scale,$scale))
    $context.DrawGeometry([Windows.Media.Brushes]::Black,$null,$geometry)
    $context.Close()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new($size,$size,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($drawing)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.MemoryStream]::new()
    $encoder.Save($stream)
    $images.Add($stream.ToArray())
    $stream.Dispose()
}
[IO.File]::WriteAllBytes((Join-Path $assetDir "$baseName.png"),$images[$images.Count-1])
$file = [IO.File]::Create((Join-Path $assetDir "$baseName.ico"))
$writer = [IO.BinaryWriter]::new($file)
try {
    $writer.Write([UInt16]0); $writer.Write([UInt16]1); $writer.Write([UInt16]$sizes.Count)
    $offset = 6+16*$sizes.Count
    for ($i=0; $i -lt $sizes.Count; $i++) {
        $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([UInt16]1); $writer.Write([UInt16]32)
        $writer.Write([UInt32]$images[$i].Length); $writer.Write([UInt32]$offset)
        $offset += $images[$i].Length
    }
    foreach ($bytes in $images) { $writer.Write($bytes) }
} finally { $writer.Dispose() }
}
if (-not $TrayOnly) { Write-HandIcon 'GlassToKeyHand' $false }
Write-HandIcon 'GlassToKeyTrayHand' $true
Write-Output "Created black Mac hand assets in $assetDir"
