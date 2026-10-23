# Rasterize the existing Mac vector with a black fill; no app/input is opened.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase
$assetDir = Join-Path $PSScriptRoot '../Assets'
[void](New-Item -ItemType Directory -Force -Path $assetDir)
$macSvg = Join-Path $PSScriptRoot '../../../mac/AppleMagicTouchstream/AppleMagicTouchstream/AppleMagicTouchstream/Assets.xcassets/StatusHand.imageset/StatusHand.svg'
# WindowsDiagnostics -> GlassToKey.Windows -> windows_linux -> repository root.
$svgText = [IO.File]::ReadAllText([IO.Path]::GetFullPath($macSvg)).Replace('fill="white"','fill="black"')
[IO.File]::WriteAllText((Join-Path $assetDir 'StatusHand.svg'),$svgText)
[xml]$svg = $svgText
$geometry = [Windows.Media.Geometry]::Parse('F1 ' + $svg.svg.path.d)
$geometry.Freeze()
$sizes = @(16,20,24,32,40,48,64,128,256)
$images = [Collections.Generic.List[byte[]]]::new()
foreach ($size in $sizes) {
    $drawing = [Windows.Media.DrawingVisual]::new()
    $context = $drawing.RenderOpen()
    $scale = $size / 96.0
    $context.PushTransform([Windows.Media.TranslateTransform]::new(($size-86*$scale)/2,0))
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
[IO.File]::WriteAllBytes((Join-Path $assetDir 'GlassToKeyHand.png'),$images[$images.Count-1])
$file = [IO.File]::Create((Join-Path $assetDir 'GlassToKeyHand.ico'))
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
Write-Output "Created black Mac hand assets in $assetDir"
