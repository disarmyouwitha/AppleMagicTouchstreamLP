using System.Runtime.CompilerServices;

namespace GlassToKey;

public readonly struct ButtonEdgeState
{
    private const byte PressedMask = 0x01;
    private const byte DownMask = 0x02;
    private const byte UpMask = 0x04;
    private const byte HasHistoryMask = 0x08;
    private readonly byte _flags;

    internal ButtonEdgeState(byte flags)
    {
        _flags = flags;
    }

    public static ButtonEdgeState Unknown => default;

    public bool IsPressed
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get => (_flags & PressedMask) != 0;
    }

    public bool JustPressed
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get => (_flags & DownMask) != 0;
    }

    public bool JustReleased
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get => (_flags & UpMask) != 0;
    }

    public bool Changed
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get => (_flags & (DownMask | UpMask)) != 0;
    }

    public bool HasHistory
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get => (_flags & HasHistoryMask) != 0;
    }
}

public struct ButtonEdgeTracker
{
    private byte _lastPressed;
    private byte _hasState;

    public readonly ButtonEdgeState Current
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get
        {
            if (_hasState == 0)
            {
                return ButtonEdgeState.Unknown;
            }

            return new ButtonEdgeState((byte)(0x08 | _lastPressed));
        }
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public ButtonEdgeState Update(in InputFrame frame)
    {
        return Update(frame.IsButtonClicked);
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public ButtonEdgeState Update(byte isButtonClicked)
    {
        byte pressed = isButtonClicked == 0 ? (byte)0 : (byte)1;
        byte flags = pressed;
        if (_hasState != 0)
        {
            flags |= 0x08;
            if (pressed != _lastPressed)
            {
                flags |= pressed != 0 ? (byte)0x02 : (byte)0x04;
            }
        }

        _lastPressed = pressed;
        _hasState = 1;
        return new ButtonEdgeState(flags);
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void Reset()
    {
        _lastPressed = 0;
        _hasState = 0;
    }
}
