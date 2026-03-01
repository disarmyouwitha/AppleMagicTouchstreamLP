namespace GlassToKey.Platform.Linux.Uinput;

internal static class LinuxKeyCodeMapper
{
    private const ushort VirtualKeyBrightnessDown = 0x0101;
    private const ushort VirtualKeyBrightnessUp = 0x0102;
    private static readonly ushort[] VirtualKeyToEvdev = BuildVirtualKeyTable();
    private static readonly ushort[] SemanticToEvdev = BuildSemanticTable();

    public static bool TryMapKey(ushort virtualKey, out ushort keyCode)
    {
        if (virtualKey == VirtualKeyBrightnessDown)
        {
            keyCode = LinuxEvdevCodes.KeyBrightnessDown;
            return true;
        }

        if (virtualKey == VirtualKeyBrightnessUp)
        {
            keyCode = LinuxEvdevCodes.KeyBrightnessUp;
            return true;
        }

        if (virtualKey < VirtualKeyToEvdev.Length)
        {
            keyCode = VirtualKeyToEvdev[virtualKey];
            return keyCode != 0;
        }

        keyCode = 0;
        return false;
    }

    public static bool TryMapMouseButton(DispatchMouseButton button, out ushort buttonCode)
    {
        buttonCode = button switch
        {
            DispatchMouseButton.Left => LinuxEvdevCodes.ButtonLeft,
            DispatchMouseButton.Right => LinuxEvdevCodes.ButtonRight,
            DispatchMouseButton.Middle => LinuxEvdevCodes.ButtonMiddle,
            _ => 0
        };

        return buttonCode != 0;
    }

    public static bool TryMapSemanticCode(DispatchSemanticCode semanticCode, out ushort keyCode)
    {
        int index = (int)semanticCode;
        if ((uint)index < (uint)SemanticToEvdev.Length)
        {
            keyCode = SemanticToEvdev[index];
            return keyCode != 0;
        }

        keyCode = 0;
        return false;
    }

    private static ushort[] BuildSemanticTable()
    {
        ushort[] table = new ushort[(int)DispatchSemanticCode.BrightnessUp + 1];

        table[(int)DispatchSemanticCode.A] = LinuxEvdevCodes.KeyA;
        table[(int)DispatchSemanticCode.B] = LinuxEvdevCodes.KeyB;
        table[(int)DispatchSemanticCode.C] = LinuxEvdevCodes.KeyC;
        table[(int)DispatchSemanticCode.D] = LinuxEvdevCodes.KeyD;
        table[(int)DispatchSemanticCode.E] = LinuxEvdevCodes.KeyE;
        table[(int)DispatchSemanticCode.F] = LinuxEvdevCodes.KeyF;
        table[(int)DispatchSemanticCode.G] = LinuxEvdevCodes.KeyG;
        table[(int)DispatchSemanticCode.H] = LinuxEvdevCodes.KeyH;
        table[(int)DispatchSemanticCode.I] = LinuxEvdevCodes.KeyI;
        table[(int)DispatchSemanticCode.J] = LinuxEvdevCodes.KeyJ;
        table[(int)DispatchSemanticCode.K] = LinuxEvdevCodes.KeyK;
        table[(int)DispatchSemanticCode.L] = LinuxEvdevCodes.KeyL;
        table[(int)DispatchSemanticCode.M] = LinuxEvdevCodes.KeyM;
        table[(int)DispatchSemanticCode.N] = LinuxEvdevCodes.KeyN;
        table[(int)DispatchSemanticCode.O] = LinuxEvdevCodes.KeyO;
        table[(int)DispatchSemanticCode.P] = LinuxEvdevCodes.KeyP;
        table[(int)DispatchSemanticCode.Q] = LinuxEvdevCodes.KeyQ;
        table[(int)DispatchSemanticCode.R] = LinuxEvdevCodes.KeyR;
        table[(int)DispatchSemanticCode.S] = LinuxEvdevCodes.KeyS;
        table[(int)DispatchSemanticCode.T] = LinuxEvdevCodes.KeyT;
        table[(int)DispatchSemanticCode.U] = LinuxEvdevCodes.KeyU;
        table[(int)DispatchSemanticCode.V] = LinuxEvdevCodes.KeyV;
        table[(int)DispatchSemanticCode.W] = LinuxEvdevCodes.KeyW;
        table[(int)DispatchSemanticCode.X] = LinuxEvdevCodes.KeyX;
        table[(int)DispatchSemanticCode.Y] = LinuxEvdevCodes.KeyY;
        table[(int)DispatchSemanticCode.Z] = LinuxEvdevCodes.KeyZ;
        table[(int)DispatchSemanticCode.Digit0] = LinuxEvdevCodes.Key0;
        table[(int)DispatchSemanticCode.Digit1] = LinuxEvdevCodes.Key1;
        table[(int)DispatchSemanticCode.Digit2] = LinuxEvdevCodes.Key2;
        table[(int)DispatchSemanticCode.Digit3] = LinuxEvdevCodes.Key3;
        table[(int)DispatchSemanticCode.Digit4] = LinuxEvdevCodes.Key4;
        table[(int)DispatchSemanticCode.Digit5] = LinuxEvdevCodes.Key5;
        table[(int)DispatchSemanticCode.Digit6] = LinuxEvdevCodes.Key6;
        table[(int)DispatchSemanticCode.Digit7] = LinuxEvdevCodes.Key7;
        table[(int)DispatchSemanticCode.Digit8] = LinuxEvdevCodes.Key8;
        table[(int)DispatchSemanticCode.Digit9] = LinuxEvdevCodes.Key9;
        table[(int)DispatchSemanticCode.Backspace] = LinuxEvdevCodes.KeyBackspace;
        table[(int)DispatchSemanticCode.Tab] = LinuxEvdevCodes.KeyTab;
        table[(int)DispatchSemanticCode.Enter] = LinuxEvdevCodes.KeyEnter;
        table[(int)DispatchSemanticCode.Escape] = LinuxEvdevCodes.KeyEsc;
        table[(int)DispatchSemanticCode.Space] = LinuxEvdevCodes.KeySpace;
        table[(int)DispatchSemanticCode.PageUp] = LinuxEvdevCodes.KeyPageUp;
        table[(int)DispatchSemanticCode.PageDown] = LinuxEvdevCodes.KeyPageDown;
        table[(int)DispatchSemanticCode.End] = LinuxEvdevCodes.KeyEnd;
        table[(int)DispatchSemanticCode.Home] = LinuxEvdevCodes.KeyHome;
        table[(int)DispatchSemanticCode.Left] = LinuxEvdevCodes.KeyLeft;
        table[(int)DispatchSemanticCode.Up] = LinuxEvdevCodes.KeyUp;
        table[(int)DispatchSemanticCode.Right] = LinuxEvdevCodes.KeyRight;
        table[(int)DispatchSemanticCode.Down] = LinuxEvdevCodes.KeyDown;
        table[(int)DispatchSemanticCode.Insert] = LinuxEvdevCodes.KeyInsert;
        table[(int)DispatchSemanticCode.Delete] = LinuxEvdevCodes.KeyDelete;
        table[(int)DispatchSemanticCode.Shift] = LinuxEvdevCodes.KeyLeftShift;
        table[(int)DispatchSemanticCode.LeftShift] = LinuxEvdevCodes.KeyLeftShift;
        table[(int)DispatchSemanticCode.RightShift] = LinuxEvdevCodes.KeyRightShift;
        table[(int)DispatchSemanticCode.Ctrl] = LinuxEvdevCodes.KeyLeftCtrl;
        table[(int)DispatchSemanticCode.LeftCtrl] = LinuxEvdevCodes.KeyLeftCtrl;
        table[(int)DispatchSemanticCode.RightCtrl] = LinuxEvdevCodes.KeyRightCtrl;
        table[(int)DispatchSemanticCode.Alt] = LinuxEvdevCodes.KeyLeftAlt;
        table[(int)DispatchSemanticCode.LeftAlt] = LinuxEvdevCodes.KeyLeftAlt;
        table[(int)DispatchSemanticCode.RightAlt] = LinuxEvdevCodes.KeyRightAlt;
        table[(int)DispatchSemanticCode.Meta] = LinuxEvdevCodes.KeyLeftMeta;
        table[(int)DispatchSemanticCode.LeftMeta] = LinuxEvdevCodes.KeyLeftMeta;
        table[(int)DispatchSemanticCode.RightMeta] = LinuxEvdevCodes.KeyRightMeta;
        table[(int)DispatchSemanticCode.F1] = LinuxEvdevCodes.KeyF1;
        table[(int)DispatchSemanticCode.F2] = LinuxEvdevCodes.KeyF2;
        table[(int)DispatchSemanticCode.F3] = LinuxEvdevCodes.KeyF3;
        table[(int)DispatchSemanticCode.F4] = LinuxEvdevCodes.KeyF4;
        table[(int)DispatchSemanticCode.F5] = LinuxEvdevCodes.KeyF5;
        table[(int)DispatchSemanticCode.F6] = LinuxEvdevCodes.KeyF6;
        table[(int)DispatchSemanticCode.F7] = LinuxEvdevCodes.KeyF7;
        table[(int)DispatchSemanticCode.F8] = LinuxEvdevCodes.KeyF8;
        table[(int)DispatchSemanticCode.F9] = LinuxEvdevCodes.KeyF9;
        table[(int)DispatchSemanticCode.F10] = LinuxEvdevCodes.KeyF10;
        table[(int)DispatchSemanticCode.F11] = LinuxEvdevCodes.KeyF11;
        table[(int)DispatchSemanticCode.F12] = LinuxEvdevCodes.KeyF12;
        table[(int)DispatchSemanticCode.Semicolon] = LinuxEvdevCodes.KeySemicolon;
        table[(int)DispatchSemanticCode.Equal] = LinuxEvdevCodes.KeyEqual;
        table[(int)DispatchSemanticCode.Comma] = LinuxEvdevCodes.KeyComma;
        table[(int)DispatchSemanticCode.Minus] = LinuxEvdevCodes.KeyMinus;
        table[(int)DispatchSemanticCode.Dot] = LinuxEvdevCodes.KeyDot;
        table[(int)DispatchSemanticCode.Slash] = LinuxEvdevCodes.KeySlash;
        table[(int)DispatchSemanticCode.Grave] = LinuxEvdevCodes.KeyGrave;
        table[(int)DispatchSemanticCode.LeftBrace] = LinuxEvdevCodes.KeyLeftBrace;
        table[(int)DispatchSemanticCode.Backslash] = LinuxEvdevCodes.KeyBackslash;
        table[(int)DispatchSemanticCode.RightBrace] = LinuxEvdevCodes.KeyRightBrace;
        table[(int)DispatchSemanticCode.Apostrophe] = LinuxEvdevCodes.KeyApostrophe;
        table[(int)DispatchSemanticCode.BrightnessDown] = LinuxEvdevCodes.KeyBrightnessDown;
        table[(int)DispatchSemanticCode.BrightnessUp] = LinuxEvdevCodes.KeyBrightnessUp;

        return table;
    }

    private static ushort[] BuildVirtualKeyTable()
    {
        ushort[] table = new ushort[256];

        table[0x08] = LinuxEvdevCodes.KeyBackspace;
        table[0x09] = LinuxEvdevCodes.KeyTab;
        table[0x0D] = LinuxEvdevCodes.KeyEnter;
        table[0x10] = LinuxEvdevCodes.KeyLeftShift;
        table[0x11] = LinuxEvdevCodes.KeyLeftCtrl;
        table[0x12] = LinuxEvdevCodes.KeyLeftAlt;
        table[0x1B] = LinuxEvdevCodes.KeyEsc;
        table[0x20] = LinuxEvdevCodes.KeySpace;
        table[0x21] = LinuxEvdevCodes.KeyPageUp;
        table[0x22] = LinuxEvdevCodes.KeyPageDown;
        table[0x23] = LinuxEvdevCodes.KeyEnd;
        table[0x24] = LinuxEvdevCodes.KeyHome;
        table[0x25] = LinuxEvdevCodes.KeyLeft;
        table[0x26] = LinuxEvdevCodes.KeyUp;
        table[0x27] = LinuxEvdevCodes.KeyRight;
        table[0x28] = LinuxEvdevCodes.KeyDown;
        table[0x2D] = LinuxEvdevCodes.KeyInsert;
        table[0x2E] = LinuxEvdevCodes.KeyDelete;

        table[0x30] = LinuxEvdevCodes.Key0;
        table[0x31] = LinuxEvdevCodes.Key1;
        table[0x32] = LinuxEvdevCodes.Key2;
        table[0x33] = LinuxEvdevCodes.Key3;
        table[0x34] = LinuxEvdevCodes.Key4;
        table[0x35] = LinuxEvdevCodes.Key5;
        table[0x36] = LinuxEvdevCodes.Key6;
        table[0x37] = LinuxEvdevCodes.Key7;
        table[0x38] = LinuxEvdevCodes.Key8;
        table[0x39] = LinuxEvdevCodes.Key9;

        table[0x41] = LinuxEvdevCodes.KeyA;
        table[0x42] = LinuxEvdevCodes.KeyB;
        table[0x43] = LinuxEvdevCodes.KeyC;
        table[0x44] = LinuxEvdevCodes.KeyD;
        table[0x45] = LinuxEvdevCodes.KeyE;
        table[0x46] = LinuxEvdevCodes.KeyF;
        table[0x47] = LinuxEvdevCodes.KeyG;
        table[0x48] = LinuxEvdevCodes.KeyH;
        table[0x49] = LinuxEvdevCodes.KeyI;
        table[0x4A] = LinuxEvdevCodes.KeyJ;
        table[0x4B] = LinuxEvdevCodes.KeyK;
        table[0x4C] = LinuxEvdevCodes.KeyL;
        table[0x4D] = LinuxEvdevCodes.KeyM;
        table[0x4E] = LinuxEvdevCodes.KeyN;
        table[0x4F] = LinuxEvdevCodes.KeyO;
        table[0x50] = LinuxEvdevCodes.KeyP;
        table[0x51] = LinuxEvdevCodes.KeyQ;
        table[0x52] = LinuxEvdevCodes.KeyR;
        table[0x53] = LinuxEvdevCodes.KeyS;
        table[0x54] = LinuxEvdevCodes.KeyT;
        table[0x55] = LinuxEvdevCodes.KeyU;
        table[0x56] = LinuxEvdevCodes.KeyV;
        table[0x57] = LinuxEvdevCodes.KeyW;
        table[0x58] = LinuxEvdevCodes.KeyX;
        table[0x59] = LinuxEvdevCodes.KeyY;
        table[0x5A] = LinuxEvdevCodes.KeyZ;

        table[0x5B] = LinuxEvdevCodes.KeyLeftMeta;
        table[0x5C] = LinuxEvdevCodes.KeyRightMeta;

        table[0x70] = LinuxEvdevCodes.KeyF1;
        table[0x71] = LinuxEvdevCodes.KeyF2;
        table[0x72] = LinuxEvdevCodes.KeyF3;
        table[0x73] = LinuxEvdevCodes.KeyF4;
        table[0x74] = LinuxEvdevCodes.KeyF5;
        table[0x75] = LinuxEvdevCodes.KeyF6;
        table[0x76] = LinuxEvdevCodes.KeyF7;
        table[0x77] = LinuxEvdevCodes.KeyF8;
        table[0x78] = LinuxEvdevCodes.KeyF9;
        table[0x79] = LinuxEvdevCodes.KeyF10;
        table[0x7A] = LinuxEvdevCodes.KeyF11;
        table[0x7B] = LinuxEvdevCodes.KeyF12;

        table[0xA0] = LinuxEvdevCodes.KeyLeftShift;
        table[0xA1] = LinuxEvdevCodes.KeyRightShift;
        table[0xA2] = LinuxEvdevCodes.KeyLeftCtrl;
        table[0xA3] = LinuxEvdevCodes.KeyRightCtrl;
        table[0xA4] = LinuxEvdevCodes.KeyLeftAlt;
        table[0xA5] = LinuxEvdevCodes.KeyRightAlt;

        table[0xBA] = LinuxEvdevCodes.KeySemicolon;
        table[0xBB] = LinuxEvdevCodes.KeyEqual;
        table[0xBC] = LinuxEvdevCodes.KeyComma;
        table[0xBD] = LinuxEvdevCodes.KeyMinus;
        table[0xBE] = LinuxEvdevCodes.KeyDot;
        table[0xBF] = LinuxEvdevCodes.KeySlash;
        table[0xC0] = LinuxEvdevCodes.KeyGrave;
        table[0xDB] = LinuxEvdevCodes.KeyLeftBrace;
        table[0xDC] = LinuxEvdevCodes.KeyBackslash;
        table[0xDD] = LinuxEvdevCodes.KeyRightBrace;
        table[0xDE] = LinuxEvdevCodes.KeyApostrophe;

        return table;
    }
}
