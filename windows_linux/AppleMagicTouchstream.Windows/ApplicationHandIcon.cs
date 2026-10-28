using System.Drawing;
using System.IO;
using System.Windows.Media.Imaging;

namespace AppleMagicTouchstream;

internal static class ApplicationHandIcon
{
    private static Stream Open(string file = "AppleMagicTouchstreamHand.ico") => typeof(ApplicationHandIcon).Assembly.GetManifestResourceStream("AppleMagicTouchstream.Assets." + file)
        ?? throw new InvalidOperationException("Application hand icon is missing.");
    public static Icon CreateTrayIcon()
    {
        using var stream = Open("AppleMagicTouchstreamTrayHand.ico");
        using var icon = new Icon(stream, new Size(32,32));
        return (Icon)icon.Clone();
    }
    public static BitmapSource CreateImage()
    {
        using var stream = Open();
        var decoder = BitmapDecoder.Create(stream,BitmapCreateOptions.PreservePixelFormat,BitmapCacheOption.OnLoad);
        var image = decoder.Frames.OrderBy(frame=>Math.Abs(frame.PixelWidth-32)).First();
        image.Freeze();
        return image;
    }
}
