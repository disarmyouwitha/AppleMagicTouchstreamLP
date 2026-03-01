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
                    HandleKeyTap(dispatchEvent.VirtualKey);
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
                    if (LinuxKeyCodeMapper.TryMapMouseButton(dispatchEvent.MouseButton, out ushort clickButton))
                    {
                        _device.EmitClick(clickButton);
                    }
                    break;
                case DispatchEventKind.MouseButtonDown:
                    if (LinuxKeyCodeMapper.TryMapMouseButton(dispatchEvent.MouseButton, out ushort downButton))
                    {
                        _device.EmitKey(downButton, isDown: true);
                    }
                    break;
                case DispatchEventKind.MouseButtonUp:
                    if (LinuxKeyCodeMapper.TryMapMouseButton(dispatchEvent.MouseButton, out ushort upButton))
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

                if (TrySendKey(entry.VirtualKey, isDown: false))
                {
                    TrySendKey(entry.VirtualKey, isDown: true);
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

            for (int virtualKey = 0; virtualKey < _keyDown.Length; virtualKey++)
            {
                if (_keyDown[virtualKey])
                {
                    TrySendKey((ushort)virtualKey, isDown: false);
                    _keyDown[virtualKey] = false;
                }
            }

            Array.Clear(_modifierRefCounts, 0, _modifierRefCounts.Length);
            Array.Clear(_repeatEntries, 0, _repeatEntries.Length);
            _disposed = true;
        }

        _device.Dispose();
    }

    private void HandleKeyTap(ushort virtualKey)
    {
        if (!LinuxKeyCodeMapper.TryMapKey(virtualKey, out ushort keyCode))
        {
            return;
        }

        _device.EmitKey(keyCode, isDown: true);
        _device.EmitKey(keyCode, isDown: false);
    }

    private void HandleKeyDown(ushort virtualKey, ulong repeatToken, DispatchEventFlags flags, long timestampTicks)
    {
        if (!TrySendKey(virtualKey, isDown: true))
        {
            return;
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

        if ((uint)virtualKey < (uint)_keyDown.Length && !_keyDown[virtualKey])
        {
            return;
        }

        if (TrySendKey(virtualKey, isDown: false) && (uint)virtualKey < (uint)_keyDown.Length)
        {
            _keyDown[virtualKey] = false;
        }
    }

    private void HandleModifierDown(ushort virtualKey)
    {
        if ((uint)virtualKey >= (uint)_modifierRefCounts.Length)
        {
            return;
        }

        _modifierRefCounts[virtualKey]++;
        if (_modifierRefCounts[virtualKey] != 1)
        {
            return;
        }

        if (TrySendKey(virtualKey, isDown: true))
        {
            _keyDown[virtualKey] = true;
        }
    }

    private void HandleModifierUp(ushort virtualKey)
    {
        if ((uint)virtualKey >= (uint)_modifierRefCounts.Length || _modifierRefCounts[virtualKey] <= 0)
        {
            return;
        }

        _modifierRefCounts[virtualKey]--;
        if (_modifierRefCounts[virtualKey] != 0)
        {
            return;
        }

        if (TrySendKey(virtualKey, isDown: false))
        {
            _keyDown[virtualKey] = false;
        }
    }

    private bool TrySendKey(ushort virtualKey, bool isDown)
    {
        if (!LinuxKeyCodeMapper.TryMapKey(virtualKey, out ushort keyCode))
        {
            return false;
        }

        _device.EmitKey(keyCode, isDown);
        return true;
    }

    private void ScheduleRepeat(ulong token, ushort virtualKey, long timestampTicks)
    {
        for (int index = 0; index < _repeatEntries.Length; index++)
        {
            ref RepeatEntry entry = ref _repeatEntries[index];
            if (!entry.Active || entry.Token != token)
            {
                continue;
            }

            entry.VirtualKey = virtualKey;
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
            entry.VirtualKey = virtualKey;
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

    private struct RepeatEntry
    {
        public bool Active;
        public ulong Token;
        public ushort VirtualKey;
        public long NextTick;
    }
}
