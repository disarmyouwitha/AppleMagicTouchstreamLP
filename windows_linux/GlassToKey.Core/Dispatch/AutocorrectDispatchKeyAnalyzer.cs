namespace GlassToKey;

public static class AutocorrectDispatchKeyAnalyzer
{
    private const ushort VirtualKeyBackspace = 0x08;
    private const ushort VirtualKeyTab = 0x09;
    private const ushort VirtualKeyEnter = 0x0D;
    private const ushort VirtualKeySpace = 0x20;

    public static bool TryResolveLetter(in DispatchEvent dispatchEvent, bool shiftDown, out char letter)
    {
        if (TryResolveLetter(dispatchEvent.SemanticAction.PrimaryCode, shiftDown, out letter))
        {
            return true;
        }

        return TryResolveLetter(dispatchEvent.VirtualKey, shiftDown, out letter);
    }

    public static bool TryResolveLetter(DispatchSemanticCode code, bool shiftDown, out char letter)
    {
        if (code is >= DispatchSemanticCode.A and <= DispatchSemanticCode.Z)
        {
            char baseChar = (char)('a' + ((int)code - (int)DispatchSemanticCode.A));
            letter = shiftDown ? char.ToUpperInvariant(baseChar) : baseChar;
            return true;
        }

        letter = '\0';
        return false;
    }

    public static bool TryResolveLetter(ushort virtualKey, bool shiftDown, out char letter)
    {
        if (virtualKey is >= 0x41 and <= 0x5A)
        {
            char baseChar = (char)('a' + (virtualKey - 0x41));
            letter = shiftDown ? char.ToUpperInvariant(baseChar) : baseChar;
            return true;
        }

        letter = '\0';
        return false;
    }

    public static bool IsBackspace(in DispatchEvent dispatchEvent)
    {
        return dispatchEvent.SemanticAction.PrimaryCode == DispatchSemanticCode.Backspace ||
               dispatchEvent.VirtualKey == VirtualKeyBackspace;
    }

    public static bool IsWordBoundary(in DispatchEvent dispatchEvent)
    {
        if (IsWordBoundary(dispatchEvent.SemanticAction.PrimaryCode))
        {
            return true;
        }

        return dispatchEvent.VirtualKey is
            VirtualKeySpace or
            VirtualKeyTab or
            VirtualKeyEnter or
            0xBA or
            0xBC or
            0xBD or
            0xBE or
            0xBF or
            0xC0 or
            0xDB or
            0xDC or
            0xDD or
            0xDE;
    }

    public static bool IsWordBoundary(DispatchSemanticCode code)
    {
        return code is
            DispatchSemanticCode.Space or
            DispatchSemanticCode.Tab or
            DispatchSemanticCode.Enter or
            DispatchSemanticCode.Semicolon or
            DispatchSemanticCode.Comma or
            DispatchSemanticCode.Minus or
            DispatchSemanticCode.Dot or
            DispatchSemanticCode.Slash or
            DispatchSemanticCode.Grave or
            DispatchSemanticCode.LeftBrace or
            DispatchSemanticCode.Backslash or
            DispatchSemanticCode.RightBrace or
            DispatchSemanticCode.Apostrophe;
    }

    public static bool IsShortcutModifier(DispatchSemanticCode code)
    {
        return code is
            DispatchSemanticCode.Ctrl or
            DispatchSemanticCode.LeftCtrl or
            DispatchSemanticCode.RightCtrl or
            DispatchSemanticCode.Alt or
            DispatchSemanticCode.LeftAlt or
            DispatchSemanticCode.RightAlt or
            DispatchSemanticCode.Meta or
            DispatchSemanticCode.LeftMeta or
            DispatchSemanticCode.RightMeta;
    }

    public static bool IsShiftModifier(DispatchSemanticCode code)
    {
        return code is
            DispatchSemanticCode.Shift or
            DispatchSemanticCode.LeftShift or
            DispatchSemanticCode.RightShift;
    }

    public static bool TryResolveReplacementLetter(char ch, out DispatchSemanticCode code, out bool requiresShift)
    {
        requiresShift = false;
        if (ch is >= 'a' and <= 'z')
        {
            code = (DispatchSemanticCode)((int)DispatchSemanticCode.A + (ch - 'a'));
            return true;
        }

        if (ch is >= 'A' and <= 'Z')
        {
            code = (DispatchSemanticCode)((int)DispatchSemanticCode.A + (ch - 'A'));
            requiresShift = true;
            return true;
        }

        code = DispatchSemanticCode.None;
        return false;
    }
}
