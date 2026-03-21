namespace GlassToKey;

public enum ShortcutDisplayConvention
{
    Windows = 0,
    Linux = 1
}

public enum ShortcutModifierVariant : byte
{
    Generic = 0,
    Left = 1,
    Right = 2
}

public sealed class ShortcutModifierSpec
{
    public ShortcutModifierSpec(
        string genericLabel,
        string leftLabel,
        string rightLabel,
        DispatchModifierFlags genericFlag,
        DispatchModifierFlags leftFlag,
        DispatchModifierFlags rightFlag)
    {
        GenericLabel = genericLabel;
        LeftLabel = leftLabel;
        RightLabel = rightLabel;
        GenericFlag = genericFlag;
        LeftFlag = leftFlag;
        RightFlag = rightFlag;
    }

    public string GenericLabel { get; }
    public string LeftLabel { get; }
    public string RightLabel { get; }
    public DispatchModifierFlags GenericFlag { get; }
    public DispatchModifierFlags LeftFlag { get; }
    public DispatchModifierFlags RightFlag { get; }

    public string LabelFor(ShortcutModifierVariant variant)
    {
        return variant switch
        {
            ShortcutModifierVariant.Left => LeftLabel,
            ShortcutModifierVariant.Right => RightLabel,
            _ => GenericLabel
        };
    }

    public DispatchModifierFlags FlagFor(ShortcutModifierVariant variant)
    {
        return variant switch
        {
            ShortcutModifierVariant.Left => LeftFlag,
            ShortcutModifierVariant.Right => RightFlag,
            _ => GenericFlag
        };
    }

    public ShortcutModifierVariant VariantFrom(DispatchModifierFlags modifiers)
    {
        bool hasLeft = (modifiers & LeftFlag) != 0;
        bool hasRight = (modifiers & RightFlag) != 0;
        return hasLeft && !hasRight
            ? ShortcutModifierVariant.Left
            : hasRight && !hasLeft
                ? ShortcutModifierVariant.Right
                : ShortcutModifierVariant.Generic;
    }
}

public static class ShortcutModifierCatalog
{
    private static readonly ShortcutModifierSpec CtrlSpec = new(
        genericLabel: "Ctrl",
        leftLabel: "Left Ctrl",
        rightLabel: "Right Ctrl",
        genericFlag: DispatchModifierFlags.Ctrl,
        leftFlag: DispatchModifierFlags.LeftCtrl,
        rightFlag: DispatchModifierFlags.RightCtrl);

    private static readonly ShortcutModifierSpec ShiftSpec = new(
        genericLabel: "Shift",
        leftLabel: "Left Shift",
        rightLabel: "Right Shift",
        genericFlag: DispatchModifierFlags.Shift,
        leftFlag: DispatchModifierFlags.LeftShift,
        rightFlag: DispatchModifierFlags.RightShift);

    private static readonly ShortcutModifierSpec AltSpec = new(
        genericLabel: "Alt",
        leftLabel: "Left Alt",
        rightLabel: "AltGr",
        genericFlag: DispatchModifierFlags.Alt,
        leftFlag: DispatchModifierFlags.LeftAlt,
        rightFlag: DispatchModifierFlags.RightAlt);

    private static readonly ShortcutModifierSpec WindowsMetaSpec = new(
        genericLabel: "Win",
        leftLabel: "Left Win",
        rightLabel: "Right Win",
        genericFlag: DispatchModifierFlags.Meta,
        leftFlag: DispatchModifierFlags.LeftMeta,
        rightFlag: DispatchModifierFlags.RightMeta);

    private static readonly ShortcutModifierSpec LinuxMetaSpec = new(
        genericLabel: "Super",
        leftLabel: "Left Super",
        rightLabel: "Right Super",
        genericFlag: DispatchModifierFlags.Meta,
        leftFlag: DispatchModifierFlags.LeftMeta,
        rightFlag: DispatchModifierFlags.RightMeta);

    public static ShortcutModifierSpec Ctrl => CtrlSpec;
    public static ShortcutModifierSpec Shift => ShiftSpec;
    public static ShortcutModifierSpec Alt => AltSpec;

    public static ShortcutModifierSpec Meta(ShortcutDisplayConvention convention)
    {
        return convention == ShortcutDisplayConvention.Linux
            ? LinuxMetaSpec
            : WindowsMetaSpec;
    }
}
