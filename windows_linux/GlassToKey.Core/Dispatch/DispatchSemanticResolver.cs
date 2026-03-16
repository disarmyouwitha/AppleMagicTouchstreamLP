using System.Globalization;

namespace GlassToKey;

internal static class DispatchSemanticResolver
{
    public static bool TryResolveKeyCode(string label, out DispatchSemanticCode code)
    {
        code = DispatchSemanticCode.None;
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
                code = (DispatchSemanticCode)((int)DispatchSemanticCode.A + (ch - 'a'));
                return true;
            }

            if (ch >= 'A' && ch <= 'Z')
            {
                code = (DispatchSemanticCode)((int)DispatchSemanticCode.A + (ch - 'A'));
                return true;
            }

            if (ch >= '0' && ch <= '9')
            {
                code = (DispatchSemanticCode)((int)DispatchSemanticCode.Digit0 + (ch - '0'));
                return true;
            }

            if (TryResolvePunctuation(ch, out code))
            {
                return true;
            }
        }

        string upperToken = token.ToUpperInvariant();
        string compactToken = upperToken.Replace("_", string.Empty, StringComparison.Ordinal)
            .Replace(" ", string.Empty, StringComparison.Ordinal);

        switch (compactToken)
        {
            case "SPACE":
                code = DispatchSemanticCode.Space;
                return true;
            case "BACK":
            case "BACKSPACE":
                code = DispatchSemanticCode.Backspace;
                return true;
            case "RET":
            case "ENTER":
                code = DispatchSemanticCode.Enter;
                return true;
            case "TAB":
                code = DispatchSemanticCode.Tab;
                return true;
            case "ESC":
            case "ESCAPE":
                code = DispatchSemanticCode.Escape;
                return true;
            case "DELETE":
            case "DEL":
                code = DispatchSemanticCode.Delete;
                return true;
            case "CAPSLOCK":
            case "CAPS":
                code = DispatchSemanticCode.CapsLock;
                return true;
            case "NUMLOCK":
            case "NUM":
                code = DispatchSemanticCode.NumLock;
                return true;
            case "SCROLLLOCK":
            case "SCROLL":
                code = DispatchSemanticCode.ScrollLock;
                return true;
            case "PRINTSCREEN":
            case "PRTSC":
            case "PRTSCN":
                code = DispatchSemanticCode.PrintScreen;
                return true;
            case "PAUSE":
            case "BREAK":
                code = DispatchSemanticCode.Pause;
                return true;
            case "MENU":
            case "APPS":
            case "APPLICATION":
                code = DispatchSemanticCode.Menu;
                return true;
            case "INSERT":
            case "INS":
                code = DispatchSemanticCode.Insert;
                return true;
            case "HOME":
                code = DispatchSemanticCode.Home;
                return true;
            case "END":
                code = DispatchSemanticCode.End;
                return true;
            case "PAGEUP":
            case "PGUP":
                code = DispatchSemanticCode.PageUp;
                return true;
            case "PAGEDOWN":
            case "PGDN":
                code = DispatchSemanticCode.PageDown;
                return true;
            case "LEFT":
                code = DispatchSemanticCode.Left;
                return true;
            case "UP":
                code = DispatchSemanticCode.Up;
                return true;
            case "RIGHT":
                code = DispatchSemanticCode.Right;
                return true;
            case "DOWN":
                code = DispatchSemanticCode.Down;
                return true;
            case "EMDASH":
            case "—":
                code = DispatchSemanticCode.Minus;
                return true;
            case "VOLDOWN":
            case "VOLUMEDOWN":
                code = DispatchSemanticCode.VolumeDown;
                return true;
            case "VOLMUTE":
            case "MUTE":
            case "VOLUMEMUTE":
                code = DispatchSemanticCode.VolumeMute;
                return true;
            case "VOLUP":
            case "VOLUMEUP":
                code = DispatchSemanticCode.VolumeUp;
                return true;
            case "MEDIAPREV":
            case "PREVTRACK":
            case "PREVIOUSSONG":
            case "MEDIAPREVIOUSTRACK":
                code = DispatchSemanticCode.MediaPreviousTrack;
                return true;
            case "MEDIANEXT":
            case "NEXTTRACK":
            case "NEXTSONG":
            case "MEDIANEXTTRACK":
                code = DispatchSemanticCode.MediaNextTrack;
                return true;
            case "PLAYPAUSE":
            case "MEDIAPLAYPAUSE":
                code = DispatchSemanticCode.MediaPlayPause;
                return true;
            case "MEDIASTOP":
            case "STOPMEDIA":
            case "STOP":
                code = DispatchSemanticCode.MediaStop;
                return true;
            case "BRIGHTNESSDOWN":
            case "BRIGHTDOWN":
                code = DispatchSemanticCode.BrightnessDown;
                return true;
            case "BRIGHTNESSUP":
            case "BRIGHTUP":
                code = DispatchSemanticCode.BrightnessUp;
                return true;
        }

        if (token.Length is >= 2 and <= 3 &&
            token[0] is 'F' or 'f' &&
            int.TryParse(token.AsSpan(1), NumberStyles.None, CultureInfo.InvariantCulture, out int functionIndex) &&
            functionIndex >= 1 &&
            functionIndex <= 24)
        {
            code = (DispatchSemanticCode)((int)DispatchSemanticCode.F1 + (functionIndex - 1));
            return true;
        }

        return false;
    }

    public static bool TryResolveModifierCode(string label, out DispatchSemanticCode code)
    {
        code = DispatchSemanticCode.None;
        if (string.IsNullOrWhiteSpace(label))
        {
            return false;
        }

        string compactToken = label.Trim().ToUpperInvariant()
            .Replace("_", string.Empty, StringComparison.Ordinal)
            .Replace(" ", string.Empty, StringComparison.Ordinal)
            .Replace("-", string.Empty, StringComparison.Ordinal);

        switch (compactToken)
        {
            case "LSHIFT":
                code = DispatchSemanticCode.LeftShift;
                return true;
            case "RSHIFT":
                code = DispatchSemanticCode.RightShift;
                return true;
            case "SHIFT":
            case "CHORDSHIFT":
            case "CHORDALSHIFT":
                code = DispatchSemanticCode.Shift;
                return true;
            case "LCTRL":
            case "LEFTCTRL":
                code = DispatchSemanticCode.LeftCtrl;
                return true;
            case "RCTRL":
            case "RIGHTCTRL":
                code = DispatchSemanticCode.RightCtrl;
                return true;
            case "CTRL":
                code = DispatchSemanticCode.Ctrl;
                return true;
            case "LALT":
            case "LEFTALT":
                code = DispatchSemanticCode.LeftAlt;
                return true;
            case "ALTGR":
            case "RALT":
            case "RIGHTALT":
            case "ROPTION":
            case "RIGHTOPTION":
                code = DispatchSemanticCode.RightAlt;
                return true;
            case "ALT":
            case "OPTION":
                code = DispatchSemanticCode.Alt;
                return true;
            case "LCMD":
            case "LEFTCMD":
            case "LEFTCOMMAND":
            case "LWIN":
            case "LMETA":
            case "LSUPER":
            case "LEFTWIN":
            case "LEFTMETA":
            case "LEFTSUPER":
                code = DispatchSemanticCode.LeftMeta;
                return true;
            case "RCMD":
            case "RIGHTCMD":
            case "RIGHTCOMMAND":
            case "RWIN":
            case "RMETA":
            case "RSUPER":
            case "RIGHTWIN":
            case "RIGHTMETA":
            case "RIGHTSUPER":
                code = DispatchSemanticCode.RightMeta;
                return true;
            case "CMD":
            case "COMMAND":
            case "WIN":
            case "META":
            case "SUPER":
                code = DispatchSemanticCode.Meta;
                return true;
            case "LOPTION":
            case "LEFTOPTION":
                code = DispatchSemanticCode.LeftAlt;
                return true;
            default:
                return false;
        }
    }

    public static bool TryResolveShiftChordPrimary(string label, out DispatchSemanticCode code)
    {
        code = label switch
        {
            "!" => DispatchSemanticCode.Digit1,
            "@" => DispatchSemanticCode.Digit2,
            "#" => DispatchSemanticCode.Digit3,
            "$" => DispatchSemanticCode.Digit4,
            "%" => DispatchSemanticCode.Digit5,
            "^" => DispatchSemanticCode.Digit6,
            "&" => DispatchSemanticCode.Digit7,
            "*" => DispatchSemanticCode.Digit8,
            "(" => DispatchSemanticCode.Digit9,
            ")" => DispatchSemanticCode.Digit0,
            "~" => DispatchSemanticCode.Grave,
            "_" => DispatchSemanticCode.Minus,
            "+" => DispatchSemanticCode.Equal,
            "{" => DispatchSemanticCode.LeftBrace,
            "}" => DispatchSemanticCode.RightBrace,
            "|" => DispatchSemanticCode.Backslash,
            ":" => DispatchSemanticCode.Semicolon,
            "\"" => DispatchSemanticCode.Apostrophe,
            "<" => DispatchSemanticCode.Comma,
            ">" => DispatchSemanticCode.Dot,
            "?" => DispatchSemanticCode.Slash,
            _ => DispatchSemanticCode.None
        };

        return code != DispatchSemanticCode.None;
    }

    private static bool TryResolvePunctuation(char ch, out DispatchSemanticCode code)
    {
        code = ch switch
        {
            ';' => DispatchSemanticCode.Semicolon,
            '=' => DispatchSemanticCode.Equal,
            ',' => DispatchSemanticCode.Comma,
            '-' => DispatchSemanticCode.Minus,
            '.' => DispatchSemanticCode.Dot,
            '/' => DispatchSemanticCode.Slash,
            '`' => DispatchSemanticCode.Grave,
            '[' => DispatchSemanticCode.LeftBrace,
            '\\' => DispatchSemanticCode.Backslash,
            ']' => DispatchSemanticCode.RightBrace,
            '\'' => DispatchSemanticCode.Apostrophe,
            _ => DispatchSemanticCode.None
        };

        return code != DispatchSemanticCode.None;
    }
}
