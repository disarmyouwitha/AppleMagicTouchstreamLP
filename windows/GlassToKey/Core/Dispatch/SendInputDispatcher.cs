using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

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
    private const ushort VirtualKeyBackspace = 0x08;
    private const ushort VirtualKeyTab = 0x09;
    private const ushort VirtualKeyEnter = 0x0D;
    private const ushort VirtualKeyShift = 0x10;
    private const ushort VirtualKeyControl = 0x11;
    private const ushort VirtualKeyMenu = 0x12;
    private const ushort VirtualKeySpace = 0x20;
    private const ushort VirtualKeyLeftWindows = 0x5B;
    private const ushort VirtualKeyRightWindows = 0x5C;
    private const ushort VirtualKeyLeftShift = 0xA0;
    private const ushort VirtualKeyRightShift = 0xA1;
    private const ushort VirtualKeyLeftControl = 0xA2;
    private const ushort VirtualKeyRightControl = 0xA3;
    private const ushort VirtualKeyLeftMenu = 0xA4;
    private const ushort VirtualKeyRightMenu = 0xA5;
    private const int AutocorrectMinimumWordLength = 3;
    private const int AutocorrectMaximumWordLength = 48;
    private const int AutocorrectCacheCapacity = 2048;
    private const int AutocorrectWordHistoryCapacity = 24;
    private const int AutocorrectMaxEditDistanceMin = 1;
    private const int AutocorrectMaxEditDistanceMax = 2;
    private const int SymSpellDictionaryMaxEditDistance = 2;
    private const int SymSpellPrefixLength = 7;
    private const int SymSpellDictionaryWordCount = 82765;
    private const string SymSpellDictionaryFileName = "frequency_dictionary_en_82_765.txt";

    private readonly int[] _modifierRefCounts = new int[256];
    private readonly bool[] _keyDown = new bool[256];
    private readonly RepeatEntry[] _repeatEntries = new RepeatEntry[64];
    private readonly Input[] _singleInput = new Input[1];
    private readonly Input[] _dualInput = new Input[2];
    private readonly StringBuilder _autocorrectWordBuffer = new(24);
    private readonly Dictionary<string, string?> _autocorrectCache = new(StringComparer.Ordinal);
    private readonly Dictionary<uint, string> _processNameCache = new();
    private readonly HashSet<string> _autocorrectBlacklist = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _autocorrectOverrides = new(StringComparer.Ordinal);
    private readonly string[] _autocorrectWordHistory = new string[AutocorrectWordHistoryCapacity];
    private readonly long _repeatInitialDelayTicks;
    private readonly long _repeatIntervalTicks;
    private bool _autocorrectEnabled;
    private uint _autocorrectForegroundProcessId;
    private string _autocorrectForegroundApp = "unknown";
    private string _autocorrectLastCorrected = "none";
    private string _autocorrectBufferSnapshot = string.Empty;
    private string _autocorrectSkipReason = "idle";
    private string _autocorrectLastResetSource = "none";
    private string _autocorrectWordHistorySnapshot = "<empty>";
    private int _autocorrectWordHistoryWriteIndex;
    private int _autocorrectWordHistoryCount;
    private int _autocorrectMaxEditDistance = AutocorrectMaxEditDistanceMax;
    private bool _autocorrectDryRunEnabled;
    private long _autocorrectCounterCorrected;
    private long _autocorrectCounterSkipped;
    private long _autocorrectCounterResetByClick;
    private long _autocorrectCounterResetByAppChange;
    private long _autocorrectCounterShortcutBypass;
    private int _autocorrectPointerActivityPending;
    private bool _suppressPhysicalOutput;
    private bool _disposed;
    private static readonly Lazy<SymSpell?> SymSpellInstance = new(CreateSymSpell);

    public SendInputDispatcher()
    {
        _repeatInitialDelayTicks = MsToTicks(275);
        _repeatIntervalTicks = MsToTicks(33);
    }

    public void SetAutocorrectEnabled(bool enabled)
    {
        _autocorrectEnabled = enabled;
        if (enabled)
        {
            _ = SymSpellInstance.Value;
            _autocorrectSkipReason = "enabled";
        }
        else
        {
            ResetAutocorrectState("disabled");
            _autocorrectForegroundProcessId = 0;
            _autocorrectForegroundApp = "unknown";
        }
    }

    public void ConfigureAutocorrectOptions(AutocorrectOptions options)
    {
        int normalizedMaxDistance = Math.Clamp(
            options.MaxEditDistance,
            AutocorrectMaxEditDistanceMin,
            AutocorrectMaxEditDistanceMax);
        bool cacheInvalidated = normalizedMaxDistance != _autocorrectMaxEditDistance;
        _autocorrectMaxEditDistance = normalizedMaxDistance;
        _autocorrectDryRunEnabled = options.DryRunEnabled;

        HashSet<string> parsedBlacklist = ParseAutocorrectWordSet(options.BlacklistCsv);
        Dictionary<string, string> parsedOverrides = ParseAutocorrectOverrides(options.OverridesCsv);
        if (!SetEquals(_autocorrectBlacklist, parsedBlacklist))
        {
            _autocorrectBlacklist.Clear();
            foreach (string word in parsedBlacklist)
            {
                _autocorrectBlacklist.Add(word);
            }

            cacheInvalidated = true;
        }

        if (!MapEquals(_autocorrectOverrides, parsedOverrides))
        {
            _autocorrectOverrides.Clear();
            foreach ((string key, string value) in parsedOverrides)
            {
                _autocorrectOverrides[key] = value;
            }

            cacheInvalidated = true;
        }

        if (cacheInvalidated)
        {
            _autocorrectCache.Clear();
        }
    }

    internal void SetPhysicalOutputSuppressed(bool suppressed)
    {
        _suppressPhysicalOutput = suppressed;
    }

    internal void ForceAutocorrectReset(string reason)
    {
        ResetAutocorrectState(reason);
    }

    public AutocorrectStatusSnapshot GetAutocorrectStatus()
    {
        return new AutocorrectStatusSnapshot(
            Enabled: _autocorrectEnabled,
            DryRunEnabled: _autocorrectDryRunEnabled,
            MaxEditDistance: _autocorrectMaxEditDistance,
            CurrentApp: _autocorrectForegroundApp,
            LastCorrected: _autocorrectLastCorrected,
            CurrentBuffer: _autocorrectBufferSnapshot,
            SkipReason: _autocorrectSkipReason,
            LastResetSource: _autocorrectLastResetSource,
            CorrectedCount: _autocorrectCounterCorrected,
            SkippedCount: _autocorrectCounterSkipped,
            ResetByClickCount: _autocorrectCounterResetByClick,
            ResetByAppChangeCount: _autocorrectCounterResetByAppChange,
            ShortcutBypassCount: _autocorrectCounterShortcutBypass,
            WordHistory: _autocorrectWordHistorySnapshot);
    }

    public void NotifyPointerActivity()
    {
        Interlocked.Exchange(ref _autocorrectPointerActivityPending, 1);
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
            case DispatchEventKind.KeyTap:
                if (!_suppressPhysicalOutput && TryDispatchSystemAction(dispatchEvent.VirtualKey))
                {
                    break;
                }

                if (dispatchEvent.VirtualKey != 0)
                {
                    HandleKeyTap(dispatchEvent.VirtualKey);
                }
                break;
            case DispatchEventKind.KeyDown:
                HandleKeyDownAutocorrect(dispatchEvent.VirtualKey);
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
                ResetAutocorrectState("pointer_click");
                SendMouseButtonClick(dispatchEvent.MouseButton);
                break;
            case DispatchEventKind.MouseButtonDown:
                ResetAutocorrectState("pointer_click");
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

    private void HandleKeyTap(ushort virtualKey)
    {
        if (!_autocorrectEnabled)
        {
            ResetAutocorrectState();
            _autocorrectSkipReason = "disabled";
            _autocorrectLastResetSource = "disabled";
            SendKeyTap(virtualKey);
            return;
        }

        ProcessAutocorrectKeyInput(virtualKey);
        SendKeyTap(virtualKey);
    }

    private void HandleKeyDownAutocorrect(ushort virtualKey)
    {
        if (!_autocorrectEnabled)
        {
            return;
        }

        ProcessAutocorrectKeyInput(virtualKey);
    }

    private void ProcessAutocorrectKeyInput(ushort virtualKey)
    {
        RefreshAutocorrectForegroundProcess();

        if (HasShortcutModifierDown())
        {
            _autocorrectCounterShortcutBypass++;
            ResetAutocorrectState("shortcut_active");
            return;
        }

        if (virtualKey == VirtualKeyBackspace)
        {
            if (_autocorrectWordBuffer.Length > 0)
            {
                _autocorrectWordBuffer.Length--;
                _autocorrectBufferSnapshot = _autocorrectWordBuffer.ToString();
            }
            _autocorrectSkipReason = "manual_backspace";
            return;
        }

        if (TryVirtualKeyToLetter(virtualKey, out char letter))
        {
            if (_autocorrectWordBuffer.Length < AutocorrectMaximumWordLength)
            {
                _autocorrectWordBuffer.Append(letter);
                _autocorrectBufferSnapshot = _autocorrectWordBuffer.ToString();
            }
            _autocorrectSkipReason = "tracking";
            return;
        }

        if (IsWordBoundaryVirtualKey(virtualKey))
        {
            ApplyAutocorrectForWordBoundary();
            return;
        }

        ResetAutocorrectState("non_word_key");
    }

    public void Tick(long nowTicks)
    {
        if (_disposed)
        {
            return;
        }

        ConsumePendingPointerActivity();

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

            HandleKeyTap(_repeatEntries[i].VirtualKey);
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

        if (virtualKey is
            VirtualKeyControl or VirtualKeyLeftControl or VirtualKeyRightControl or
            VirtualKeyMenu or VirtualKeyLeftMenu or VirtualKeyRightMenu or
            VirtualKeyLeftWindows or VirtualKeyRightWindows)
        {
            ResetAutocorrectState("shortcut_modifier_down");
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
        ResetAutocorrectState();
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
        if (virtualKey == 0 || _suppressPhysicalOutput)
        {
            return;
        }

        _dualInput[0] = CreateKeyboardInput(virtualKey, keyUp: false);
        _dualInput[1] = CreateKeyboardInput(virtualKey, keyUp: true);
        SendInput(2, _dualInput, Marshal.SizeOf<Input>());
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
        if (_suppressPhysicalOutput)
        {
            return;
        }

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
        if (_suppressPhysicalOutput)
        {
            return;
        }

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
        if (_suppressPhysicalOutput)
        {
            return;
        }

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

    private static SymSpell? CreateSymSpell()
    {
        try
        {
            SymSpell symSpell = new(
                initialCapacity: SymSpellDictionaryWordCount,
                maxDictionaryEditDistance: SymSpellDictionaryMaxEditDistance,
                prefixLength: SymSpellPrefixLength);

            string baseDir = AppContext.BaseDirectory;
            string dictionaryPath = Path.Combine(baseDir, "ThirdParty", "SymSpell", SymSpellDictionaryFileName);
            if (!File.Exists(dictionaryPath))
            {
                dictionaryPath = Path.Combine(baseDir, SymSpellDictionaryFileName);
                if (!File.Exists(dictionaryPath))
                {
                    return null;
                }
            }

            return symSpell.LoadDictionary(dictionaryPath, termIndex: 0, countIndex: 1) ? symSpell : null;
        }
        catch
        {
            return null;
        }
    }

    private void ApplyAutocorrectForWordBoundary()
    {
        string typedWord = _autocorrectWordBuffer.ToString();
        if (typedWord.Length == 0)
        {
            _autocorrectSkipReason = "word_empty";
            ResetAutocorrectState();
            return;
        }

        RecordWordHistory(typedWord);

        if (_autocorrectWordBuffer.Length < AutocorrectMinimumWordLength ||
            _autocorrectWordBuffer.Length > AutocorrectMaximumWordLength)
        {
            RegisterAutocorrectSkip("word_length");
            ResetAutocorrectState();
            return;
        }

        SymSpell? symSpell = SymSpellInstance.Value;
        if (symSpell == null)
        {
            RegisterAutocorrectSkip("dictionary_unavailable");
            ResetAutocorrectState();
            return;
        }

        string typedLower = typedWord.ToLowerInvariant();
        if (_autocorrectBlacklist.Contains(typedLower))
        {
            RegisterAutocorrectSkip("blacklisted");
            ResetAutocorrectState();
            return;
        }

        string resolutionSource;
        string? correctedLower;
        if (_autocorrectOverrides.TryGetValue(typedLower, out string? overrideCorrection))
        {
            correctedLower = overrideCorrection;
            resolutionSource = "override";
        }
        else
        {
            correctedLower = ResolveCorrection(symSpell, typedLower);
            resolutionSource = "symspell";
        }

        if (string.IsNullOrEmpty(correctedLower))
        {
            RegisterAutocorrectSkip("no_suggestion");
            ResetAutocorrectState();
            return;
        }

        string corrected = ApplyWordCasePattern(correctedLower, typedWord);
        if (string.Equals(corrected, typedWord, StringComparison.Ordinal))
        {
            RegisterAutocorrectSkip("already_correct");
            ResetAutocorrectState();
            return;
        }

        bool applyReplacement = !_autocorrectDryRunEnabled;
        if (applyReplacement)
        {
            for (int i = 0; i < typedWord.Length; i++)
            {
                SendKeyTap(VirtualKeyBackspace);
            }

            for (int i = 0; i < corrected.Length; i++)
            {
                if (!TryResolveCharacterVirtualKey(corrected[i], out ushort virtualKey, out bool requiresShift))
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

        if (applyReplacement)
        {
            _autocorrectCounterCorrected++;
            _autocorrectLastCorrected = resolutionSource == "override"
                ? $"{typedWord} -> {corrected} (override)"
                : $"{typedWord} -> {corrected}";
            _autocorrectSkipReason = "corrected";
        }
        else
        {
            _autocorrectCounterSkipped++;
            _autocorrectLastCorrected = $"{typedWord} -> {corrected} (dry-run)";
            _autocorrectSkipReason = "dry_run_preview";
        }

        ResetAutocorrectState();
    }

    private string? ResolveCorrection(SymSpell symSpell, string typedLower)
    {
        string cacheKey = $"{_autocorrectMaxEditDistance}:{typedLower}";
        if (_autocorrectCache.TryGetValue(cacheKey, out string? cached))
        {
            return cached;
        }

        List<SymSpell.SuggestItem> suggestions = symSpell.Lookup(
            typedLower,
            SymSpell.Verbosity.Top,
            _autocorrectMaxEditDistance);
        string? correction = null;
        if (suggestions.Count > 0)
        {
            SymSpell.SuggestItem suggestion = suggestions[0];
            bool isWordLike = IsAsciiLetterWord(suggestion.term);
            if (suggestion.distance > 0 &&
                isWordLike &&
                !string.Equals(suggestion.term, typedLower, StringComparison.Ordinal))
            {
                correction = suggestion.term;
            }
        }

        if (_autocorrectCache.Count >= AutocorrectCacheCapacity)
        {
            _autocorrectCache.Clear();
        }

        _autocorrectCache[cacheKey] = correction;
        return correction;
    }

    private static bool IsAsciiLetterWord(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return false;
        }

        for (int i = 0; i < value.Length; i++)
        {
            char ch = value[i];
            if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')))
            {
                return false;
            }
        }

        return true;
    }

    private static string ApplyWordCasePattern(string correction, string original)
    {
        if (string.IsNullOrEmpty(correction) || string.IsNullOrEmpty(original))
        {
            return correction;
        }

        bool allUpper = true;
        bool firstUpperRestLower = char.IsUpper(original[0]);
        for (int i = 0; i < original.Length; i++)
        {
            char ch = original[i];
            if (char.IsLetter(ch))
            {
                if (!char.IsUpper(ch))
                {
                    allUpper = false;
                }

                if (i > 0 && !char.IsLower(ch))
                {
                    firstUpperRestLower = false;
                }
            }
            else
            {
                allUpper = false;
                firstUpperRestLower = false;
            }
        }

        if (allUpper)
        {
            return correction.ToUpperInvariant();
        }

        if (firstUpperRestLower)
        {
            if (correction.Length == 1)
            {
                return correction.ToUpperInvariant();
            }

            return char.ToUpperInvariant(correction[0]) + correction.Substring(1).ToLowerInvariant();
        }

        return correction.ToLowerInvariant();
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

    private static bool IsWordBoundaryVirtualKey(ushort virtualKey)
    {
        return virtualKey is
            VirtualKeySpace or
            VirtualKeyTab or
            VirtualKeyEnter or
            0xBA or // ; :
            0xBC or // , <
            0xBD or // - _
            0xBE or // . >
            0xBF or // / ?
            0xC0 or // ` ~
            0xDB or // [ {
            0xDC or // \ |
            0xDD or // ] }
            0xDE;   // ' "
    }

    private bool TryVirtualKeyToLetter(ushort virtualKey, out char value)
    {
        if (virtualKey >= 0x41 && virtualKey <= 0x5A)
        {
            char baseChar = (char)('a' + (virtualKey - 0x41));
            value = IsShiftModifierDown()
                ? char.ToUpperInvariant(baseChar)
                : baseChar;
            return true;
        }

        value = '\0';
        return false;
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
            ResetAutocorrectState("pointer_click");
        }
    }

    private void RefreshAutocorrectForegroundProcess()
    {
        if (!TryGetForegroundProcessId(out uint processId))
        {
            return;
        }

        bool changed = _autocorrectForegroundProcessId != processId;
        if (_autocorrectForegroundProcessId != 0 && _autocorrectForegroundProcessId != processId)
        {
            ResetAutocorrectState("app_changed");
        }

        if (changed)
        {
            _autocorrectForegroundApp = ResolveProcessLabel(processId);
        }

        _autocorrectForegroundProcessId = processId;
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

    private void ResetAutocorrectState(string? reason = null)
    {
        _autocorrectWordBuffer.Clear();
        _autocorrectBufferSnapshot = string.Empty;
        if (!string.IsNullOrWhiteSpace(reason))
        {
            _autocorrectSkipReason = reason;
            _autocorrectLastResetSource = reason;
            if (string.Equals(reason, "pointer_click", StringComparison.Ordinal))
            {
                _autocorrectCounterResetByClick++;
            }
            else if (string.Equals(reason, "app_changed", StringComparison.Ordinal))
            {
                _autocorrectCounterResetByAppChange++;
            }
        }
    }

    private void RegisterAutocorrectSkip(string reason)
    {
        _autocorrectCounterSkipped++;
        _autocorrectSkipReason = reason;
    }

    private void RecordWordHistory(string word)
    {
        if (string.IsNullOrWhiteSpace(word))
        {
            return;
        }

        _autocorrectWordHistory[_autocorrectWordHistoryWriteIndex] = word;
        _autocorrectWordHistoryWriteIndex = (_autocorrectWordHistoryWriteIndex + 1) % _autocorrectWordHistory.Length;
        if (_autocorrectWordHistoryCount < _autocorrectWordHistory.Length)
        {
            _autocorrectWordHistoryCount++;
        }

        _autocorrectWordHistorySnapshot = BuildWordHistorySnapshot();
    }

    private string BuildWordHistorySnapshot()
    {
        if (_autocorrectWordHistoryCount == 0)
        {
            return "<empty>";
        }

        StringBuilder builder = new(capacity: 128);
        for (int i = 0; i < _autocorrectWordHistoryCount; i++)
        {
            int index = (_autocorrectWordHistoryWriteIndex - _autocorrectWordHistoryCount + i + _autocorrectWordHistory.Length) %
                _autocorrectWordHistory.Length;
            if (i > 0)
            {
                builder.Append(' ');
            }

            builder.Append(_autocorrectWordHistory[index]);
        }

        return builder.ToString();
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

    private static HashSet<string> ParseAutocorrectWordSet(string? source)
    {
        HashSet<string> values = new(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(source))
        {
            return values;
        }

        ReadOnlySpan<char> span = source.AsSpan();
        int start = 0;
        for (int i = 0; i <= span.Length; i++)
        {
            bool boundary = i == span.Length ||
                span[i] == ',' ||
                span[i] == ';' ||
                span[i] == ' ' ||
                span[i] == '\n' ||
                span[i] == '\r' ||
                span[i] == '\t';
            if (!boundary)
            {
                continue;
            }

            ReadOnlySpan<char> token = span[start..i].Trim();
            start = i + 1;
            if (token.IsEmpty)
            {
                continue;
            }

            string word = token.ToString().ToLowerInvariant();
            if (IsAsciiLetterWord(word))
            {
                values.Add(word);
            }
        }

        return values;
    }

    private static Dictionary<string, string> ParseAutocorrectOverrides(string? source)
    {
        Dictionary<string, string> map = new(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(source))
        {
            return map;
        }

        string normalized = source.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
        string[] lines = normalized.Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i].Trim();
            if (line.Length == 0)
            {
                continue;
            }

            string[] segments = line.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            for (int segmentIndex = 0; segmentIndex < segments.Length; segmentIndex++)
            {
                if (!TryParseAutocorrectOverride(segments[segmentIndex], out string from, out string to))
                {
                    continue;
                }

                map[from] = to;
            }
        }

        return map;
    }

    private static bool TryParseAutocorrectOverride(string text, out string from, out string to)
    {
        from = string.Empty;
        to = string.Empty;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        string line = text.Trim();
        int separatorIndex = line.IndexOf("->", StringComparison.Ordinal);
        int separatorLength = 2;
        if (separatorIndex < 0)
        {
            separatorIndex = line.IndexOf('=', StringComparison.Ordinal);
            separatorLength = 1;
        }

        if (separatorIndex < 0)
        {
            separatorIndex = line.IndexOf(':', StringComparison.Ordinal);
            separatorLength = 1;
        }

        if (separatorIndex <= 0 || separatorIndex >= line.Length - separatorLength)
        {
            return false;
        }

        string left = line.Substring(0, separatorIndex).Trim().ToLowerInvariant();
        string right = line.Substring(separatorIndex + separatorLength).Trim().ToLowerInvariant();
        if (!IsAsciiLetterWord(left) || !IsAsciiLetterWord(right))
        {
            return false;
        }

        from = left;
        to = right;
        return true;
    }

    private static bool SetEquals(HashSet<string> existing, HashSet<string> next)
    {
        return existing.Count == next.Count && existing.SetEquals(next);
    }

    private static bool MapEquals(Dictionary<string, string> existing, Dictionary<string, string> next)
    {
        if (existing.Count != next.Count)
        {
            return false;
        }

        foreach ((string key, string value) in next)
        {
            if (!existing.TryGetValue(key, out string? existingValue) ||
                !string.Equals(existingValue, value, StringComparison.Ordinal))
            {
                return false;
            }
        }

        return true;
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
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    private struct RepeatEntry
    {
        public bool Active;
        public ulong Token;
        public ushort VirtualKey;
        public long NextTick;
    }
}

internal readonly record struct AutocorrectStatusSnapshot(
    bool Enabled,
    bool DryRunEnabled,
    int MaxEditDistance,
    string CurrentApp,
    string LastCorrected,
    string CurrentBuffer,
    string SkipReason,
    string LastResetSource,
    long CorrectedCount,
    long SkippedCount,
    long ResetByClickCount,
    long ResetByAppChangeCount,
    long ShortcutBypassCount,
    string WordHistory);

internal readonly record struct AutocorrectOptions(
    int MaxEditDistance,
    bool DryRunEnabled,
    string BlacklistCsv,
    string OverridesCsv);

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
