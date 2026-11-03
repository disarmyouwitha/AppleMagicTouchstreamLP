namespace AppleMagicTouchstream;

internal static class MouseTakeoverReleaseShortcut
{
    // Keep the established shortcut when free; use function keys on collision.
    // F12 is reserved by Windows for debuggers.
    internal static uint Select(Func<uint,bool> tryRegister)
    {
        foreach (uint key in new uint[] { 0x52, 0x79, 0x78, 0x77 })
            if (tryRegister(key)) return key;
        return 0;
    }

    internal static string Label(uint key) => key==0 ? "Unavailable"
        : key==0x52 ? "Ctrl+Alt+R" : "Ctrl+Alt+F"+(key-0x70+1);
}
