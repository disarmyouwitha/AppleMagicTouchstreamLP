using System;
using System.Collections.Generic;

namespace GlassToKey;

public static class DispatchShortcutHelper
{
    private static readonly DispatchModifierFlags[] OrderedModifierFlags =
    {
        DispatchModifierFlags.Ctrl,
        DispatchModifierFlags.LeftCtrl,
        DispatchModifierFlags.RightCtrl,
        DispatchModifierFlags.Shift,
        DispatchModifierFlags.LeftShift,
        DispatchModifierFlags.RightShift,
        DispatchModifierFlags.Alt,
        DispatchModifierFlags.LeftAlt,
        DispatchModifierFlags.RightAlt,
        DispatchModifierFlags.Meta,
        DispatchModifierFlags.LeftMeta,
        DispatchModifierFlags.RightMeta
    };

    private static readonly string[] SupportedShortcutKeys =
    {
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "Space",
        "Backspace",
        "Tab",
        "Enter",
        "Esc",
        "Delete",
        "Insert",
        "Home",
        "End",
        "PageUp",
        "PageDown",
        "Left",
        "Up",
        "Right",
        "Down",
        ";",
        "=",
        ",",
        "-",
        ".",
        "/",
        "`",
        "[",
        "\\",
        "]",
        "'",
        "PrintScreen",
        "F1",
        "F2",
        "F3",
        "F4",
        "F5",
        "F6",
        "F7",
        "F8",
        "F9",
        "F10",
        "F11",
        "F12",
        "F13",
        "F14",
        "F15",
        "F16",
        "F17",
        "F18",
        "F19",
        "F20",
        "F21",
        "F22",
        "F23",
        "F24"
    };

    public static IReadOnlyList<string> ShortcutKeyLabels => SupportedShortcutKeys;

    public static bool TryParseShortcut(
        string text,
        out DispatchModifierFlags modifiers,
        out ushort keyVirtualKey,
        out DispatchSemanticCode primaryCode,
        out DispatchSemanticCode firstModifierCode,
        out ushort firstModifierVirtualKey)
    {
        modifiers = DispatchModifierFlags.None;
        keyVirtualKey = 0;
        primaryCode = DispatchSemanticCode.None;
        firstModifierCode = DispatchSemanticCode.None;
        firstModifierVirtualKey = 0;

        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        string[] tokens = text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (tokens.Length < 2)
        {
            return false;
        }

        string keyToken = tokens[^1];
        if (!DispatchSemanticResolver.TryResolveKeyCode(keyToken, out primaryCode) &&
            !DispatchKeyResolver.TryResolveVirtualKey(keyToken, out keyVirtualKey))
        {
            return false;
        }

        bool sawModifier = false;
        for (int index = 0; index < tokens.Length - 1; index++)
        {
            string modifierToken = tokens[index];
            if (!DispatchSemanticResolver.TryResolveModifierCode(modifierToken, out DispatchSemanticCode modifierCode))
            {
                return false;
            }

            DispatchModifierFlags flag = ToModifierFlag(modifierCode);
            if (flag == DispatchModifierFlags.None)
            {
                return false;
            }

            modifiers |= flag;
            if (!sawModifier)
            {
                sawModifier = true;
                firstModifierCode = modifierCode;
                DispatchKeyResolver.TryResolveModifierVirtualKey(modifierToken, out firstModifierVirtualKey);
            }
        }

        return sawModifier;
    }

    public static bool TryReadShortcut(
        string text,
        out DispatchModifierFlags modifiers,
        out string keyLabel)
    {
        keyLabel = string.Empty;
        if (!TryParseShortcut(
                text,
                out modifiers,
                out ushort keyVirtualKey,
                out DispatchSemanticCode primaryCode,
                out _,
                out _))
        {
            return false;
        }

        if (primaryCode != DispatchSemanticCode.None)
        {
            keyLabel = ToDisplayKeyLabel(primaryCode);
            return !string.IsNullOrEmpty(keyLabel);
        }

        if (keyVirtualKey != 0)
        {
            keyLabel = ToDisplayKeyLabel(keyVirtualKey);
            return !string.IsNullOrEmpty(keyLabel);
        }

        return false;
    }

    public static bool TryNormalizeShortcutKeyLabel(string text, out string normalized)
    {
        normalized = string.Empty;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        if (DispatchSemanticResolver.TryResolveKeyCode(text, out DispatchSemanticCode primaryCode))
        {
            normalized = ToDisplayKeyLabel(primaryCode);
            return !string.IsNullOrEmpty(normalized);
        }

        if (DispatchKeyResolver.TryResolveVirtualKey(text, out ushort keyVirtualKey))
        {
            normalized = ToDisplayKeyLabel(keyVirtualKey);
            return !string.IsNullOrEmpty(normalized);
        }

        return false;
    }

    public static int CopyModifierSemanticCodes(DispatchModifierFlags modifiers, Span<DispatchSemanticCode> destination)
    {
        int count = 0;
        for (int index = 0; index < OrderedModifierFlags.Length; index++)
        {
            DispatchModifierFlags flag = OrderedModifierFlags[index];
            if ((modifiers & flag) == 0)
            {
                continue;
            }

            DispatchSemanticCode code = ToSemanticCode(flag);
            if (code == DispatchSemanticCode.None)
            {
                continue;
            }

            if (count < destination.Length)
            {
                destination[count] = code;
            }

            count++;
        }

        return count;
    }

    public static bool HasAnyModifier(DispatchModifierFlags modifiers)
    {
        return modifiers != DispatchModifierFlags.None;
    }

    public static bool ContainsShortcutModifier(DispatchModifierFlags modifiers)
    {
        return (modifiers & (
            DispatchModifierFlags.Ctrl |
            DispatchModifierFlags.LeftCtrl |
            DispatchModifierFlags.RightCtrl |
            DispatchModifierFlags.Alt |
            DispatchModifierFlags.LeftAlt |
            DispatchModifierFlags.RightAlt |
            DispatchModifierFlags.Meta |
            DispatchModifierFlags.LeftMeta |
            DispatchModifierFlags.RightMeta)) != 0;
    }

    public static bool ContainsShiftModifier(DispatchModifierFlags modifiers)
    {
        return (modifiers & (
            DispatchModifierFlags.Shift |
            DispatchModifierFlags.LeftShift |
            DispatchModifierFlags.RightShift)) != 0;
    }

    public static string FormatShortcut(DispatchModifierFlags modifiers, string keyLabel)
    {
        if (string.IsNullOrWhiteSpace(keyLabel))
        {
            return string.Empty;
        }

        string[] parts = new string[13];
        int count = 0;
        for (int index = 0; index < OrderedModifierFlags.Length; index++)
        {
            DispatchModifierFlags flag = OrderedModifierFlags[index];
            if ((modifiers & flag) == 0)
            {
                continue;
            }

            string label = ToDisplayLabel(flag);
            if (!string.IsNullOrEmpty(label))
            {
                parts[count++] = label;
            }
        }

        if (count == 0)
        {
            return keyLabel.Trim();
        }

        string[] materialized = new string[count + 1];
        for (int index = 0; index < count; index++)
        {
            materialized[index] = parts[index];
        }

        materialized[count] = keyLabel.Trim();
        return string.Join("+", materialized);
    }

    public static DispatchModifierFlags ToModifierFlag(DispatchSemanticCode code)
    {
        return code switch
        {
            DispatchSemanticCode.Shift => DispatchModifierFlags.Shift,
            DispatchSemanticCode.LeftShift => DispatchModifierFlags.LeftShift,
            DispatchSemanticCode.RightShift => DispatchModifierFlags.RightShift,
            DispatchSemanticCode.Ctrl => DispatchModifierFlags.Ctrl,
            DispatchSemanticCode.LeftCtrl => DispatchModifierFlags.LeftCtrl,
            DispatchSemanticCode.RightCtrl => DispatchModifierFlags.RightCtrl,
            DispatchSemanticCode.Alt => DispatchModifierFlags.Alt,
            DispatchSemanticCode.LeftAlt => DispatchModifierFlags.LeftAlt,
            DispatchSemanticCode.RightAlt => DispatchModifierFlags.RightAlt,
            DispatchSemanticCode.Meta => DispatchModifierFlags.Meta,
            DispatchSemanticCode.LeftMeta => DispatchModifierFlags.LeftMeta,
            DispatchSemanticCode.RightMeta => DispatchModifierFlags.RightMeta,
            _ => DispatchModifierFlags.None
        };
    }

    public static DispatchSemanticCode ToSemanticCode(DispatchModifierFlags flag)
    {
        return flag switch
        {
            DispatchModifierFlags.Shift => DispatchSemanticCode.Shift,
            DispatchModifierFlags.LeftShift => DispatchSemanticCode.LeftShift,
            DispatchModifierFlags.RightShift => DispatchSemanticCode.RightShift,
            DispatchModifierFlags.Ctrl => DispatchSemanticCode.Ctrl,
            DispatchModifierFlags.LeftCtrl => DispatchSemanticCode.LeftCtrl,
            DispatchModifierFlags.RightCtrl => DispatchSemanticCode.RightCtrl,
            DispatchModifierFlags.Alt => DispatchSemanticCode.Alt,
            DispatchModifierFlags.LeftAlt => DispatchSemanticCode.LeftAlt,
            DispatchModifierFlags.RightAlt => DispatchSemanticCode.RightAlt,
            DispatchModifierFlags.Meta => DispatchSemanticCode.Meta,
            DispatchModifierFlags.LeftMeta => DispatchSemanticCode.LeftMeta,
            DispatchModifierFlags.RightMeta => DispatchSemanticCode.RightMeta,
            _ => DispatchSemanticCode.None
        };
    }

    private static string ToDisplayLabel(DispatchModifierFlags flag)
    {
        return flag switch
        {
            DispatchModifierFlags.Shift => "Shift",
            DispatchModifierFlags.LeftShift => "LeftShift",
            DispatchModifierFlags.RightShift => "RightShift",
            DispatchModifierFlags.Ctrl => "Ctrl",
            DispatchModifierFlags.LeftCtrl => "LeftCtrl",
            DispatchModifierFlags.RightCtrl => "RightCtrl",
            DispatchModifierFlags.Alt => "Alt",
            DispatchModifierFlags.LeftAlt => "LeftAlt",
            DispatchModifierFlags.RightAlt => "RightAlt",
            DispatchModifierFlags.Meta => "Win",
            DispatchModifierFlags.LeftMeta => "LeftWin",
            DispatchModifierFlags.RightMeta => "RightWin",
            _ => string.Empty
        };
    }

    private static string ToDisplayKeyLabel(DispatchSemanticCode code)
    {
        if (code is >= DispatchSemanticCode.A and <= DispatchSemanticCode.Z)
        {
            char letter = (char)('A' + (code - DispatchSemanticCode.A));
            return letter.ToString();
        }

        if (code is >= DispatchSemanticCode.Digit0 and <= DispatchSemanticCode.Digit9)
        {
            char digit = (char)('0' + (code - DispatchSemanticCode.Digit0));
            return digit.ToString();
        }

        return code switch
        {
            DispatchSemanticCode.Backspace => "Backspace",
            DispatchSemanticCode.Tab => "Tab",
            DispatchSemanticCode.Enter => "Enter",
            DispatchSemanticCode.Escape => "Esc",
            DispatchSemanticCode.Space => "Space",
            DispatchSemanticCode.PageUp => "PageUp",
            DispatchSemanticCode.PageDown => "PageDown",
            DispatchSemanticCode.End => "End",
            DispatchSemanticCode.Home => "Home",
            DispatchSemanticCode.Left => "Left",
            DispatchSemanticCode.Up => "Up",
            DispatchSemanticCode.Right => "Right",
            DispatchSemanticCode.Down => "Down",
            DispatchSemanticCode.Insert => "Insert",
            DispatchSemanticCode.Delete => "Delete",
            DispatchSemanticCode.F1 => "F1",
            DispatchSemanticCode.F2 => "F2",
            DispatchSemanticCode.F3 => "F3",
            DispatchSemanticCode.F4 => "F4",
            DispatchSemanticCode.F5 => "F5",
            DispatchSemanticCode.F6 => "F6",
            DispatchSemanticCode.F7 => "F7",
            DispatchSemanticCode.F8 => "F8",
            DispatchSemanticCode.F9 => "F9",
            DispatchSemanticCode.F10 => "F10",
            DispatchSemanticCode.F11 => "F11",
            DispatchSemanticCode.F12 => "F12",
            DispatchSemanticCode.F13 => "F13",
            DispatchSemanticCode.F14 => "F14",
            DispatchSemanticCode.F15 => "F15",
            DispatchSemanticCode.F16 => "F16",
            DispatchSemanticCode.F17 => "F17",
            DispatchSemanticCode.F18 => "F18",
            DispatchSemanticCode.F19 => "F19",
            DispatchSemanticCode.F20 => "F20",
            DispatchSemanticCode.F21 => "F21",
            DispatchSemanticCode.F22 => "F22",
            DispatchSemanticCode.F23 => "F23",
            DispatchSemanticCode.F24 => "F24",
            DispatchSemanticCode.Semicolon => ";",
            DispatchSemanticCode.Equal => "=",
            DispatchSemanticCode.Comma => ",",
            DispatchSemanticCode.Minus => "-",
            DispatchSemanticCode.Dot => ".",
            DispatchSemanticCode.Slash => "/",
            DispatchSemanticCode.Grave => "`",
            DispatchSemanticCode.LeftBrace => "[",
            DispatchSemanticCode.Backslash => "\\",
            DispatchSemanticCode.RightBrace => "]",
            DispatchSemanticCode.Apostrophe => "'",
            DispatchSemanticCode.CapsLock => "CapsLock",
            DispatchSemanticCode.NumLock => "NumLock",
            DispatchSemanticCode.ScrollLock => "ScrollLock",
            DispatchSemanticCode.PrintScreen => "PrintScreen",
            DispatchSemanticCode.Pause => "Pause",
            DispatchSemanticCode.Menu => "Menu",
            DispatchSemanticCode.VolumeMute => "VolumeMute",
            DispatchSemanticCode.VolumeDown => "VolumeDown",
            DispatchSemanticCode.VolumeUp => "VolumeUp",
            DispatchSemanticCode.MediaPreviousTrack => "MediaPreviousTrack",
            DispatchSemanticCode.MediaNextTrack => "MediaNextTrack",
            DispatchSemanticCode.MediaPlayPause => "MediaPlayPause",
            DispatchSemanticCode.MediaStop => "MediaStop",
            DispatchSemanticCode.BrightnessDown => "BrightnessDown",
            DispatchSemanticCode.BrightnessUp => "BrightnessUp",
            _ => string.Empty
        };
    }

    private static string ToDisplayKeyLabel(ushort virtualKey)
    {
        if (virtualKey is >= 0x41 and <= 0x5A)
        {
            char letter = (char)virtualKey;
            return letter.ToString();
        }

        if (virtualKey is >= 0x30 and <= 0x39)
        {
            char digit = (char)virtualKey;
            return digit.ToString();
        }

        return virtualKey switch
        {
            0x08 => "Backspace",
            0x09 => "Tab",
            0x0D => "Enter",
            0x1B => "Esc",
            0x20 => "Space",
            0x21 => "PageUp",
            0x22 => "PageDown",
            0x23 => "End",
            0x24 => "Home",
            0x25 => "Left",
            0x26 => "Up",
            0x27 => "Right",
            0x28 => "Down",
            0x2D => "Insert",
            0x2E => "Delete",
            0x2C => "PrintScreen",
            0x70 => "F1",
            0x71 => "F2",
            0x72 => "F3",
            0x73 => "F4",
            0x74 => "F5",
            0x75 => "F6",
            0x76 => "F7",
            0x77 => "F8",
            0x78 => "F9",
            0x79 => "F10",
            0x7A => "F11",
            0x7B => "F12",
            0x7C => "F13",
            0x7D => "F14",
            0x7E => "F15",
            0x7F => "F16",
            0x80 => "F17",
            0x81 => "F18",
            0x82 => "F19",
            0x83 => "F20",
            0x84 => "F21",
            0x85 => "F22",
            0x86 => "F23",
            0x87 => "F24",
            0xBA => ";",
            0xBB => "=",
            0xBC => ",",
            0xBD => "-",
            0xBE => ".",
            0xBF => "/",
            0xC0 => "`",
            0xDB => "[",
            0xDC => "\\",
            0xDD => "]",
            0xDE => "'",
            DispatchKeyResolver.VirtualKeyBrightnessDown => "BrightnessDown",
            DispatchKeyResolver.VirtualKeyBrightnessUp => "BrightnessUp",
            _ => string.Empty
        };
    }
}
