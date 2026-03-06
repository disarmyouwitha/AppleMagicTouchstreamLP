namespace GlassToKey.Platform.Linux.Uinput;

using System.Diagnostics;
using System.Threading;

public sealed class LinuxUinputDispatcher : IInputDispatcher, IInputDispatcherDiagnosticsProvider
{
    private readonly LinuxUinputDevice _device;
    private readonly DispatchRepeatProfile _repeatProfile;
    private readonly int[] _modifierRefCounts = new int[256];
    private readonly bool[] _keyDown = new bool[256];
    private readonly RepeatEntry[] _repeatEntries = new RepeatEntry[64];
    private readonly object _gate = new();
    private readonly long _repeatInitialDelayTicks;
    private readonly long _repeatIntervalTicks;
    private long _dispatchCalls;
    private long _tickCalls;
    private long _sendFailures;
    private long _lastDispatchTicks;
    private long _lastTickTicks;
    private string _lastErrorMessage = string.Empty;
    private bool _disposed;

    public LinuxUinputDispatcher()
        : this(new LinuxUinputDevice())
    {
    }

    internal LinuxUinputDispatcher(LinuxUinputDevice device)
        : this(device, DispatchRepeatProfile.Default)
    {
    }

    internal LinuxUinputDispatcher(LinuxUinputDevice device, DispatchRepeatProfile repeatProfile)
    {
        _device = device;
        _repeatProfile = repeatProfile;
        _repeatInitialDelayTicks = _repeatProfile.GetInitialDelayTicks();
        _repeatIntervalTicks = _repeatProfile.GetIntervalTicks();
    }

    public void Dispatch(in DispatchEvent dispatchEvent)
    {
        if (_disposed)
        {
            return;
        }

        long nowTicks = Stopwatch.GetTimestamp();
        Interlocked.Increment(ref _dispatchCalls);
        Volatile.Write(ref _lastDispatchTicks, nowTicks);

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
                        TryEmitClick(clickButton);
                    }
                    break;
                case DispatchEventKind.MouseButtonDown:
                    if (TryResolveMouseButtonCode(dispatchEvent, out ushort downButton))
                    {
                        TryEmitKey(downButton, isDown: true);
                    }
                    break;
                case DispatchEventKind.MouseButtonUp:
                    if (TryResolveMouseButtonCode(dispatchEvent, out ushort upButton))
                    {
                        TryEmitKey(upButton, isDown: false);
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

        Interlocked.Increment(ref _tickCalls);
        Volatile.Write(ref _lastTickTicks, nowTicks);

        lock (_gate)
        {
            for (int index = 0; index < _repeatEntries.Length; index++)
            {
                ref RepeatEntry entry = ref _repeatEntries[index];
                if (!entry.Active || nowTicks < entry.NextTick)
                {
                    continue;
                }

                HandleRepeatKeyDown(entry.KeyCode);

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

    public bool TryGetDiagnostics(out InputDispatcherDiagnostics diagnostics)
    {
        if (_disposed)
        {
            diagnostics = new InputDispatcherDiagnostics(
                DispatchCalls: Interlocked.Read(ref _dispatchCalls),
                TickCalls: Interlocked.Read(ref _tickCalls),
                SendFailures: Interlocked.Read(ref _sendFailures),
                ActiveRepeats: 0,
                KeysDown: 0,
                ActiveModifiers: 0,
                LastDispatchTicks: Volatile.Read(ref _lastDispatchTicks),
                LastTickTicks: Volatile.Read(ref _lastTickTicks),
                LastErrorMessage: Volatile.Read(ref _lastErrorMessage) ?? string.Empty);
            return true;
        }

        lock (_gate)
        {
            diagnostics = new InputDispatcherDiagnostics(
                DispatchCalls: Interlocked.Read(ref _dispatchCalls),
                TickCalls: Interlocked.Read(ref _tickCalls),
                SendFailures: Interlocked.Read(ref _sendFailures),
                ActiveRepeats: CountActiveRepeatsLocked(),
                KeysDown: CountKeysDownLocked(),
                ActiveModifiers: CountActiveModifiersLocked(),
                LastDispatchTicks: Volatile.Read(ref _lastDispatchTicks),
                LastTickTicks: Volatile.Read(ref _lastTickTicks),
                LastErrorMessage: Volatile.Read(ref _lastErrorMessage) ?? string.Empty);
            return true;
        }
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

        return TryEmitKey(keyCode, isDown);
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

    private void HandleRepeatKeyDown(ushort keyCode)
    {
        if (keyCode == 0)
        {
            return;
        }

        if ((uint)keyCode < (uint)_keyDown.Length && !_keyDown[keyCode])
        {
            return;
        }

        TrySendKeyCode(keyCode, isDown: true);
    }

    private bool TryEmitKey(ushort keyCode, bool isDown)
    {
        try
        {
            _device.EmitKey(keyCode, isDown);
            return true;
        }
        catch (Exception ex)
        {
            RecordSendFailure(ex);
            return false;
        }
    }

    private bool TryEmitClick(ushort buttonCode)
    {
        try
        {
            _device.EmitClick(buttonCode);
            return true;
        }
        catch (Exception ex)
        {
            RecordSendFailure(ex);
            return false;
        }
    }

    private void RecordSendFailure(Exception ex)
    {
        Interlocked.Increment(ref _sendFailures);
        Volatile.Write(ref _lastErrorMessage, $"{ex.GetType().Name}: {ex.Message}");
    }

    private int CountActiveRepeatsLocked()
    {
        int count = 0;
        for (int index = 0; index < _repeatEntries.Length; index++)
        {
            if (_repeatEntries[index].Active)
            {
                count++;
            }
        }

        return count;
    }

    private int CountKeysDownLocked()
    {
        int count = 0;
        for (int index = 0; index < _keyDown.Length; index++)
        {
            if (_keyDown[index])
            {
                count++;
            }
        }

        return count;
    }

    private int CountActiveModifiersLocked()
    {
        int count = 0;
        for (int index = 0; index < _modifierRefCounts.Length; index++)
        {
            if (_modifierRefCounts[index] > 0)
            {
                count++;
            }
        }

        return count;
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
