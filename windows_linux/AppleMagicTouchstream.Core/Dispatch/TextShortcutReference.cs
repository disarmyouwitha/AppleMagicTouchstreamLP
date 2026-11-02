using System.Text;
namespace AppleMagicTouchstream;

// Cross-platform wire identity. The secret itself is never an action, setting,
// dispatch label or capture payload. Host vaults resolve references only live.
public static class TextShortcutReference
{
    public const string Prefix="TEXT_SHORTCUT:";
    public const int MaximumUtf8Bytes=65536;
    public static bool TryRead(string? label,out Guid id)
    { id=default; return label!=null && label.StartsWith(Prefix,StringComparison.Ordinal) && Guid.TryParseExact(label[Prefix.Length..],"D",out id) && id!=Guid.Empty; }
    public static string Label(Guid id)=>Prefix+id.ToString("D").ToUpperInvariant();
    public static bool Valid(string text)=>!string.IsNullOrEmpty(text) && Encoding.UTF8.GetByteCount(text)<=MaximumUtf8Bytes;
}
