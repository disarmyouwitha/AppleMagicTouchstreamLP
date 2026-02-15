using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace GlassToKey;

internal sealed class SendInputDispatcher : IInputDispatcher
{
    private const uint InputMouse = 0;
    private const uint InputKeyboard = 1;

    private const uint KeyeventfKeyup = 0x0002;
    private const uint MouseeventfLeftdown = 0x0002;
    private const uint MouseeventfLeftup = 0x0004;
    private const uint MouseeventfRightdown = 0x0008;
    private const uint MouseeventfRightup = 0x0010;
    private const uint MouseeventfMiddledown = 0x0020;
    private const uint MouseeventfMiddleup = 0x0040;

    private readonly int[] _modifierRefCounts = new int[256];
    private readonly bool[] _keyDown = new bool[256];
    private readonly RepeatEntry[] _repeatEntries = new RepeatEntry[64];
    private readonly Input[] _singleInput = new Input[1];
    private readonly Input[] _dualInput = new Input[2];
    private readonly long _repeatInitialDelayTicks;
    private readonly long _repeatIntervalTicks;
    private bool _disposed;

    public SendInputDispatcher()
    {
        _repeatInitialDelayTicks = MsToTicks(275);
        _repeatIntervalTicks = MsToTicks(33);
    }

    public void Dispatch(in DispatchEvent dispatchEvent)
    {
        if (_disposed)
        {
            return;
        }

        switch (dispatchEvent.Kind)
        {
            case DispatchEventKind.KeyTap:
                if (TryDispatchSystemAction(dispatchEvent.VirtualKey))
                {
                    break;
                }

                if (dispatchEvent.VirtualKey != 0)
                {
                    SendKeyTap(dispatchEvent.VirtualKey);
                }
                break;
            case DispatchEventKind.KeyDown:
                HandleKeyDown(dispatchEvent.VirtualKey, dispatchEvent.RepeatToken, dispatchEvent.Flags, dispatchEvent.TimestampTicks);
                break;
            case DispatchEventKind.KeyUp:
                HandleKeyUp(dispatchEvent.VirtualKey, dispatchEvent.RepeatToken);
                break;
            case DispatchEventKind.ModifierDown:
                HandleModifierDown(dispatchEvent.VirtualKey);
                break;
            case DispatchEventKind.ModifierUp:
                HandleModifierUp(dispatchEvent.VirtualKey);
                break;
            case DispatchEventKind.MouseButtonClick:
                SendMouseButtonClick(dispatchEvent.MouseButton);
                break;
            case DispatchEventKind.MouseButtonDown:
                SendMouseButtonDown(dispatchEvent.MouseButton);
                break;
            case DispatchEventKind.MouseButtonUp:
                SendMouseButtonUp(dispatchEvent.MouseButton);
                break;
            case DispatchEventKind.None:
            default:
                break;
        }

        if ((dispatchEvent.Flags & DispatchEventFlags.Haptic) != 0)
        {
            _ = MagicTrackpadActuatorHaptics.TryVibrate();
        }
    }

    public void Tick(long nowTicks)
    {
        if (_disposed)
        {
            return;
        }

        for (int i = 0; i < _repeatEntries.Length; i++)
        {
            if (!_repeatEntries[i].Active)
            {
                continue;
            }

            if (nowTicks < _repeatEntries[i].NextTick)
            {
                continue;
            }

            SendKeyTap(_repeatEntries[i].VirtualKey);
            _repeatEntries[i].NextTick = nowTicks + _repeatIntervalTicks;
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        ReleaseAllHeldKeys();
    }

    private void HandleKeyDown(ushort virtualKey, ulong repeatToken, DispatchEventFlags flags, long timestampTicks)
    {
        if (virtualKey == 0)
        {
            return;
        }

        int vk = virtualKey;
        if ((uint)vk < (uint)_keyDown.Length && !_keyDown[vk])
        {
            SendKeyboard(virtualKey, keyUp: false);
            _keyDown[vk] = true;
        }

        if ((flags & DispatchEventFlags.Repeatable) != 0 && repeatToken != 0)
        {
            ScheduleRepeat(repeatToken, virtualKey, timestampTicks);
        }
    }

    private void HandleKeyUp(ushort virtualKey, ulong repeatToken)
    {
        if (repeatToken != 0)
        {
            CancelRepeat(repeatToken);
        }

        if (virtualKey == 0)
        {
            return;
        }

        int vk = virtualKey;
        if ((uint)vk < (uint)_keyDown.Length && _keyDown[vk])
        {
            SendKeyboard(virtualKey, keyUp: true);
            _keyDown[vk] = false;
        }
    }

    private void HandleModifierDown(ushort virtualKey)
    {
        if (virtualKey == 0)
        {
            return;
        }

        int vk = virtualKey;
        if ((uint)vk >= (uint)_modifierRefCounts.Length)
        {
            return;
        }

        _modifierRefCounts[vk]++;
        if (_modifierRefCounts[vk] == 1)
        {
            SendKeyboard(virtualKey, keyUp: false);
            _keyDown[vk] = true;
        }
    }

    private void HandleModifierUp(ushort virtualKey)
    {
        if (virtualKey == 0)
        {
            return;
        }

        int vk = virtualKey;
        if ((uint)vk >= (uint)_modifierRefCounts.Length)
        {
            return;
        }

        if (_modifierRefCounts[vk] <= 0)
        {
            return;
        }

        _modifierRefCounts[vk]--;
        if (_modifierRefCounts[vk] == 0)
        {
            SendKeyboard(virtualKey, keyUp: true);
            _keyDown[vk] = false;
        }
    }

    private void ScheduleRepeat(ulong token, ushort virtualKey, long timestampTicks)
    {
        for (int i = 0; i < _repeatEntries.Length; i++)
        {
            if (_repeatEntries[i].Active && _repeatEntries[i].Token == token)
            {
                _repeatEntries[i].VirtualKey = virtualKey;
                _repeatEntries[i].NextTick = timestampTicks + _repeatInitialDelayTicks;
                return;
            }
        }

        for (int i = 0; i < _repeatEntries.Length; i++)
        {
            if (_repeatEntries[i].Active)
            {
                continue;
            }

            _repeatEntries[i] = new RepeatEntry
            {
                Active = true,
                Token = token,
                VirtualKey = virtualKey,
                NextTick = timestampTicks + _repeatInitialDelayTicks
            };
            return;
        }
    }

    private void CancelRepeat(ulong token)
    {
        for (int i = 0; i < _repeatEntries.Length; i++)
        {
            if (!_repeatEntries[i].Active || _repeatEntries[i].Token != token)
            {
                continue;
            }

            _repeatEntries[i] = default;
            return;
        }
    }

    private void ReleaseAllHeldKeys()
    {
        for (int i = 0; i < _repeatEntries.Length; i++)
        {
            _repeatEntries[i] = default;
        }

        for (int vk = 0; vk < _modifierRefCounts.Length; vk++)
        {
            if (_modifierRefCounts[vk] > 0 || _keyDown[vk])
            {
                SendKeyboard((ushort)vk, keyUp: true);
                _modifierRefCounts[vk] = 0;
                _keyDown[vk] = false;
            }
        }
    }

    private void SendKeyTap(ushort virtualKey)
    {
        if (virtualKey == 0)
        {
            return;
        }

        _dualInput[0] = CreateKeyboardInput(virtualKey, keyUp: false);
        _dualInput[1] = CreateKeyboardInput(virtualKey, keyUp: true);
        SendInput(2, _dualInput, Marshal.SizeOf<Input>());
    }

    private void SendKeyboard(ushort virtualKey, bool keyUp)
    {
        _singleInput[0] = CreateKeyboardInput(virtualKey, keyUp);
        SendInput(1, _singleInput, Marshal.SizeOf<Input>());
    }

    private static Input CreateKeyboardInput(ushort virtualKey, bool keyUp)
    {
        return new Input
        {
            Type = InputKeyboard,
            Union = new InputUnion
            {
                Keyboard = new KeyboardInput
                {
                    VirtualKey = virtualKey,
                    ScanCode = 0,
                    Flags = keyUp ? KeyeventfKeyup : 0,
                    Time = 0,
                    ExtraInfo = IntPtr.Zero
                }
            }
        };
    }

    private void SendMouseButtonClick(DispatchMouseButton button)
    {
        (uint down, uint up) = ResolveMouseFlags(button);
        if (down == 0 || up == 0)
        {
            return;
        }

        _dualInput[0] = CreateMouseInput(down);
        _dualInput[1] = CreateMouseInput(up);
        SendInput(2, _dualInput, Marshal.SizeOf<Input>());
    }

    private void SendMouseButtonDown(DispatchMouseButton button)
    {
        (uint down, _) = ResolveMouseFlags(button);
        if (down == 0)
        {
            return;
        }

        _singleInput[0] = CreateMouseInput(down);
        SendInput(1, _singleInput, Marshal.SizeOf<Input>());
    }

    private void SendMouseButtonUp(DispatchMouseButton button)
    {
        (_, uint up) = ResolveMouseFlags(button);
        if (up == 0)
        {
            return;
        }

        _singleInput[0] = CreateMouseInput(up);
        SendInput(1, _singleInput, Marshal.SizeOf<Input>());
    }

    private static (uint Down, uint Up) ResolveMouseFlags(DispatchMouseButton button)
    {
        return button switch
        {
            DispatchMouseButton.Left => (MouseeventfLeftdown, MouseeventfLeftup),
            DispatchMouseButton.Right => (MouseeventfRightdown, MouseeventfRightup),
            DispatchMouseButton.Middle => (MouseeventfMiddledown, MouseeventfMiddleup),
            _ => (0, 0)
        };
    }

    private static Input CreateMouseInput(uint flags)
    {
        return new Input
        {
            Type = InputMouse,
            Union = new InputUnion
            {
                Mouse = new MouseInput
                {
                    DeltaX = 0,
                    DeltaY = 0,
                    MouseData = 0,
                    Flags = flags,
                    Time = 0,
                    ExtraInfo = IntPtr.Zero
                }
            }
        };
    }

    private static long MsToTicks(double milliseconds)
    {
        if (milliseconds <= 0)
        {
            return 0;
        }

        return (long)Math.Round(milliseconds * Stopwatch.Frequency / 1000.0);
    }

    private static bool TryDispatchSystemAction(ushort virtualKey)
    {
        if (virtualKey == DispatchKeyResolver.VirtualKeyBrightnessUp)
        {
            BrightnessController.StepUp();
            return true;
        }

        if (virtualKey == DispatchKeyResolver.VirtualKeyBrightnessDown)
        {
            BrightnessController.StepDown();
            return true;
        }

        return false;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public InputUnion Union;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public MouseInput Mouse;

        [FieldOffset(0)]
        public KeyboardInput Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int DeltaX;
        public int DeltaY;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint inputCount, [In] Input[] inputs, int size);

    private struct RepeatEntry
    {
        public bool Active;
        public ulong Token;
        public ushort VirtualKey;
        public long NextTick;
    }
}

internal sealed class NullInputDispatcher : IInputDispatcher
{
    public void Dispatch(in DispatchEvent dispatchEvent)
    {
    }

    public void Tick(long nowTicks)
    {
    }

    public void Dispose()
    {
    }
}
