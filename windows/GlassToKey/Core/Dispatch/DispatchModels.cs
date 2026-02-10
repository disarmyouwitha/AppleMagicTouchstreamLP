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
internal enum DispatchEventFlags : byte
{
    None = 0,
    Repeatable = 1
}

internal readonly record struct DispatchEvent(
    long TimestampTicks,
    DispatchEventKind Kind,
    ushort VirtualKey,
    DispatchMouseButton MouseButton,
    ulong RepeatToken,
    DispatchEventFlags Flags,
    TrackpadSide Side,
    string DispatchLabel);
