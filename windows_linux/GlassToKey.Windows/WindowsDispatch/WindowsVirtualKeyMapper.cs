namespace GlassToKey;

internal static class WindowsVirtualKeyMapper
{
    private static readonly ushort[] SemanticToVirtualKey = BuildSemanticTable();

    public static bool TryMapSemanticCode(DispatchSemanticCode semanticCode, out ushort virtualKey)
    {
        int index = (int)semanticCode;
        if ((uint)index < (uint)SemanticToVirtualKey.Length)
        {
            virtualKey = SemanticToVirtualKey[index];
            return virtualKey != 0;
        }

        virtualKey = 0;
        return false;
    }

    public static bool IsExtendedVirtualKey(ushort virtualKey)
    {
        return virtualKey is
            0x21 or // PageUp
            0x22 or // PageDown
            0x23 or // End
            0x24 or // Home
            0x25 or // Left
            0x26 or // Up
            0x27 or // Right
            0x28 or // Down
            0x2D or // Insert
            0x2E or // Delete
            0x5B or // LeftWin
            0x5C or // RightWin
            0x5D or // Apps
            0xA3 or // RightCtrl
            0xA5;   // RightAlt / AltGr
    }

    private static ushort[] BuildSemanticTable()
    {
        ushort[] table = new ushort[(int)DispatchSemanticCode.BrightnessUp + 1];

        for (int index = 0; index < 26; index++)
        {
            table[(int)DispatchSemanticCode.A + index] = (ushort)(0x41 + index);
        }

        for (int index = 0; index < 10; index++)
        {
            table[(int)DispatchSemanticCode.Digit0 + index] = (ushort)(0x30 + index);
        }

        table[(int)DispatchSemanticCode.Backspace] = 0x08;
        table[(int)DispatchSemanticCode.Tab] = 0x09;
        table[(int)DispatchSemanticCode.Enter] = 0x0D;
        table[(int)DispatchSemanticCode.Escape] = 0x1B;
        table[(int)DispatchSemanticCode.Space] = 0x20;
        table[(int)DispatchSemanticCode.PageUp] = 0x21;
        table[(int)DispatchSemanticCode.PageDown] = 0x22;
        table[(int)DispatchSemanticCode.End] = 0x23;
        table[(int)DispatchSemanticCode.Home] = 0x24;
        table[(int)DispatchSemanticCode.Left] = 0x25;
        table[(int)DispatchSemanticCode.Up] = 0x26;
        table[(int)DispatchSemanticCode.Right] = 0x27;
        table[(int)DispatchSemanticCode.Down] = 0x28;
        table[(int)DispatchSemanticCode.Insert] = 0x2D;
        table[(int)DispatchSemanticCode.Delete] = 0x2E;

        table[(int)DispatchSemanticCode.Shift] = 0x10;
        table[(int)DispatchSemanticCode.LeftShift] = 0xA0;
        table[(int)DispatchSemanticCode.RightShift] = 0xA1;
        table[(int)DispatchSemanticCode.Ctrl] = 0x11;
        table[(int)DispatchSemanticCode.LeftCtrl] = 0xA2;
        table[(int)DispatchSemanticCode.RightCtrl] = 0xA3;
        table[(int)DispatchSemanticCode.Alt] = 0x12;
        table[(int)DispatchSemanticCode.LeftAlt] = 0xA4;
        table[(int)DispatchSemanticCode.RightAlt] = 0xA5;
        table[(int)DispatchSemanticCode.Meta] = 0x5B;
        table[(int)DispatchSemanticCode.LeftMeta] = 0x5B;
        table[(int)DispatchSemanticCode.RightMeta] = 0x5C;

        for (int index = 0; index < 24; index++)
        {
            table[(int)DispatchSemanticCode.F1 + index] = (ushort)(0x70 + index);
        }

        table[(int)DispatchSemanticCode.Semicolon] = 0xBA;
        table[(int)DispatchSemanticCode.Equal] = 0xBB;
        table[(int)DispatchSemanticCode.Comma] = 0xBC;
        table[(int)DispatchSemanticCode.Minus] = 0xBD;
        table[(int)DispatchSemanticCode.Dot] = 0xBE;
        table[(int)DispatchSemanticCode.Slash] = 0xBF;
        table[(int)DispatchSemanticCode.Grave] = 0xC0;
        table[(int)DispatchSemanticCode.LeftBrace] = 0xDB;
        table[(int)DispatchSemanticCode.Backslash] = 0xDC;
        table[(int)DispatchSemanticCode.RightBrace] = 0xDD;
        table[(int)DispatchSemanticCode.Apostrophe] = 0xDE;

        table[(int)DispatchSemanticCode.CapsLock] = 0x14;
        table[(int)DispatchSemanticCode.NumLock] = 0x90;
        table[(int)DispatchSemanticCode.ScrollLock] = 0x91;
        table[(int)DispatchSemanticCode.PrintScreen] = 0x2C;
        table[(int)DispatchSemanticCode.Pause] = 0x13;
        table[(int)DispatchSemanticCode.Menu] = 0x5D;

        table[(int)DispatchSemanticCode.VolumeMute] = 0xAD;
        table[(int)DispatchSemanticCode.VolumeDown] = 0xAE;
        table[(int)DispatchSemanticCode.VolumeUp] = 0xAF;
        table[(int)DispatchSemanticCode.MediaNextTrack] = 0xB0;
        table[(int)DispatchSemanticCode.MediaPreviousTrack] = 0xB1;
        table[(int)DispatchSemanticCode.MediaStop] = 0xB2;
        table[(int)DispatchSemanticCode.MediaPlayPause] = 0xB3;

        table[(int)DispatchSemanticCode.BrightnessDown] = DispatchKeyResolver.VirtualKeyBrightnessDown;
        table[(int)DispatchSemanticCode.BrightnessUp] = DispatchKeyResolver.VirtualKeyBrightnessUp;

        return table;
    }
}
