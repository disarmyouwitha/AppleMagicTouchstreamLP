using System.Diagnostics;

namespace GlassToKey.Platform.Linux.Uinput;

public sealed class LinuxUinputDispatcher : IInputDispatcher
{
    private readonly LinuxUinputDevice _device;
    private readonly int[] _modifierRefCounts = new int[256];
    private readonly bool[] _keyDown = new bool[256];
    private readonly RepeatEntry[] _repeatEntries = new RepeatEntry[64];
    private readonly object _gate = new();
    private readonly long _repeatInitialDelayTicks;
    private readonly long _repeatIntervalTicks;
    private bool _disposed;

    public LinuxUinputDispatcher()
        : this(new LinuxUinputDevice())
    {
    }

    internal LinuxUinputDispatcher(LinuxUinputDevice device)
    {
        _device = device;
        _repeatInitialDelayTicks = MsToTicks(275);
        _repeatIntervalTicks = MsToTicks(33);
    }

    public void Dispatch(in DispatchEvent dispatchEvent)
    {
        if (_disposed)
        {
            return;
        }

        lock (_gate)
        {
            switch (dispatchEvent.Kind)
            {
                case DispatchEventKind.KeyTap:
                    HandleKeyTap(dispatchEvent);
                    break;
                case DispatchEventKind.KeyDown:
                    HandleKeyDown(dispatchEvent);
                    break;
                case DispatchEventKind.KeyUp:
                    HandleKeyUp(dispatchEvent);
                    break;
                case DispatchEventKind.ModifierDown:
                    HandleModifierDown(dispatchEvent);
                    break;
                case DispatchEventKind.ModifierUp:
                    HandleModifierUp(dispatchEvent);
                    break;
                case DispatchEventKind.MouseButtonClick:
                    if (TryResolveMouseButtonCode(dispatchEvent, out ushort clickButton))
                    {
                        _device.EmitClick(clickButton);
                    }
                    break;
                case DispatchEventKind.MouseButtonDown:
                    if (TryResolveMouseButtonCode(dispatchEvent, out ushort downButton))
                    {
                        _device.EmitKey(downButton, isDown: true);
                    }
                    break;
                case DispatchEventKind.MouseButtonUp:
                    if (TryResolveMouseButtonCode(dispatchEvent, out ushort upButton))
                    {
                        _device.EmitKey(upButton, isDown: false);
                    }
                    break;
            }
        }
    }

    public void Tick(long nowTicks)
    {
        if (_disposed)
        {
            return;
        }

        lock (_gate)
        {
            for (int index = 0; index < _repeatEntries.Length; index++)
            {
                ref RepeatEntry entry = ref _repeatEntries[index];
                if (!entry.Active || nowTicks < entry.NextTick)
                {
                    continue;
                }

                if (TrySendKeyCode(entry.KeyCode, isDown: false))
                {
                    TrySendKeyCode(entry.KeyCode, isDown: true);
                }

                entry.NextTick = nowTicks + _repeatIntervalTicks;
            }
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            for (int keyCode = 0; keyCode < _keyDown.Length; keyCode++)
            {
                if (_keyDown[keyCode])
                {
                    TrySendKeyCode((ushort)keyCode, isDown: false);
                    _keyDown[keyCode] = false;
                }
            }

            Array.Clear(_modifierRefCounts, 0, _modifierRefCounts.Length);
            Array.Clear(_repeatEntries, 0, _repeatEntries.Length);
            _disposed = true;
        }

        _device.Dispose();
    }

    private void HandleKeyTap(in DispatchEvent dispatchEvent)
    {
        if (!TryResolveKeyCode(dispatchEvent, out ushort keyCode))
        {
            return;
        }

        TrySendKeyCode(keyCode, isDown: true);
        TrySendKeyCode(keyCode, isDown: false);
    }

    private void HandleKeyDown(in DispatchEvent dispatchEvent)
    {
        if (!TryResolveKeyCode(dispatchEvent, out ushort keyCode))
        {
            return;
        }

        if ((uint)keyCode < (uint)_keyDown.Length)
        {
            if (!_keyDown[keyCode])
            {
                if (!TrySendKeyCode(keyCode, isDown: true))
                {
                    return;
                }

                _keyDown[keyCode] = true;
            }
        }
        else if (!TrySendKeyCode(keyCode, isDown: true))
        {
            return;
        }

        if ((dispatchEvent.Flags & DispatchEventFlags.Repeatable) != 0 && dispatchEvent.RepeatToken != 0)
        {
            ScheduleRepeat(dispatchEvent.RepeatToken, keyCode, dispatchEvent.TimestampTicks);
        }
    }

    private void HandleKeyUp(in DispatchEvent dispatchEvent)
    {
        if (dispatchEvent.RepeatToken != 0)
        {
            CancelRepeat(dispatchEvent.RepeatToken);
        }

        if (!TryResolveKeyCode(dispatchEvent, out ushort keyCode))
        {
            return;
        }

        if ((uint)keyCode < (uint)_keyDown.Length)
        {
            if (!_keyDown[keyCode])
            {
                return;
            }

            if (TrySendKeyCode(keyCode, isDown: false))
            {
                _keyDown[keyCode] = false;
            }

            return;
        }

        TrySendKeyCode(keyCode, isDown: false);
    }

    private void HandleModifierDown(in DispatchEvent dispatchEvent)
    {
        if (!TryResolveModifierKeyCode(dispatchEvent, out ushort keyCode) ||
            (uint)keyCode >= (uint)_modifierRefCounts.Length)
        {
            return;
        }

        _modifierRefCounts[keyCode]++;
        if (_modifierRefCounts[keyCode] != 1)
        {
            return;
        }

        if (TrySendKeyCode(keyCode, isDown: true))
        {
            _keyDown[keyCode] = true;
        }
    }

    private void HandleModifierUp(in DispatchEvent dispatchEvent)
    {
        if (!TryResolveModifierKeyCode(dispatchEvent, out ushort keyCode) ||
            (uint)keyCode >= (uint)_modifierRefCounts.Length ||
            _modifierRefCounts[keyCode] <= 0)
        {
            return;
        }

        _modifierRefCounts[keyCode]--;
        if (_modifierRefCounts[keyCode] != 0)
        {
            return;
        }

        if (TrySendKeyCode(keyCode, isDown: false))
        {
            _keyDown[keyCode] = false;
        }
    }

    private bool TrySendKeyCode(ushort keyCode, bool isDown)
    {
        if (keyCode == 0)
        {
            return false;
        }

        _device.EmitKey(keyCode, isDown);
        return true;
    }

    private void ScheduleRepeat(ulong token, ushort keyCode, long timestampTicks)
    {
        for (int index = 0; index < _repeatEntries.Length; index++)
        {
            ref RepeatEntry entry = ref _repeatEntries[index];
            if (!entry.Active || entry.Token != token)
            {
                continue;
            }

            entry.KeyCode = keyCode;
            entry.NextTick = timestampTicks + _repeatInitialDelayTicks;
            return;
        }

        for (int index = 0; index < _repeatEntries.Length; index++)
        {
            ref RepeatEntry entry = ref _repeatEntries[index];
            if (entry.Active)
            {
                continue;
            }

            entry.Active = true;
            entry.Token = token;
            entry.KeyCode = keyCode;
            entry.NextTick = timestampTicks + _repeatInitialDelayTicks;
            return;
        }
    }

    private void CancelRepeat(ulong token)
    {
        for (int index = 0; index < _repeatEntries.Length; index++)
        {
            if (_repeatEntries[index].Active && _repeatEntries[index].Token == token)
            {
                _repeatEntries[index] = default;
                return;
            }
        }
    }

    private static long MsToTicks(double milliseconds)
    {
        return (long)(milliseconds * Stopwatch.Frequency / 1000.0);
    }

    private static bool TryResolveKeyCode(in DispatchEvent dispatchEvent, out ushort keyCode)
    {
        if (LinuxKeyCodeMapper.TryMapSemanticCode(dispatchEvent.SemanticAction.PrimaryCode, out keyCode))
        {
            return true;
        }

        return LinuxKeyCodeMapper.TryMapKey(dispatchEvent.VirtualKey, out keyCode);
    }

    private static bool TryResolveModifierKeyCode(in DispatchEvent dispatchEvent, out ushort keyCode)
    {
        DispatchSemanticCode semanticCode =
            dispatchEvent.SemanticAction.Kind == DispatchSemanticKind.KeyChord
                ? dispatchEvent.SemanticAction.SecondaryCode
                : dispatchEvent.SemanticAction.PrimaryCode;
        if (LinuxKeyCodeMapper.TryMapSemanticCode(semanticCode, out keyCode))
        {
            return true;
        }

        return LinuxKeyCodeMapper.TryMapKey(dispatchEvent.VirtualKey, out keyCode);
    }

    private static bool TryResolveMouseButtonCode(in DispatchEvent dispatchEvent, out ushort buttonCode)
    {
        DispatchMouseButton mouseButton =
            dispatchEvent.SemanticAction.MouseButton != DispatchMouseButton.None
                ? dispatchEvent.SemanticAction.MouseButton
                : dispatchEvent.MouseButton;
        return LinuxKeyCodeMapper.TryMapMouseButton(mouseButton, out buttonCode);
    }

    private struct RepeatEntry
    {
        public bool Active;
        public ulong Token;
        public ushort KeyCode;
        public long NextTick;
    }
}
