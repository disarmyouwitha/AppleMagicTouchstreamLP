using System;

namespace GlassToKey;

public enum DispatchEventKind : byte
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

public enum DispatchMouseButton : byte
{
    None = 0,
    Left = 1,
    Right = 2,
    Middle = 3
}

public enum DispatchSemanticCode : ushort
{
    None = 0,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    Digit0,
    Digit1,
    Digit2,
    Digit3,
    Digit4,
    Digit5,
    Digit6,
    Digit7,
    Digit8,
    Digit9,
    Backspace,
    Tab,
    Enter,
    Escape,
    Space,
    PageUp,
    PageDown,
    End,
    Home,
    Left,
    Up,
    Right,
    Down,
    Insert,
    Delete,
    Shift,
    LeftShift,
    RightShift,
    Ctrl,
    LeftCtrl,
    RightCtrl,
    Alt,
    LeftAlt,
    RightAlt,
    Meta,
    LeftMeta,
    RightMeta,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    F13,
    F14,
    F15,
    F16,
    F17,
    F18,
    F19,
    F20,
    F21,
    F22,
    F23,
    F24,
    Semicolon,
    Equal,
    Comma,
    Minus,
    Dot,
    Slash,
    Grave,
    LeftBrace,
    Backslash,
    RightBrace,
    Apostrophe,
    CapsLock,
    NumLock,
    ScrollLock,
    PrintScreen,
    Pause,
    Menu,
    VolumeMute,
    VolumeDown,
    VolumeUp,
    MediaPreviousTrack,
    MediaNextTrack,
    MediaPlayPause,
    MediaStop,
    BrightnessDown,
    BrightnessUp
}

[Flags]
public enum DispatchSemanticKind : ushort
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
public enum DispatchEventFlags : byte
{
    None = 0,
    Repeatable = 1,
    Haptic = 2
}

public readonly record struct DispatchSemanticAction(
    DispatchSemanticKind Kind,
    string Label,
    DispatchSemanticCode PrimaryCode = DispatchSemanticCode.None,
    DispatchSemanticCode SecondaryCode = DispatchSemanticCode.None,
    DispatchMouseButton MouseButton = DispatchMouseButton.None)
{
    public static DispatchSemanticAction None => new(DispatchSemanticKind.None, string.Empty);
}

public readonly record struct DispatchEvent(
    long TimestampTicks,
    DispatchEventKind Kind,
    ushort VirtualKey,
    DispatchMouseButton MouseButton,
    ulong RepeatToken,
    DispatchEventFlags Flags,
    TrackpadSide Side,
    string DispatchLabel,
    DispatchSemanticAction SemanticAction = default);
