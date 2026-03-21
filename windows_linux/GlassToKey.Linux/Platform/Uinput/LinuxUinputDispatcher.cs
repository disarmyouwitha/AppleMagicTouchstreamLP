namespace GlassToKey.Platform.Linux.Uinput;

using System.Diagnostics;
using System.Threading;
using GlassToKey.Platform.Linux.Haptics;
using GlassToKey.Platform.Linux.Models;

public sealed class LinuxUinputDispatcher : IInputDispatcher, IInputDispatcherDiagnosticsProvider, IAutocorrectController, IThreeFingerDragSink
{
    private const int KeyTapMinimumHoldMilliseconds = 20;

    private readonly LinuxUinputDevice _device;
    private readonly LinuxMagicTrackpadActuatorHaptics _haptics;
    private readonly DispatchRepeatProfile _repeatProfile;
    private readonly AutocorrectSession _autocorrect = new();
    private readonly int[] _modifierRefCounts = new int[256];
    private readonly bool[] _keyDown = new bool[256];
    private readonly RepeatEntry[] _repeatEntries = new RepeatEntry[64];
    private readonly TapReleaseEntry[] _tapReleaseEntries = new TapReleaseEntry[32];
    private readonly bool[] _tapHeldDown = new bool[256];
    private readonly object _gate = new();
    private readonly long _keyTapMinimumHoldTicks;
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
        _haptics = new LinuxMagicTrackpadActuatorHaptics();
        _repeatProfile = repeatProfile;
        _keyTapMinimumHoldTicks = MsToTicks(KeyTapMinimumHoldMilliseconds);
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
        bool shouldVibrate = false;

        lock (_gate)
        {
            switch (dispatchEvent.Kind)
            {
                case DispatchEventKind.KeyTap:
                    if (IsShortcutKeyChord(dispatchEvent.SemanticAction))
                    {
                        HandleChordKeyTap(dispatchEvent);
                    }
                    else
                    {
                        HandleKeyTap(dispatchEvent);
                    }
                    break;
                case DispatchEventKind.KeyDown:
                    if (IsShortcutKeyChord(dispatchEvent.SemanticAction))
                    {
                        HandleChordKeyDown(dispatchEvent);
                    }
                    else
                    {
                        HandleKeyDown(dispatchEvent);
                    }
                    break;
                case DispatchEventKind.KeyUp:
                    if (IsShortcutKeyChord(dispatchEvent.SemanticAction))
                    {
                        HandleChordKeyUp(dispatchEvent);
                    }
                    else
                    {
                        HandleKeyUp(dispatchEvent);
                    }
                    break;
                case DispatchEventKind.ModifierDown:
                    HandleModifierDown(dispatchEvent);
                    break;
                case DispatchEventKind.ModifierUp:
                    HandleModifierUp(dispatchEvent);
                    break;
                case DispatchEventKind.MouseButtonClick:
                    _autocorrect.NotifyPointerActivity();
                    if (TryResolveMouseButtonCode(dispatchEvent, out ushort clickButton))
                    {
                        TryEmitClick(clickButton);
                    }
                    break;
                case DispatchEventKind.MouseButtonDown:
                    _autocorrect.NotifyPointerActivity();
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
                case DispatchEventKind.AppLaunch:
                    _autocorrect.NotifyNonWordKey();
                    break;
            }

            shouldVibrate = (dispatchEvent.Flags & DispatchEventFlags.Haptic) != 0;
        }

        if (shouldVibrate)
        {
            _ = _haptics.TryVibrate(dispatchEvent.Side);
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
            ProcessTapReleases(nowTicks);

            for (int index = 0; index < _repeatEntries.Length; index++)
            {
                ref RepeatEntry entry = ref _repeatEntries[index];
                if (!entry.Active || nowTicks < entry.NextTick)
                {
                    continue;
                }

                HandleRepeatKeyDown(entry.KeyCode, entry.SemanticAction);

                entry.NextTick = nowTicks + entry.IntervalTicks;
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

            ReleaseAllHeldKeys();
            _autocorrect.Dispose();
            _haptics.Dispose();
            _disposed = true;
        }

        _device.Dispose();
    }

    public void SetAutocorrectEnabled(bool enabled)
    {
        lock (_gate)
        {
            _autocorrect.SetEnabled(enabled);
        }
    }

    public void ConfigureAutocorrectOptions(AutocorrectOptions options)
    {
        lock (_gate)
        {
            _autocorrect.Configure(options);
        }
    }

    public void ConfigureHaptics(UserSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        _haptics.Configure(settings.HapticsEnabled, settings.HapticsStrength, settings.HapticsMinIntervalMs);
    }

    public void SetHapticRoutes(IReadOnlyList<LinuxTrackpadBinding> bindings)
    {
        ArgumentNullException.ThrowIfNull(bindings);

        string? leftHint = null;
        string? rightHint = null;
        for (int index = 0; index < bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = bindings[index];
            string hint = string.IsNullOrWhiteSpace(binding.Device.StableId)
                ? binding.Device.DeviceNode
                : binding.Device.StableId;
            if (binding.Side == TrackpadSide.Right)
            {
                rightHint = hint;
            }
            else
            {
                leftHint = hint;
            }
        }

        _haptics.SetRoutes(leftHint, rightHint);
    }

    public void WarmupHaptics()
    {
        _haptics.WarmupAsync();
    }

    public void NotifyPointerActivity()
    {
        lock (_gate)
        {
            _autocorrect.NotifyPointerActivity();
        }
    }

    public void MovePointerBy(int deltaX, int deltaY)
    {
        if (_disposed || (deltaX == 0 && deltaY == 0))
        {
            return;
        }

        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            try
            {
                _device.EmitRelative(deltaX, deltaY);
            }
            catch (Exception ex)
            {
                RecordSendFailure(ex);
            }
        }
    }

    public void SetLeftButtonState(bool pressed)
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

            try
            {
                _device.EmitKey(LinuxEvdevCodes.ButtonLeft, pressed);
            }
            catch (Exception ex)
            {
                RecordSendFailure(ex);
            }
        }
    }

    public void ForceAutocorrectReset(string reason)
    {
        lock (_gate)
        {
            _autocorrect.ForceReset(reason);
        }
    }

    public AutocorrectStatusSnapshot GetAutocorrectStatus()
    {
        lock (_gate)
        {
            return _autocorrect.GetStatus();
        }
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
        ProcessAutocorrectKeyInput(dispatchEvent);
        if (!TryResolveKeyCode(dispatchEvent, out ushort keyCode))
        {
            return;
        }

        SendKeyTap(keyCode);
    }

    private void HandleChordKeyTap(in DispatchEvent dispatchEvent)
    {
        ApplyShortcutModifiers(dispatchEvent.SemanticAction);
        try
        {
            HandleKeyTap(dispatchEvent);
        }
        finally
        {
            ReleaseShortcutModifiers(dispatchEvent.SemanticAction);
        }
    }

    private void HandleKeyDown(in DispatchEvent dispatchEvent)
    {
        ProcessAutocorrectKeyInput(dispatchEvent);
        if (!TryResolveKeyCode(dispatchEvent, out ushort keyCode))
        {
            return;
        }

        if ((uint)keyCode < (uint)_keyDown.Length)
        {
            if (_tapHeldDown[keyCode])
            {
                CancelTapRelease(keyCode);
                _tapHeldDown[keyCode] = false;
                _keyDown[keyCode] = true;
            }

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
            ScheduleRepeat(
                dispatchEvent.RepeatToken,
                keyCode,
                dispatchEvent.TimestampTicks,
                dispatchEvent.RepeatProfile,
                dispatchEvent.SemanticAction);
        }
    }

    private void HandleChordKeyDown(in DispatchEvent dispatchEvent)
    {
        ApplyShortcutModifiers(dispatchEvent.SemanticAction);
        HandleKeyDown(dispatchEvent);
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
            if (_tapHeldDown[keyCode])
            {
                CancelTapRelease(keyCode);
                _tapHeldDown[keyCode] = false;
                TrySendKeyCode(keyCode, isDown: false);
            }

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

    private void HandleChordKeyUp(in DispatchEvent dispatchEvent)
    {
        try
        {
            HandleKeyUp(dispatchEvent);
        }
        finally
        {
            ReleaseShortcutModifiers(dispatchEvent.SemanticAction);
        }
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

        if (AutocorrectDispatchKeyAnalyzer.IsShortcutModifier(dispatchEvent.SemanticAction.PrimaryCode))
        {
            _autocorrect.ForceReset("shortcut_modifier_down");
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

    private void ApplyShortcutModifiers(DispatchSemanticAction semanticAction)
    {
        Span<ushort> modifierKeyCodes = stackalloc ushort[12];
        int count = CopyShortcutModifierKeyCodes(semanticAction, modifierKeyCodes);
        for (int index = 0; index < count; index++)
        {
            DispatchSemanticCode semanticCode = DispatchShortcutHelper.ToSemanticCode(ToShortcutModifierFlag(modifierKeyCodes[index], semanticAction));
            HandleModifierDown(new DispatchEvent(
                TimestampTicks: 0,
                Kind: DispatchEventKind.ModifierDown,
                VirtualKey: 0,
                MouseButton: DispatchMouseButton.None,
                RepeatToken: 0,
                Flags: DispatchEventFlags.None,
                Side: TrackpadSide.Left,
                DispatchLabel: string.Empty,
                SemanticAction: new DispatchSemanticAction(
                    DispatchSemanticKind.Modifier,
                    string.Empty,
                    semanticCode)));
        }
    }

    private void ReleaseShortcutModifiers(DispatchSemanticAction semanticAction)
    {
        Span<ushort> modifierKeyCodes = stackalloc ushort[12];
        int count = CopyShortcutModifierKeyCodes(semanticAction, modifierKeyCodes);
        for (int index = count - 1; index >= 0; index--)
        {
            DispatchSemanticCode semanticCode = DispatchShortcutHelper.ToSemanticCode(ToShortcutModifierFlag(modifierKeyCodes[index], semanticAction));
            HandleModifierUp(new DispatchEvent(
                TimestampTicks: 0,
                Kind: DispatchEventKind.ModifierUp,
                VirtualKey: 0,
                MouseButton: DispatchMouseButton.None,
                RepeatToken: 0,
                Flags: DispatchEventFlags.None,
                Side: TrackpadSide.Left,
                DispatchLabel: string.Empty,
                SemanticAction: new DispatchSemanticAction(
                    DispatchSemanticKind.Modifier,
                    string.Empty,
                    semanticCode)));
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

    private void ScheduleRepeat(
        ulong token,
        ushort keyCode,
        long timestampTicks,
        DispatchRepeatProfile repeatProfile,
        DispatchSemanticAction semanticAction)
    {
        long initialDelayTicks = GetRepeatInitialDelayTicks(repeatProfile);
        long intervalTicks = GetRepeatIntervalTicks(repeatProfile);
        for (int index = 0; index < _repeatEntries.Length; index++)
        {
            ref RepeatEntry entry = ref _repeatEntries[index];
            if (!entry.Active || entry.Token != token)
            {
                continue;
            }

            entry.KeyCode = keyCode;
            entry.SemanticAction = semanticAction;
            entry.NextTick = timestampTicks + initialDelayTicks;
            entry.IntervalTicks = intervalTicks;
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
            entry.SemanticAction = semanticAction;
            entry.NextTick = timestampTicks + initialDelayTicks;
            entry.IntervalTicks = intervalTicks;
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

    private void HandleRepeatKeyDown(ushort keyCode, DispatchSemanticAction semanticAction)
    {
        if (keyCode == 0)
        {
            return;
        }

        ProcessAutocorrectKeyInput(new DispatchEvent(
            TimestampTicks: 0,
            Kind: DispatchEventKind.KeyDown,
            VirtualKey: 0,
            MouseButton: DispatchMouseButton.None,
            RepeatToken: 0,
            Flags: DispatchEventFlags.None,
            Side: TrackpadSide.Left,
            DispatchLabel: string.Empty,
            SemanticAction: semanticAction));

        if ((uint)keyCode < (uint)_keyDown.Length && !_keyDown[keyCode])
        {
            return;
        }

        if ((uint)keyCode < (uint)_tapHeldDown.Length && _tapHeldDown[keyCode])
        {
            CancelTapRelease(keyCode);
            _tapHeldDown[keyCode] = false;
        }

        TrySendKeyCode(keyCode, isDown: true);
    }

    private void ProcessTapReleases(long nowTicks)
    {
        for (int index = 0; index < _tapReleaseEntries.Length; index++)
        {
            if (!_tapReleaseEntries[index].Active || nowTicks < _tapReleaseEntries[index].ReleaseTick)
            {
                continue;
            }

            ushort keyCode = _tapReleaseEntries[index].KeyCode;
            int keyIndex = keyCode;
            if ((uint)keyIndex < (uint)_tapHeldDown.Length && _tapHeldDown[keyIndex])
            {
                _tapHeldDown[keyIndex] = false;
                if (_modifierRefCounts[keyIndex] <= 0)
                {
                    TrySendKeyCode(keyCode, isDown: false);
                }
            }

            _tapReleaseEntries[index] = default;
        }
    }

    private void SendKeyTap(ushort keyCode)
    {
        if (keyCode == 0)
        {
            return;
        }

        int keyIndex = keyCode;
        if ((uint)keyIndex >= (uint)_tapHeldDown.Length)
        {
            TrySendKeyCode(keyCode, isDown: true);
            TrySendKeyCode(keyCode, isDown: false);
            return;
        }

        if (_tapHeldDown[keyIndex])
        {
            CancelTapRelease(keyCode);
            _tapHeldDown[keyIndex] = false;
            TrySendKeyCode(keyCode, isDown: false);
        }

        if (!TrySendKeyCode(keyCode, isDown: true))
        {
            return;
        }

        _tapHeldDown[keyIndex] = true;
        ScheduleTapRelease(keyCode, Stopwatch.GetTimestamp() + _keyTapMinimumHoldTicks);
    }

    private void ScheduleTapRelease(ushort keyCode, long releaseTick)
    {
        int firstFree = -1;
        int oldestIndex = 0;
        long oldestTick = long.MaxValue;

        for (int index = 0; index < _tapReleaseEntries.Length; index++)
        {
            if (_tapReleaseEntries[index].Active)
            {
                if (_tapReleaseEntries[index].KeyCode == keyCode)
                {
                    _tapReleaseEntries[index].ReleaseTick = releaseTick;
                    return;
                }

                if (_tapReleaseEntries[index].ReleaseTick < oldestTick)
                {
                    oldestTick = _tapReleaseEntries[index].ReleaseTick;
                    oldestIndex = index;
                }
            }
            else if (firstFree < 0)
            {
                firstFree = index;
            }
        }

        int slot = firstFree >= 0 ? firstFree : oldestIndex;
        if (firstFree < 0)
        {
            ushort replacedKeyCode = _tapReleaseEntries[slot].KeyCode;
            int replacedKeyIndex = replacedKeyCode;
            if ((uint)replacedKeyIndex < (uint)_tapHeldDown.Length && _tapHeldDown[replacedKeyIndex])
            {
                _tapHeldDown[replacedKeyIndex] = false;
                if (_modifierRefCounts[replacedKeyIndex] <= 0)
                {
                    TrySendKeyCode(replacedKeyCode, isDown: false);
                }
            }
        }

        _tapReleaseEntries[slot] = new TapReleaseEntry
        {
            Active = true,
            KeyCode = keyCode,
            ReleaseTick = releaseTick
        };
    }

    private void CancelTapRelease(ushort keyCode)
    {
        for (int index = 0; index < _tapReleaseEntries.Length; index++)
        {
            if (_tapReleaseEntries[index].Active && _tapReleaseEntries[index].KeyCode == keyCode)
            {
                _tapReleaseEntries[index] = default;
                return;
            }
        }
    }

    private void ReleaseAllHeldKeys()
    {
        _autocorrect.ForceReset("release_all");
        Array.Clear(_repeatEntries, 0, _repeatEntries.Length);

        for (int index = 0; index < _tapReleaseEntries.Length; index++)
        {
            _tapReleaseEntries[index] = default;
        }

        for (int keyCode = 0; keyCode < _tapHeldDown.Length; keyCode++)
        {
            if (_tapHeldDown[keyCode] && !_keyDown[keyCode] && _modifierRefCounts[keyCode] <= 0)
            {
                TrySendKeyCode((ushort)keyCode, isDown: false);
            }

            _tapHeldDown[keyCode] = false;
        }

        for (int keyCode = 0; keyCode < _modifierRefCounts.Length; keyCode++)
        {
            if (_modifierRefCounts[keyCode] > 0 || _keyDown[keyCode])
            {
                TrySendKeyCode((ushort)keyCode, isDown: false);
                _modifierRefCounts[keyCode] = 0;
                _keyDown[keyCode] = false;
            }
        }
    }

    private void ProcessAutocorrectKeyInput(in DispatchEvent dispatchEvent)
    {
        if (!_autocorrect.GetStatus().Enabled)
        {
            _autocorrect.ForceReset("disabled");
            return;
        }

        if (HasShortcutModifierDown())
        {
            _autocorrect.NotifyShortcutBypass();
            return;
        }

        if (AutocorrectDispatchKeyAnalyzer.IsBackspace(dispatchEvent))
        {
            _autocorrect.TrackBackspace();
            return;
        }

        if (AutocorrectDispatchKeyAnalyzer.TryResolveLetter(dispatchEvent, IsShiftModifierDown(), out char letter))
        {
            _autocorrect.TrackLetter(letter);
            return;
        }

        if (AutocorrectDispatchKeyAnalyzer.IsWordBoundary(dispatchEvent))
        {
            ApplyAutocorrectForWordBoundary();
            return;
        }

        _autocorrect.NotifyNonWordKey();
    }

    private void ApplyAutocorrectForWordBoundary()
    {
        if (!_autocorrect.TryCompleteWord(out AutocorrectReplacement replacement) ||
            !LinuxKeyCodeMapper.TryMapSemanticCode(DispatchSemanticCode.Backspace, out ushort backspaceCode))
        {
            return;
        }

        for (int index = 0; index < replacement.BackspaceCount; index++)
        {
            TryEmitKey(backspaceCode, isDown: true);
            TryEmitKey(backspaceCode, isDown: false);
        }

        for (int index = 0; index < replacement.ReplacementText.Length; index++)
        {
            if (!AutocorrectDispatchKeyAnalyzer.TryResolveReplacementLetter(
                    replacement.ReplacementText[index],
                    out DispatchSemanticCode semanticCode,
                    out bool requiresShift) ||
                !LinuxKeyCodeMapper.TryMapSemanticCode(semanticCode, out ushort keyCode))
            {
                continue;
            }

            bool shiftAlreadyDown = IsShiftModifierDown();
            if (requiresShift &&
                !shiftAlreadyDown &&
                LinuxKeyCodeMapper.TryMapSemanticCode(DispatchSemanticCode.Shift, out ushort shiftCode))
            {
                TryEmitKey(shiftCode, isDown: true);
                TryEmitKey(keyCode, isDown: true);
                TryEmitKey(keyCode, isDown: false);
                TryEmitKey(shiftCode, isDown: false);
                continue;
            }

            TryEmitKey(keyCode, isDown: true);
            TryEmitKey(keyCode, isDown: false);
        }
    }

    private bool HasShortcutModifierDown()
    {
        return IsModifierDown(DispatchSemanticCode.Ctrl) ||
               IsModifierDown(DispatchSemanticCode.LeftCtrl) ||
               IsModifierDown(DispatchSemanticCode.RightCtrl) ||
               IsModifierDown(DispatchSemanticCode.Alt) ||
               IsModifierDown(DispatchSemanticCode.LeftAlt) ||
               IsModifierDown(DispatchSemanticCode.RightAlt) ||
               IsModifierDown(DispatchSemanticCode.Meta) ||
               IsModifierDown(DispatchSemanticCode.LeftMeta) ||
               IsModifierDown(DispatchSemanticCode.RightMeta);
    }

    private bool IsShiftModifierDown()
    {
        return IsModifierDown(DispatchSemanticCode.Shift) ||
               IsModifierDown(DispatchSemanticCode.LeftShift) ||
               IsModifierDown(DispatchSemanticCode.RightShift);
    }

    private bool IsModifierDown(DispatchSemanticCode semanticCode)
    {
        if (!LinuxKeyCodeMapper.TryMapSemanticCode(semanticCode, out ushort keyCode) ||
            (uint)keyCode >= (uint)_modifierRefCounts.Length)
        {
            return false;
        }

        return _modifierRefCounts[keyCode] > 0;
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

    private static long MsToTicks(double milliseconds)
    {
        if (milliseconds <= 0)
        {
            return 0;
        }

        return (long)Math.Round(milliseconds * Stopwatch.Frequency / 1000.0);
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

    private long GetRepeatInitialDelayTicks(DispatchRepeatProfile repeatProfile)
    {
        long ticks = repeatProfile.GetInitialDelayTicks();
        return ticks > 0 ? ticks : _repeatInitialDelayTicks;
    }

    private long GetRepeatIntervalTicks(DispatchRepeatProfile repeatProfile)
    {
        long ticks = repeatProfile.GetIntervalTicks();
        return ticks > 0 ? ticks : _repeatIntervalTicks;
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
        DispatchSemanticCode semanticCode = dispatchEvent.SemanticAction.PrimaryCode != DispatchSemanticCode.None
            ? dispatchEvent.SemanticAction.PrimaryCode
            : dispatchEvent.SemanticAction.SecondaryCode;
        if (LinuxKeyCodeMapper.TryMapSemanticCode(semanticCode, out keyCode))
        {
            return true;
        }

        return LinuxKeyCodeMapper.TryMapKey(dispatchEvent.VirtualKey, out keyCode);
    }

    private static bool IsShortcutKeyChord(DispatchSemanticAction semanticAction)
    {
        if (semanticAction.Kind != DispatchSemanticKind.KeyChord)
        {
            return false;
        }

        return semanticAction.Modifiers != DispatchModifierFlags.None ||
            semanticAction.SecondaryCode != DispatchSemanticCode.None;
    }

    private static int CopyShortcutModifierKeyCodes(DispatchSemanticAction semanticAction, Span<ushort> destination)
    {
        DispatchModifierFlags modifiers = semanticAction.Modifiers;
        if (modifiers == DispatchModifierFlags.None && semanticAction.SecondaryCode != DispatchSemanticCode.None)
        {
            modifiers = DispatchShortcutHelper.ToModifierFlag(semanticAction.SecondaryCode);
        }

        Span<DispatchSemanticCode> modifierCodes = stackalloc DispatchSemanticCode[12];
        int available = DispatchShortcutHelper.CopyModifierSemanticCodes(modifiers, modifierCodes);
        int count = 0;
        int limit = Math.Min(available, modifierCodes.Length);
        for (int index = 0; index < limit; index++)
        {
            if (!LinuxKeyCodeMapper.TryMapSemanticCode(modifierCodes[index], out ushort keyCode))
            {
                continue;
            }

            destination[count++] = keyCode;
        }

        if (count == 0 &&
            semanticAction.SecondaryCode != DispatchSemanticCode.None &&
            LinuxKeyCodeMapper.TryMapSemanticCode(semanticAction.SecondaryCode, out ushort legacyKeyCode))
        {
            destination[count++] = legacyKeyCode;
        }

        return count;
    }

    private static DispatchModifierFlags ToShortcutModifierFlag(ushort keyCode, DispatchSemanticAction semanticAction)
    {
        DispatchModifierFlags modifiers = semanticAction.Modifiers;
        if (modifiers == DispatchModifierFlags.None)
        {
            return DispatchShortcutHelper.ToModifierFlag(semanticAction.SecondaryCode);
        }

        Span<DispatchSemanticCode> modifierCodes = stackalloc DispatchSemanticCode[12];
        int count = DispatchShortcutHelper.CopyModifierSemanticCodes(modifiers, modifierCodes);
        int limit = Math.Min(count, modifierCodes.Length);
        for (int index = 0; index < limit; index++)
        {
            if (LinuxKeyCodeMapper.TryMapSemanticCode(modifierCodes[index], out ushort candidate) &&
                candidate == keyCode)
            {
                return DispatchShortcutHelper.ToModifierFlag(modifierCodes[index]);
            }
        }

        return DispatchShortcutHelper.ToModifierFlag(semanticAction.SecondaryCode);
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
        public DispatchSemanticAction SemanticAction;
        public long NextTick;
        public long IntervalTicks;
    }

    private struct TapReleaseEntry
    {
        public bool Active;
        public ushort KeyCode;
        public long ReleaseTick;
    }
}
