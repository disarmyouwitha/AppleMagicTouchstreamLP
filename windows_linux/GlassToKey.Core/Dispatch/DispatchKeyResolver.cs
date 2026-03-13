using System;

namespace GlassToKey;

internal static class DispatchKeyResolver
{
    public const ushort VirtualKeyBrightnessDown = 0x0101;
    public const ushort VirtualKeyBrightnessUp = 0x0102;

    public static bool TryResolveMouseButton(string label, out DispatchMouseButton button)
    {
        button = DispatchMouseButton.None;
        if (string.IsNullOrWhiteSpace(label))
        {
            return false;
        }

        if (label.Equals("LClick", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("LeftClick", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("Left Click", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("DoubleClick", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("Double Click", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("MouseLeft", StringComparison.OrdinalIgnoreCase))
        {
            button = DispatchMouseButton.Left;
            return true;
        }

        if (label.Equals("RClick", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("RightClick", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("Right Click", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("MouseRight", StringComparison.OrdinalIgnoreCase))
        {
            button = DispatchMouseButton.Right;
            return true;
        }

        if (label.Equals("MClick", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("MiddleClick", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("Middle Click", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("MouseMiddle", StringComparison.OrdinalIgnoreCase))
        {
            button = DispatchMouseButton.Middle;
            return true;
        }

        return false;
    }

    public static bool TryResolveModifierVirtualKey(string label, out ushort virtualKey)
    {
        virtualKey = 0;
        if (string.IsNullOrWhiteSpace(label))
        {
            return false;
        }

        if (label.Equals("LShift", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("LeftShift", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0xA0;
            return true;
        }

        if (label.Equals("RShift", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("RightShift", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0xA1;
            return true;
        }

        if (label.Equals("Shift", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x10;
            return true;
        }

        if (label.Equals("LCtrl", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("LeftCtrl", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0xA2;
            return true;
        }

        if (label.Equals("RCtrl", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("RightCtrl", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0xA3;
            return true;
        }

        if (label.Equals("Ctrl", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x11;
            return true;
        }

        if (label.Equals("LAlt", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("LeftAlt", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0xA4;
            return true;
        }

        if (label.Equals("RAlt", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("RightAlt", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0xA5;
            return true;
        }

        if (label.Equals("Alt", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x12;
            return true;
        }

        if (label.Equals("LeftWin", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("LeftMeta", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x5B;
            return true;
        }

        if (label.Equals("RightWin", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("RightMeta", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x5C;
            return true;
        }

        return false;
    }

    public static bool TryResolveVirtualKey(string label, out ushort virtualKey)
    {
        virtualKey = 0;
        if (string.IsNullOrWhiteSpace(label))
        {
            return false;
        }

        string token = label.Trim();
        if (token.Length == 1)
        {
            char ch = token[0];
            if (ch >= 'a' && ch <= 'z')
            {
                virtualKey = (ushort)(ch - 'a' + 0x41);
                return true;
            }

            if (ch >= 'A' && ch <= 'Z')
            {
                virtualKey = (ushort)(ch - 'A' + 0x41);
                return true;
            }

            if (ch >= '0' && ch <= '9')
            {
                virtualKey = (ushort)(ch - '0' + 0x30);
                return true;
            }

            if (TryResolvePunctuation(ch, out virtualKey))
            {
                return true;
            }
        }

        string upperToken = token.ToUpperInvariant();
        string compactToken = upperToken.Replace("_", string.Empty, StringComparison.Ordinal)
            .Replace(" ", string.Empty, StringComparison.Ordinal);

        if (token.Equals("Space", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x20;
            return true;
        }

        if (token.Equals("Back", StringComparison.OrdinalIgnoreCase) ||
            token.Equals("Backspace", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x08;
            return true;
        }

        if (token.Equals("Ret", StringComparison.OrdinalIgnoreCase) ||
            token.Equals("Enter", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x0D;
            return true;
        }

        if (token.Equals("Tab", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x09;
            return true;
        }

        if (token.Equals("Esc", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x1B;
            return true;
        }

        if (token.Equals("Escape", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x1B;
            return true;
        }

        if (token.Equals("Delete", StringComparison.OrdinalIgnoreCase) || token.Equals("Del", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x2E;
            return true;
        }

        if (compactToken is "CAPSLOCK" or "CAPS")
        {
            virtualKey = 0x14;
            return true;
        }

        if (compactToken is "NUMLOCK" or "NUM")
        {
            virtualKey = 0x90;
            return true;
        }

        if (compactToken is "SCROLLLOCK" or "SCROLL")
        {
            virtualKey = 0x91;
            return true;
        }

        if (compactToken is "PRINTSCREEN" or "PRTSC" or "PRTSCN")
        {
            virtualKey = 0x2C;
            return true;
        }

        if (compactToken is "PAUSE" or "BREAK")
        {
            virtualKey = 0x13;
            return true;
        }

        if (compactToken is "MENU" or "APPS" or "APPLICATION")
        {
            virtualKey = 0x5D;
            return true;
        }

        if (token.Equals("Insert", StringComparison.OrdinalIgnoreCase) || token.Equals("Ins", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x2D;
            return true;
        }

        if (token.Equals("Home", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x24;
            return true;
        }

        if (token.Equals("End", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x23;
            return true;
        }

        if (token.Equals("PageUp", StringComparison.OrdinalIgnoreCase) || token.Equals("PgUp", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x21;
            return true;
        }

        if (token.Equals("PageDown", StringComparison.OrdinalIgnoreCase) || token.Equals("PgDn", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x22;
            return true;
        }

        if (token.Equals("Left", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x25;
            return true;
        }

        if (token.Equals("Up", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x26;
            return true;
        }

        if (token.Equals("Right", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x27;
            return true;
        }

        if (token.Equals("Down", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x28;
            return true;
        }

        if (token.Length >= 2 &&
            (token[0] == 'F' || token[0] == 'f') &&
            int.TryParse(token.Substring(1), out int fIndex) &&
            fIndex >= 1 &&
            fIndex <= 24)
        {
            virtualKey = (ushort)(0x70 + (fIndex - 1));
            return true;
        }

        if (compactToken is "VOLUP" or "VOLUMEUP")
        {
            virtualKey = 0xAF;
            return true;
        }

        if (compactToken is "MUTE" or "VOLMUTE" or "VOLUMEMUTE")
        {
            virtualKey = 0xAD;
            return true;
        }

        if (compactToken is "VOLDOWN" or "VOLUMEDOWN")
        {
            virtualKey = 0xAE;
            return true;
        }

        if (compactToken is "NEXTTRACK" or "MEDIANEXT" or "NEXTSONG" or "MEDIANEXTTRACK")
        {
            virtualKey = 0xB0;
            return true;
        }

        if (compactToken is "PREVTRACK" or "MEDIAPREV" or "PREVIOUSSONG" or "MEDIAPREVIOUSTRACK")
        {
            virtualKey = 0xB1;
            return true;
        }

        if (compactToken is "STOPMEDIA" or "MEDIASTOP")
        {
            virtualKey = 0xB2;
            return true;
        }

        if (compactToken is "PLAYPAUSE" or "MEDIAPLAYPAUSE")
        {
            virtualKey = 0xB3;
            return true;
        }

        if (token.Equals("BRIGHT_UP", StringComparison.OrdinalIgnoreCase) ||
            token.Equals("BRIGHTNESS_UP", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = VirtualKeyBrightnessUp;
            return true;
        }

        if (token.Equals("BRIGHT_DOWN", StringComparison.OrdinalIgnoreCase) ||
            token.Equals("BRIGHTNESS_DOWN", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = VirtualKeyBrightnessDown;
            return true;
        }

        return false;
    }

    private static bool TryResolvePunctuation(char ch, out ushort virtualKey)
    {
        virtualKey = ch switch
        {
            ';' => 0xBA,
            '+' => 0xBB,
            '=' => 0xBB,
            ',' => 0xBC,
            '-' => 0xBD,
            '—' => 0xBD,
            '.' => 0xBE,
            '/' => 0xBF,
            '`' => 0xC0,
            '[' => 0xDB,
            '\\' => 0xDC,
            ']' => 0xDD,
            '\'' => 0xDE,
            _ => 0
        };

        return virtualKey != 0;
    }
}
