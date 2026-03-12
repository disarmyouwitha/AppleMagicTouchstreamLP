using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Threading;

namespace GlassToKey;

internal sealed class SendInputDispatcher : IInputDispatcher, IAutocorrectController, IThreeFingerDragSink
{
    private const uint InputMouse = 0;
    private const uint InputKeyboard = 1;

    private const uint KeyeventfExtendedkey = 0x0001;
    private const uint KeyeventfKeyup = 0x0002;
    private const uint KeyeventfScancode = 0x0008;
    private const uint MouseeventfMove = 0x0001;
    private const uint MouseeventfLeftdown = 0x0002;
    private const uint MouseeventfLeftup = 0x0004;
    private const uint MouseeventfRightdown = 0x0008;
    private const uint MouseeventfRightup = 0x0010;
    private const uint MouseeventfMiddledown = 0x0020;
    private const uint MouseeventfMiddleup = 0x0040;
    private const uint MapvkVkToVscEx = 0x04;
    private const ushort VirtualKeyBackspace = 0x08;
    private const ushort VirtualKeyShift = 0x10;
    private const ushort VirtualKeyControl = 0x11;
    private const ushort VirtualKeyMenu = 0x12;
    private const ushort VirtualKeyLeftWindows = 0x5B;
    private const ushort VirtualKeyRightWindows = 0x5C;
    private const ushort VirtualKeyLeftShift = 0xA0;
    private const ushort VirtualKeyRightShift = 0xA1;
    private const ushort VirtualKeyLeftControl = 0xA2;
    private const ushort VirtualKeyRightControl = 0xA3;
    private const ushort VirtualKeyLeftMenu = 0xA4;
    private const ushort VirtualKeyRightMenu = 0xA5;
    private const int KeyTapMinimumHoldMilliseconds = 20;

    private readonly int[] _modifierRefCounts = new int[256];
    private readonly bool[] _keyDown = new bool[256];
    private readonly RepeatEntry[] _repeatEntries = new RepeatEntry[64];
    private readonly TapReleaseEntry[] _tapReleaseEntries = new TapReleaseEntry[32];
    private readonly bool[] _tapHeldDown = new bool[256];
    private readonly Input[] _singleInput = new Input[1];
    private readonly Input[] _dualInput = new Input[2];
    private readonly AutocorrectSession _autocorrect = new();
    private readonly Dictionary<uint, string> _processNameCache = new();
    private readonly long _keyTapMinimumHoldTicks;
    private readonly long _repeatInitialDelayTicks;
    private readonly long _repeatIntervalTicks;
    private int _autocorrectPointerActivityPending;
    private bool _suppressPhysicalOutput;
    private bool _disposed;

    public SendInputDispatcher()
    {
        _keyTapMinimumHoldTicks = MsToTicks(KeyTapMinimumHoldMilliseconds);
        _repeatInitialDelayTicks = MsToTicks(275);
        _repeatIntervalTicks = MsToTicks(33);
    }

    public void SetAutocorrectEnabled(bool enabled)
    {
        bool wasEnabled = _autocorrect.GetStatus().Enabled;
        _autocorrect.SetEnabled(enabled);
        if (!enabled && wasEnabled)
        {
            ManagedMemoryCompactor.QueueCompaction();
        }
    }

    public void ConfigureAutocorrectOptions(AutocorrectOptions options)
    {
        _autocorrect.Configure(options);
    }

    internal void SetPhysicalOutputSuppressed(bool suppressed)
    {
        _suppressPhysicalOutput = suppressed;
    }

    public void ForceAutocorrectReset(string reason)
    {
        _autocorrect.ForceReset(reason);
    }

    public AutocorrectStatusSnapshot GetAutocorrectStatus()
    {
        return _autocorrect.GetStatus();
    }

    public void NotifyPointerActivity()
    {
        Interlocked.Exchange(ref _autocorrectPointerActivityPending, 1);
    }

    public void MovePointerBy(int deltaX, int deltaY)
    {
        if (_suppressPhysicalOutput || (deltaX == 0 && deltaY == 0))
        {
            return;
        }

        _singleInput[0] = CreateMouseInput(MouseeventfMove, deltaX, deltaY);
        SendInput(1, _singleInput, Marshal.SizeOf<Input>());
    }

    public void SetLeftButtonState(bool pressed)
    {
        if (pressed)
        {
            SendMouseButtonDown(DispatchMouseButton.Left);
        }
        else
        {
            SendMouseButtonUp(DispatchMouseButton.Left);
        }
    }

    public void Dispatch(in DispatchEvent dispatchEvent)
    {
        if (_disposed)
        {
            return;
        }

        ConsumePendingPointerActivity();

        switch (dispatchEvent.Kind)
        {
            case DispatchEventKind.AppLaunch:
                HandleAppLaunch(dispatchEvent);
                break;
            case DispatchEventKind.KeyTap:
                if (!TryResolveKeyVirtualKey(dispatchEvent, out ushort keyTapVirtualKey))
                {
                    break;
                }

                if (!_suppressPhysicalOutput && TryDispatchSystemAction(keyTapVirtualKey))
                {
                    break;
                }

                if (IsShortcutKeyChord(dispatchEvent.SemanticAction))
                {
                    HandleChordKeyTap(keyTapVirtualKey, dispatchEvent);
                }
                else
                {
                    HandleKeyTap(keyTapVirtualKey, dispatchEvent);
                }
                break;
            case DispatchEventKind.KeyDown:
                if (!TryResolveKeyVirtualKey(dispatchEvent, out ushort keyDownVirtualKey))
                {
                    break;
                }

                if (IsShortcutKeyChord(dispatchEvent.SemanticAction))
                {
                    HandleChordKeyDown(keyDownVirtualKey, dispatchEvent);
                }
                else
                {
                    HandleKeyDownAutocorrect(dispatchEvent);
                    HandleKeyDown(
                        keyDownVirtualKey,
                        dispatchEvent.RepeatToken,
                        dispatchEvent.Flags,
                        dispatchEvent.TimestampTicks,
                        dispatchEvent.SemanticAction);
                }
                break;
            case DispatchEventKind.KeyUp:
                if (TryResolveKeyVirtualKey(dispatchEvent, out ushort keyUpVirtualKey))
                {
                    if (IsShortcutKeyChord(dispatchEvent.SemanticAction))
                    {
                        HandleChordKeyUp(keyUpVirtualKey, dispatchEvent.RepeatToken, dispatchEvent.SemanticAction);
                    }
                    else
                    {
                        HandleKeyUp(keyUpVirtualKey, dispatchEvent.RepeatToken);
                    }
                }
                break;
            case DispatchEventKind.ModifierDown:
                if (TryResolveModifierVirtualKey(dispatchEvent, out ushort modifierDownVirtualKey))
                {
                    HandleModifierDown(modifierDownVirtualKey);
                }
                break;
            case DispatchEventKind.ModifierUp:
                if (TryResolveModifierVirtualKey(dispatchEvent, out ushort modifierUpVirtualKey))
                {
                    HandleModifierUp(modifierUpVirtualKey);
                }
                break;
            case DispatchEventKind.MouseButtonClick:
                _autocorrect.NotifyPointerActivity();
                SendMouseButtonClick(dispatchEvent.MouseButton);
                break;
            case DispatchEventKind.MouseButtonDown:
                _autocorrect.NotifyPointerActivity();
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
            _ = MagicTrackpadActuatorHaptics.TryVibrate(dispatchEvent.Side);
        }
    }

    private void HandleKeyTap(ushort virtualKey, in DispatchEvent dispatchEvent)
    {
        ProcessAutocorrectKeyInput(dispatchEvent);
        SendKeyTap(virtualKey);
    }

    private void HandleAppLaunch(in DispatchEvent dispatchEvent)
    {
        _autocorrect.NotifyNonWordKey();
        if (_suppressPhysicalOutput ||
            !AppLaunchActionHelper.TryParse(dispatchEvent.SemanticAction.Label, out AppLaunchActionSpec spec))
        {
            return;
        }

        try
        {
            using Process? process = Process.Start(new ProcessStartInfo
            {
                FileName = spec.FileName,
                Arguments = spec.Arguments,
                UseShellExecute = true
            });
        }
        catch
        {
            // Ignore launch failures to keep the dispatch path best-effort.
        }
    }

    private void HandleChordKeyTap(ushort virtualKey, in DispatchEvent dispatchEvent)
    {
        ApplyShortcutModifiers(dispatchEvent.SemanticAction);
        try
        {
            ProcessAutocorrectKeyInput(dispatchEvent);
            SendKeyTap(virtualKey);
        }
        finally
        {
            ReleaseShortcutModifiers(dispatchEvent.SemanticAction);
        }
    }

    private void HandleKeyDownAutocorrect(in DispatchEvent dispatchEvent)
    {
        ProcessAutocorrectKeyInput(dispatchEvent);
    }

    private void ProcessAutocorrectKeyInput(in DispatchEvent dispatchEvent)
    {
        AutocorrectStatusSnapshot status = _autocorrect.GetStatus();
        if (!status.Enabled)
        {
            _autocorrect.ForceReset("disabled");
            return;
        }

        RefreshAutocorrectForegroundProcess();

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

    public void Tick(long nowTicks)
    {
        if (_disposed)
        {
            return;
        }

        ConsumePendingPointerActivity();
        ProcessTapReleases(nowTicks);

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

            HandleRepeatKeyDown(_repeatEntries[i].VirtualKey, _repeatEntries[i].SemanticAction);
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
        _autocorrect.Dispose();
        ReleaseAllHeldKeys();
    }

    private void HandleKeyDown(
        ushort virtualKey,
        ulong repeatToken,
        DispatchEventFlags flags,
        long timestampTicks,
        DispatchSemanticAction semanticAction)
    {
        if (virtualKey == 0)
        {
            return;
        }

        int vk = virtualKey;
        if ((uint)vk < (uint)_keyDown.Length)
        {
            if (_tapHeldDown[vk])
            {
                CancelTapRelease(virtualKey);
                _tapHeldDown[vk] = false;
                _keyDown[vk] = true;
            }

            if (!_keyDown[vk])
            {
                SendKeyboard(virtualKey, keyUp: false);
                _keyDown[vk] = true;
            }
        }

        if ((flags & DispatchEventFlags.Repeatable) != 0 && repeatToken != 0)
        {
            ScheduleRepeat(repeatToken, virtualKey, timestampTicks, semanticAction);
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
        if ((uint)vk < (uint)_tapHeldDown.Length && _tapHeldDown[vk])
        {
            CancelTapRelease(virtualKey);
            _tapHeldDown[vk] = false;
            SendKeyboard(virtualKey, keyUp: true);
        }

        if ((uint)vk < (uint)_keyDown.Length && _keyDown[vk])
        {
            SendKeyboard(virtualKey, keyUp: true);
            _keyDown[vk] = false;
        }
    }

    private void HandleChordKeyDown(ushort virtualKey, in DispatchEvent dispatchEvent)
    {
        ApplyShortcutModifiers(dispatchEvent.SemanticAction);
        HandleKeyDownAutocorrect(dispatchEvent);
        HandleKeyDown(
            virtualKey,
            dispatchEvent.RepeatToken,
            dispatchEvent.Flags,
            dispatchEvent.TimestampTicks,
            dispatchEvent.SemanticAction);
    }

    private void HandleChordKeyUp(ushort virtualKey, ulong repeatToken, DispatchSemanticAction semanticAction)
    {
        try
        {
            HandleKeyUp(virtualKey, repeatToken);
        }
        finally
        {
            ReleaseShortcutModifiers(semanticAction);
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

        if (virtualKey is
            VirtualKeyControl or VirtualKeyLeftControl or VirtualKeyRightControl or
            VirtualKeyMenu or VirtualKeyLeftMenu or VirtualKeyRightMenu or
            VirtualKeyLeftWindows or VirtualKeyRightWindows)
        {
            _autocorrect.ForceReset("shortcut_modifier_down");
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

    private void ApplyShortcutModifiers(DispatchSemanticAction semanticAction)
    {
        Span<ushort> modifierVirtualKeys = stackalloc ushort[12];
        int count = CopyShortcutModifierVirtualKeys(semanticAction, modifierVirtualKeys);
        for (int index = 0; index < count; index++)
        {
            HandleModifierDown(modifierVirtualKeys[index]);
        }
    }

    private void ReleaseShortcutModifiers(DispatchSemanticAction semanticAction)
    {
        Span<ushort> modifierVirtualKeys = stackalloc ushort[12];
        int count = CopyShortcutModifierVirtualKeys(semanticAction, modifierVirtualKeys);
        for (int index = count - 1; index >= 0; index--)
        {
            HandleModifierUp(modifierVirtualKeys[index]);
        }
    }

    private void ScheduleRepeat(ulong token, ushort virtualKey, long timestampTicks, DispatchSemanticAction semanticAction)
    {
        for (int i = 0; i < _repeatEntries.Length; i++)
        {
            if (_repeatEntries[i].Active && _repeatEntries[i].Token == token)
            {
                _repeatEntries[i].VirtualKey = virtualKey;
                _repeatEntries[i].SemanticAction = semanticAction;
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
                SemanticAction = semanticAction,
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
        _autocorrect.ForceReset("release_all");
        for (int i = 0; i < _repeatEntries.Length; i++)
        {
            _repeatEntries[i] = default;
        }

        for (int i = 0; i < _tapReleaseEntries.Length; i++)
        {
            _tapReleaseEntries[i] = default;
        }

        for (int vk = 0; vk < _tapHeldDown.Length; vk++)
        {
            if (_tapHeldDown[vk] && !_keyDown[vk] && _modifierRefCounts[vk] <= 0)
            {
                SendKeyboard((ushort)vk, keyUp: true);
            }

            _tapHeldDown[vk] = false;
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
        if (virtualKey == 0 || _suppressPhysicalOutput)
        {
            return;
        }

        int vk = virtualKey;
        if ((uint)vk >= (uint)_tapHeldDown.Length)
        {
            _dualInput[0] = CreateKeyboardInput(virtualKey, keyUp: false);
            _dualInput[1] = CreateKeyboardInput(virtualKey, keyUp: true);
            SendInput(2, _dualInput, Marshal.SizeOf<Input>());
            return;
        }

        if (_tapHeldDown[vk])
        {
            CancelTapRelease(virtualKey);
            _tapHeldDown[vk] = false;
            SendKeyboard(virtualKey, keyUp: true);
        }

        SendKeyboard(virtualKey, keyUp: false);
        _tapHeldDown[vk] = true;
        ScheduleTapRelease(virtualKey, Stopwatch.GetTimestamp() + _keyTapMinimumHoldTicks);
    }

    private void HandleRepeatKeyDown(ushort virtualKey, DispatchSemanticAction semanticAction)
    {
        if (virtualKey == 0)
        {
            return;
        }

        // Keep autocorrect/key history behavior aligned with repeated character input.
        HandleKeyDownAutocorrect(new DispatchEvent(
            TimestampTicks: 0,
            Kind: DispatchEventKind.KeyDown,
            VirtualKey: virtualKey,
            MouseButton: DispatchMouseButton.None,
            RepeatToken: 0,
            Flags: DispatchEventFlags.None,
            Side: TrackpadSide.Left,
            DispatchLabel: string.Empty,
            SemanticAction: semanticAction));

        int vk = virtualKey;
        if ((uint)vk < (uint)_tapHeldDown.Length && _tapHeldDown[vk])
        {
            CancelTapRelease(virtualKey);
            _tapHeldDown[vk] = false;
        }

        // Emit typematic-style repeat while preserving the held-down state until explicit KeyUp.
        SendKeyboard(virtualKey, keyUp: false);
        if ((uint)vk < (uint)_keyDown.Length)
        {
            _keyDown[vk] = true;
        }
    }

    private void ProcessTapReleases(long nowTicks)
    {
        for (int i = 0; i < _tapReleaseEntries.Length; i++)
        {
            if (!_tapReleaseEntries[i].Active || nowTicks < _tapReleaseEntries[i].ReleaseTick)
            {
                continue;
            }

            ushort virtualKey = _tapReleaseEntries[i].VirtualKey;
            int vk = virtualKey;
            if ((uint)vk < (uint)_tapHeldDown.Length && _tapHeldDown[vk])
            {
                _tapHeldDown[vk] = false;
                if (_modifierRefCounts[vk] <= 0)
                {
                    SendKeyboard(virtualKey, keyUp: true);
                }
            }

            _tapReleaseEntries[i] = default;
        }
    }

    private void ScheduleTapRelease(ushort virtualKey, long releaseTick)
    {
        int firstFree = -1;
        int oldestIndex = 0;
        long oldestTick = long.MaxValue;

        for (int i = 0; i < _tapReleaseEntries.Length; i++)
        {
            if (_tapReleaseEntries[i].Active)
            {
                if (_tapReleaseEntries[i].VirtualKey == virtualKey)
                {
                    _tapReleaseEntries[i].ReleaseTick = releaseTick;
                    return;
                }

                if (_tapReleaseEntries[i].ReleaseTick < oldestTick)
                {
                    oldestTick = _tapReleaseEntries[i].ReleaseTick;
                    oldestIndex = i;
                }
            }
            else if (firstFree < 0)
            {
                firstFree = i;
            }
        }

        int slot = firstFree >= 0 ? firstFree : oldestIndex;
        if (firstFree < 0)
        {
            ushort replacedVirtualKey = _tapReleaseEntries[slot].VirtualKey;
            int replacedVk = replacedVirtualKey;
            if ((uint)replacedVk < (uint)_tapHeldDown.Length && _tapHeldDown[replacedVk])
            {
                _tapHeldDown[replacedVk] = false;
                if (_modifierRefCounts[replacedVk] <= 0)
                {
                    SendKeyboard(replacedVirtualKey, keyUp: true);
                }
            }
        }

        _tapReleaseEntries[slot] = new TapReleaseEntry
        {
            Active = true,
            VirtualKey = virtualKey,
            ReleaseTick = releaseTick
        };
    }

    private void CancelTapRelease(ushort virtualKey)
    {
        for (int i = 0; i < _tapReleaseEntries.Length; i++)
        {
            if (_tapReleaseEntries[i].Active && _tapReleaseEntries[i].VirtualKey == virtualKey)
            {
                _tapReleaseEntries[i] = default;
                return;
            }
        }
    }

    private void SendKeyboard(ushort virtualKey, bool keyUp)
    {
        if (_suppressPhysicalOutput)
        {
            return;
        }

        _singleInput[0] = CreateKeyboardInput(virtualKey, keyUp);
        SendInput(1, _singleInput, Marshal.SizeOf<Input>());
    }

    private static Input CreateKeyboardInput(ushort virtualKey, bool keyUp)
    {
        uint flags = keyUp ? KeyeventfKeyup : 0;
        ushort sendVirtualKey = virtualKey;
        ushort scanCode = 0;
        if (TryResolveScanCode(virtualKey, out ushort mappedScanCode, out bool extended))
        {
            sendVirtualKey = 0;
            scanCode = mappedScanCode;
            flags |= KeyeventfScancode;
            if (extended)
            {
                flags |= KeyeventfExtendedkey;
            }
        }

        return new Input
        {
            Type = InputKeyboard,
            Union = new InputUnion
            {
                Keyboard = new KeyboardInput
                {
                    VirtualKey = sendVirtualKey,
                    ScanCode = scanCode,
                    Flags = flags,
                    Time = 0,
                    ExtraInfo = IntPtr.Zero
                }
            }
        };
    }

    private static bool TryResolveScanCode(ushort virtualKey, out ushort scanCode, out bool extended)
    {
        uint mapped = MapVirtualKey(virtualKey, MapvkVkToVscEx);
        scanCode = (ushort)(mapped & 0xFF);
        if (scanCode == 0)
        {
            extended = false;
            return false;
        }

        uint prefix = (mapped >> 8) & 0xFF;
        extended = prefix is 0xE0 or 0xE1;
        return true;
    }

    private void SendMouseButtonClick(DispatchMouseButton button)
    {
        if (_suppressPhysicalOutput)
        {
            return;
        }

        (uint down, uint up) = ResolveMouseFlags(button);
        if (down == 0 || up == 0)
        {
            return;
        }

        _dualInput[0] = CreateMouseInput(down, 0, 0);
        _dualInput[1] = CreateMouseInput(up, 0, 0);
        SendInput(2, _dualInput, Marshal.SizeOf<Input>());
    }

    private void SendMouseButtonDown(DispatchMouseButton button)
    {
        if (_suppressPhysicalOutput)
        {
            return;
        }

        (uint down, _) = ResolveMouseFlags(button);
        if (down == 0)
        {
            return;
        }

        _singleInput[0] = CreateMouseInput(down, 0, 0);
        SendInput(1, _singleInput, Marshal.SizeOf<Input>());
    }

    private void SendMouseButtonUp(DispatchMouseButton button)
    {
        if (_suppressPhysicalOutput)
        {
            return;
        }

        (_, uint up) = ResolveMouseFlags(button);
        if (up == 0)
        {
            return;
        }

        _singleInput[0] = CreateMouseInput(up, 0, 0);
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

    private static Input CreateMouseInput(uint flags, int deltaX, int deltaY)
    {
        return new Input
        {
            Type = InputMouse,
            Union = new InputUnion
            {
                Mouse = new MouseInput
                {
                    DeltaX = deltaX,
                    DeltaY = deltaY,
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

    private static bool TryResolveKeyVirtualKey(in DispatchEvent dispatchEvent, out ushort virtualKey)
    {
        if (WindowsVirtualKeyMapper.TryMapSemanticCode(dispatchEvent.SemanticAction.PrimaryCode, out virtualKey))
        {
            return true;
        }

        virtualKey = dispatchEvent.VirtualKey;
        return virtualKey != 0;
    }

    private static bool TryResolveModifierVirtualKey(in DispatchEvent dispatchEvent, out ushort virtualKey)
    {
        DispatchSemanticCode semanticCode = dispatchEvent.SemanticAction.PrimaryCode != DispatchSemanticCode.None
            ? dispatchEvent.SemanticAction.PrimaryCode
            : dispatchEvent.SemanticAction.SecondaryCode;
        if (WindowsVirtualKeyMapper.TryMapSemanticCode(semanticCode, out virtualKey))
        {
            return true;
        }

        virtualKey = dispatchEvent.VirtualKey;
        return virtualKey != 0;
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

    private static int CopyShortcutModifierVirtualKeys(DispatchSemanticAction semanticAction, Span<ushort> destination)
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
            if (!WindowsVirtualKeyMapper.TryMapSemanticCode(modifierCodes[index], out ushort virtualKey))
            {
                continue;
            }

            destination[count++] = virtualKey;
        }

        if (count == 0 &&
            semanticAction.SecondaryCode != DispatchSemanticCode.None &&
            WindowsVirtualKeyMapper.TryMapSemanticCode(semanticAction.SecondaryCode, out ushort legacyVirtualKey))
        {
            destination[count++] = legacyVirtualKey;
        }

        return count;
    }

    private void ApplyAutocorrectForWordBoundary()
    {
        if (!_autocorrect.TryCompleteWord(out AutocorrectReplacement replacement))
        {
            return;
        }

        for (int i = 0; i < replacement.BackspaceCount; i++)
        {
            SendKeyTap(VirtualKeyBackspace);
        }

        for (int i = 0; i < replacement.ReplacementText.Length; i++)
        {
            if (!TryResolveCharacterVirtualKey(replacement.ReplacementText[i], out ushort virtualKey, out bool requiresShift))
            {
                continue;
            }

            bool shiftAlreadyDown = IsShiftModifierDown();
            if (requiresShift && !shiftAlreadyDown)
            {
                SendKeyboard(VirtualKeyShift, keyUp: false);
            }

            SendKeyTap(virtualKey);

            if (requiresShift && !shiftAlreadyDown)
            {
                SendKeyboard(VirtualKeyShift, keyUp: true);
            }
        }
    }

    private bool HasShortcutModifierDown()
    {
        return IsModifierDown(VirtualKeyControl) ||
            IsModifierDown(VirtualKeyLeftControl) ||
            IsModifierDown(VirtualKeyRightControl) ||
            IsModifierDown(VirtualKeyMenu) ||
            IsModifierDown(VirtualKeyLeftMenu) ||
            IsModifierDown(VirtualKeyRightMenu) ||
            IsModifierDown(VirtualKeyLeftWindows) ||
            IsModifierDown(VirtualKeyRightWindows);
    }

    private bool IsShiftModifierDown()
    {
        return IsModifierDown(VirtualKeyShift) ||
            IsModifierDown(VirtualKeyLeftShift) ||
            IsModifierDown(VirtualKeyRightShift);
    }

    private bool IsModifierDown(ushort virtualKey)
    {
        int vk = virtualKey;
        return (uint)vk < (uint)_modifierRefCounts.Length && _modifierRefCounts[vk] > 0;
    }

    private static bool TryResolveCharacterVirtualKey(char ch, out ushort virtualKey, out bool requiresShift)
    {
        requiresShift = false;
        if (ch >= 'a' && ch <= 'z')
        {
            virtualKey = (ushort)(ch - 'a' + 0x41);
            return true;
        }

        if (ch >= 'A' && ch <= 'Z')
        {
            virtualKey = (ushort)(ch - 'A' + 0x41);
            requiresShift = true;
            return true;
        }

        virtualKey = 0;
        return false;
    }

    private void ConsumePendingPointerActivity()
    {
        if (Interlocked.Exchange(ref _autocorrectPointerActivityPending, 0) != 0)
        {
            _autocorrect.NotifyPointerActivity();
        }
    }

    private void RefreshAutocorrectForegroundProcess()
    {
        if (!TryGetForegroundProcessId(out uint processId))
        {
            return;
        }

        _autocorrect.UpdateContext(
            contextKey: processId.ToString(CultureInfo.InvariantCulture),
            contextLabel: ResolveProcessLabel(processId));
    }

    private static bool TryGetForegroundProcessId(out uint processId)
    {
        processId = 0;
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero)
        {
            return false;
        }

        _ = GetWindowThreadProcessId(hwnd, out processId);
        return processId != 0;
    }

    private string ResolveProcessLabel(uint processId)
    {
        if (processId == 0)
        {
            return "unknown";
        }

        if (_processNameCache.TryGetValue(processId, out string? cachedName))
        {
            return $"{cachedName} ({processId.ToString(CultureInfo.InvariantCulture)})";
        }

        string processName = $"pid-{processId.ToString(CultureInfo.InvariantCulture)}";
        try
        {
            Process process = Process.GetProcessById(unchecked((int)processId));
            if (!string.IsNullOrWhiteSpace(process.ProcessName))
            {
                processName = process.ProcessName;
            }
        }
        catch
        {
            // Process labels are best-effort diagnostics only.
        }

        _processNameCache[processId] = processName;
        return $"{processName} ({processId.ToString(CultureInfo.InvariantCulture)})";
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

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint code, uint mapType);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    private struct RepeatEntry
    {
        public bool Active;
        public ulong Token;
        public ushort VirtualKey;
        public DispatchSemanticAction SemanticAction;
        public long NextTick;
    }

    private struct TapReleaseEntry
    {
        public bool Active;
        public ushort VirtualKey;
        public long ReleaseTick;
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
