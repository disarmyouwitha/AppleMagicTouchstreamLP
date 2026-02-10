using System;

namespace GlassToKey;

internal static class DispatchKeyResolver
{
    public static bool TryResolveMouseButton(string label, out DispatchMouseButton button)
    {
        button = DispatchMouseButton.None;
        if (string.IsNullOrWhiteSpace(label))
        {
            return false;
        }

        if (label.Equals("LClick", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("MouseLeft", StringComparison.OrdinalIgnoreCase))
        {
            button = DispatchMouseButton.Left;
            return true;
        }

        if (label.Equals("RClick", StringComparison.OrdinalIgnoreCase) ||
            label.Equals("MouseRight", StringComparison.OrdinalIgnoreCase))
        {
            button = DispatchMouseButton.Right;
            return true;
        }

        if (label.Equals("MClick", StringComparison.OrdinalIgnoreCase) ||
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

        if (label.Equals("LShift", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0xA0;
            return true;
        }

        if (label.Equals("RShift", StringComparison.OrdinalIgnoreCase))
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

        if (label.Equals("LWin", StringComparison.OrdinalIgnoreCase))
        {
            virtualKey = 0x5B;
            return true;
        }

        if (label.Equals("RWin", StringComparison.OrdinalIgnoreCase))
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
