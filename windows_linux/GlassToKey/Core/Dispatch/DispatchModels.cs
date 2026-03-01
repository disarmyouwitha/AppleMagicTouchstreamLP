using System;

namespace GlassToKey;

internal enum DispatchEventKind : byte
{
    None = 0,
    KeyTap = 1,
    KeyDown = 2,
    KeyUp = 3,
    ModifierDown = 4,
    ModifierUp = 5,
    MouseButtonClick = 6,
    MouseButtonDown = 7,
    MouseButtonUp = 8
}

internal enum DispatchMouseButton : byte
{
    None = 0,
    Left = 1,
    Right = 2,
    Middle = 3
}

[Flags]
internal enum DispatchSemanticKind : ushort
{
    None = 0,
    Key = 1 << 0,
    Modifier = 1 << 1,
    MouseButton = 1 << 2,
    KeyChord = 1 << 3,
    Continuous = 1 << 4,
    TypingToggle = 1 << 5,
    LayerSet = 1 << 6,
    LayerToggle = 1 << 7,
    MomentaryLayer = 1 << 8
}

[Flags]
internal enum DispatchEventFlags : byte
{
    None = 0,
    Repeatable = 1,
    Haptic = 2
}

internal readonly record struct DispatchSemanticAction(
    DispatchSemanticKind Kind,
    string Label)
{
    public static DispatchSemanticAction None => new(DispatchSemanticKind.None, string.Empty);
}

internal readonly record struct DispatchEvent(
    long TimestampTicks,
    DispatchEventKind Kind,
    ushort VirtualKey,
    DispatchMouseButton MouseButton,
    ulong RepeatToken,
    DispatchEventFlags Flags,
    TrackpadSide Side,
    string DispatchLabel,
    DispatchSemanticAction SemanticAction = default);
