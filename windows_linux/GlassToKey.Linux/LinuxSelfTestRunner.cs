using System.Diagnostics;
using System.Text.Json;
using GlassToKey.Linux.Runtime;
using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Evdev;
using GlassToKey.Platform.Linux.Haptics;
using GlassToKey.Platform.Linux.Models;
using GlassToKey.Platform.Linux.Uinput;

namespace GlassToKey.Linux;

internal readonly record struct LinuxSelfTestResult(bool Success, string Message);

internal static class LinuxSelfTestRunner
{
    private static readonly string[] ForbiddenBundledLabels =
    [
        "EMOJI",
        "VOICE",
        "LWin",
        "RWin",
        "Win+H"
    ];

    public static LinuxSelfTestResult Run()
    {
        if (!TryLoadBundledKeymap(out KeymapStore.KeymapFileModel keymap, out string failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateBundledTranslations(keymap, out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateResolvedMappings(keymap, out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateSemanticAliases(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateSharedAutocorrect(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateConfiguredRuntimeStartupState(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateConfiguredMouseTakeoverStartupState(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateAtpCapRoundTrip(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateLinuxForceThresholdDispatch(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateLinuxAssemblerForceData(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateMagicTrackpadSelectionHeuristic(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateLinuxActuatorDescriptorParsing(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        return new LinuxSelfTestResult(true, "Linux self-tests passed.");
    }

    private static bool TryLoadBundledKeymap(out KeymapStore.KeymapFileModel keymap, out string failure)
    {
        keymap = new KeymapStore.KeymapFileModel();
        failure = string.Empty;

        string path = Path.Combine(AppContext.BaseDirectory, "GLASSTOKEY_DEFAULT_KEYMAP.json");
        if (!File.Exists(path))
        {
            failure = $"Bundled Linux keymap is missing: {path}";
            return false;
        }

        try
        {
            string bundledJson = File.ReadAllText(path);
            string keymapJson = ExtractBundledKeymapJsonOrSelf(bundledJson);
            if (string.IsNullOrWhiteSpace(keymapJson))
            {
                failure = "Bundled Linux keymap payload is empty.";
                return false;
            }

            KeymapStore store = new();
            if (!store.TryImportFromJson(keymapJson, out string importFailure))
            {
                failure = $"Bundled Linux keymap did not import: {importFailure}";
                return false;
            }

            KeymapStore.KeymapFileModel? model = JsonSerializer.Deserialize<KeymapStore.KeymapFileModel>(
                keymapJson,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (model?.Layouts == null || model.Layouts.Count == 0)
            {
                failure = "Bundled Linux keymap contains no layouts.";
                return false;
            }

            keymap = model;
            return true;
        }
        catch (Exception ex)
        {
            failure = $"Bundled Linux keymap parse failed: {ex.Message}";
            return false;
        }
    }

    private static string ExtractBundledKeymapJsonOrSelf(string bundledJson)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(bundledJson);
            if (document.RootElement.ValueKind == JsonValueKind.Object &&
                TryGetPropertyIgnoreCase(document.RootElement, "KeymapJson", out JsonElement keymapJsonElement) &&
                keymapJsonElement.ValueKind == JsonValueKind.String)
            {
                return keymapJsonElement.GetString() ?? string.Empty;
            }
        }
        catch
        {
            // Let the normal keymap import path surface the parse error.
        }

        return bundledJson;
    }

    private static bool TryGetPropertyIgnoreCase(JsonElement element, string propertyName, out JsonElement value)
    {
        foreach (JsonProperty property in element.EnumerateObject())
        {
            if (string.Equals(property.Name, propertyName, StringComparison.OrdinalIgnoreCase))
            {
                value = property.Value;
                return true;
            }
        }

        value = default;
        return false;
    }

    private static bool ValidateBundledTranslations(KeymapStore.KeymapFileModel keymap, out string failure)
    {
        foreach (string label in EnumerateActionLabels(keymap))
        {
            for (int index = 0; index < ForbiddenBundledLabels.Length; index++)
            {
                if (string.Equals(label, ForbiddenBundledLabels[index], StringComparison.OrdinalIgnoreCase))
                {
                    failure = $"Bundled Linux keymap still contains Windows-specific label '{label}'.";
                    return false;
                }
            }
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateResolvedMappings(KeymapStore.KeymapFileModel keymap, out string failure)
    {
        foreach (string label in EnumerateActionLabels(keymap))
        {
            EngineKeyAction action = EngineActionResolver.ResolveActionLabel(label, "None");
            if (!ValidateResolvedAction(label, action, out failure))
            {
                return false;
            }
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateSemanticAliases(out string failure)
    {
        if (!ValidateSemanticAlias("VOL_UP", DispatchSemanticCode.VolumeUp, LinuxEvdevCodes.KeyVolumeUp, out failure) ||
            !ValidateSemanticAlias("VOL_DOWN", DispatchSemanticCode.VolumeDown, LinuxEvdevCodes.KeyVolumeDown, out failure) ||
            !ValidateSemanticAlias("MUTE", DispatchSemanticCode.VolumeMute, LinuxEvdevCodes.KeyMute, out failure) ||
            !ValidateSemanticAlias("BRIGHT_UP", DispatchSemanticCode.BrightnessUp, LinuxEvdevCodes.KeyBrightnessUp, out failure) ||
            !ValidateSemanticAlias("BRIGHT_DOWN", DispatchSemanticCode.BrightnessDown, LinuxEvdevCodes.KeyBrightnessDown, out failure) ||
            !ValidateSemanticAlias("PLAY_PAUSE", DispatchSemanticCode.MediaPlayPause, LinuxEvdevCodes.KeyPlayPause, out failure) ||
            !ValidateSemanticAlias("NEXT_TRACK", DispatchSemanticCode.MediaNextTrack, LinuxEvdevCodes.KeyNextSong, out failure) ||
            !ValidateSemanticAlias("PREV_TRACK", DispatchSemanticCode.MediaPreviousTrack, LinuxEvdevCodes.KeyPreviousSong, out failure) ||
            !ValidateSemanticAlias("STOP_MEDIA", DispatchSemanticCode.MediaStop, LinuxEvdevCodes.KeyStopCd, out failure) ||
            !ValidateSemanticAlias("CAPS_LOCK", DispatchSemanticCode.CapsLock, LinuxEvdevCodes.KeyCapsLock, out failure) ||
            !ValidateSemanticAlias("NUM_LOCK", DispatchSemanticCode.NumLock, LinuxEvdevCodes.KeyNumLock, out failure) ||
            !ValidateSemanticAlias("SCROLL_LOCK", DispatchSemanticCode.ScrollLock, LinuxEvdevCodes.KeyScrollLock, out failure) ||
            !ValidateSemanticAlias("PRINT_SCREEN", DispatchSemanticCode.PrintScreen, LinuxEvdevCodes.KeySysRq, out failure) ||
            !ValidateSemanticAlias("PAUSE", DispatchSemanticCode.Pause, LinuxEvdevCodes.KeyPause, out failure) ||
            !ValidateSemanticAlias("MENU", DispatchSemanticCode.Menu, LinuxEvdevCodes.KeyMenu, out failure) ||
            !ValidateSemanticAlias("F24", DispatchSemanticCode.F24, LinuxEvdevCodes.KeyF24, out failure))
        {
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateSemanticAlias(
        string label,
        DispatchSemanticCode expectedCode,
        ushort expectedLinuxCode,
        out string failure)
    {
        if (!DispatchSemanticResolver.TryResolveKeyCode(label, out DispatchSemanticCode resolvedCode) ||
            resolvedCode != expectedCode)
        {
            failure = $"Label '{label}' did not resolve semantic code '{expectedCode}'.";
            return false;
        }

        EngineKeyAction action = EngineActionResolver.ResolveActionLabel(label, "None");
        if (action.SemanticAction.PrimaryCode != expectedCode)
        {
            failure = $"Label '{label}' did not flow semantic code '{expectedCode}' through action resolution.";
            return false;
        }

        if (!LinuxKeyCodeMapper.TryMapSemanticCode(expectedCode, out ushort linuxCode) ||
            linuxCode != expectedLinuxCode)
        {
            failure = $"Semantic code '{expectedCode}' did not map to Linux code '{expectedLinuxCode}'.";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateSharedAutocorrect(out string failure)
    {
        using AutocorrectSession session = new(new FakeAutocorrectLexicon(("teh", "the"), ("woudl", "would")));
        session.Configure(new AutocorrectOptions(
            MaxEditDistance: 2,
            DryRunEnabled: false,
            BlacklistCsv: "dontfix",
            OverridesCsv: "adress->address"));
        session.SetEnabled(true);

        session.TrackLetter('t');
        session.TrackLetter('e');
        session.TrackLetter('h');
        if (!session.TryCompleteWord(out AutocorrectReplacement replacement) ||
            replacement.BackspaceCount != 3 ||
            !string.Equals(replacement.ReplacementText, "the", StringComparison.Ordinal))
        {
            failure = "Shared autocorrect did not produce the expected SymSpell replacement.";
            return false;
        }

        AutocorrectStatusSnapshot status = session.GetStatus();
        if (status.CorrectedCount != 1 || !string.Equals(status.SkipReason, "corrected", StringComparison.Ordinal))
        {
            failure = "Shared autocorrect correction counters/status did not update after a replacement.";
            return false;
        }

        session.TrackLetter('a');
        session.TrackLetter('d');
        session.TrackLetter('r');
        session.TrackLetter('e');
        session.TrackLetter('s');
        session.TrackLetter('s');
        if (!session.TryCompleteWord(out replacement) ||
            !string.Equals(replacement.ReplacementText, "address", StringComparison.Ordinal))
        {
            failure = "Shared autocorrect override mapping did not win over dictionary resolution.";
            return false;
        }

        session.TrackLetter('d');
        session.TrackLetter('o');
        session.TrackLetter('n');
        session.TrackLetter('t');
        if (session.TryCompleteWord(out _))
        {
            failure = "Shared autocorrect should not replace blacklisted words.";
            return false;
        }

        status = session.GetStatus();
        if (status.CorrectedCount != 2 || status.SkippedCount == 0)
        {
            failure = "Shared autocorrect skip/correct counters were not updated as expected.";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateConfiguredRuntimeStartupState(out string failure)
    {
        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        UserSettings settings = new()
        {
            LayoutPresetName = preset.Name,
            ActiveLayer = 2,
            TypingEnabled = false,
            KeyboardModeEnabled = true
        };
        settings.NormalizeRanges();

        using RecordingDispatcher dispatcher = new();
        using TouchProcessorRuntimeHost host = new(dispatcher, KeymapStore.LoadBundledDefault(), preset, settings);
        if (!host.TryGetSnapshot(out TouchProcessorRuntimeSnapshot snapshot))
        {
            failure = "Configured runtime host did not produce an initial snapshot.";
            return false;
        }

        if (snapshot.ActiveLayer != settings.ActiveLayer ||
            snapshot.TypingEnabled != settings.TypingEnabled ||
            snapshot.KeyboardModeEnabled != settings.KeyboardModeEnabled)
        {
            failure = $"Configured runtime host did not restore startup mode state (layer={snapshot.ActiveLayer}, typing={snapshot.TypingEnabled}, keyboard={snapshot.KeyboardModeEnabled}).";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateConfiguredMouseTakeoverStartupState(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;
        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout rightLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: false);
        NormalizedRect keyRect = rightLayout.Rects[0][0];
        ushort keyX = (ushort)Math.Clamp((int)Math.Round((keyRect.X + (keyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort keyY = (ushort)Math.Clamp((int)Math.Round((keyRect.Y + (keyRect.Height * 0.5)) * maxY), 1, maxY - 1);
        ushort offKeyX = (ushort)Math.Clamp(maxX - 64, 1, maxX - 1);
        ushort offKeyY = (ushort)Math.Clamp(maxY - 64, 1, maxY - 1);

        UserSettings settings = new()
        {
            LayoutPresetName = preset.Name,
            TypingEnabled = true,
            KeyboardModeEnabled = false,
            KeyBufferMs = 1.0,
            IntentMoveMm = 1.0,
            DragCancelMm = 1.0
        };
        settings.NormalizeRanges();

        using RecordingDispatcher dispatcher = new();
        using TouchProcessorRuntimeHost host = new(dispatcher, KeymapStore.LoadBundledDefault(), preset, settings);

        long now = Stopwatch.Frequency / 100;
        host.Post(new TrackpadFrameEnvelope(
            TrackpadSide.Right,
            MakeFrame(contactCount: 1, x: keyX, y: keyY, pressure: 64),
            maxX,
            maxY,
            now));
        now += Math.Max(1, Stopwatch.Frequency / 200);
        host.Post(new TrackpadFrameEnvelope(
            TrackpadSide.Right,
            MakeFrame(contactCount: 1, x: keyX, y: keyY, pressure: 64),
            maxX,
            maxY,
            now));
        now += Math.Max(1, Stopwatch.Frequency / 20);
        host.Post(new TrackpadFrameEnvelope(
            TrackpadSide.Right,
            MakeFrame(contactCount: 1, x: keyX, y: keyY, pressure: 64),
            maxX,
            maxY,
            now));
        now += Math.Max(1, Stopwatch.Frequency / 20);
        host.Post(new TrackpadFrameEnvelope(
            TrackpadSide.Right,
            MakeFrame(contactCount: 1, x: offKeyX, y: offKeyY, pressure: 64),
            maxX,
            maxY,
            now));
        now += Math.Max(1, Stopwatch.Frequency / 20);
        host.Post(new TrackpadFrameEnvelope(
            TrackpadSide.Right,
            MakeFrame(contactCount: 1, x: offKeyX, y: offKeyY, pressure: 64),
            maxX,
            maxY,
            now));

        if (!host.TryGetSynchronizedSnapshot(timeoutMs: 25, out TouchProcessorRuntimeSnapshot snapshot))
        {
            failure = "Configured runtime host did not produce a synchronized snapshot for mouse takeover validation.";
            return false;
        }

        if (!string.Equals(snapshot.IntentMode, "MouseActive", StringComparison.Ordinal))
        {
            failure = $"Configured runtime host did not restore mouse takeover on startup (intent={snapshot.IntentMode}).";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateResolvedAction(string label, EngineKeyAction action, out string failure)
    {
        if (action.Kind == EngineActionKind.None)
        {
            if (!string.Equals(label, "None", StringComparison.OrdinalIgnoreCase))
            {
                failure = $"Label '{label}' resolved to None.";
                return false;
            }

            failure = string.Empty;
            return true;
        }

        switch (action.Kind)
        {
            case EngineActionKind.Key:
            case EngineActionKind.Continuous:
            case EngineActionKind.Modifier:
                if (!CanResolveLinuxKey(action.SemanticAction.PrimaryCode, action.VirtualKey))
                {
                    failure = $"Label '{label}' did not resolve to a Linux key code.";
                    return false;
                }

                break;
            case EngineActionKind.KeyChord:
                if (!CanResolveLinuxKey(action.SemanticAction.PrimaryCode, action.VirtualKey))
                {
                    failure = $"Chord '{label}' did not resolve its primary Linux key code.";
                    return false;
                }

                if (!CanResolveLinuxKey(action.SemanticAction.SecondaryCode, action.ModifierVirtualKey))
                {
                    failure = $"Chord '{label}' did not resolve its modifier Linux key code.";
                    return false;
                }

                break;
            case EngineActionKind.MouseButton:
                if (!LinuxKeyCodeMapper.TryMapMouseButton(action.MouseButton, out _))
                {
                    failure = $"Mouse label '{label}' did not resolve to a Linux button.";
                    return false;
                }

                break;
            case EngineActionKind.MomentaryLayer:
            case EngineActionKind.LayerSet:
            case EngineActionKind.LayerToggle:
            case EngineActionKind.TypingToggle:
                break;
            default:
                failure = $"Label '{label}' resolved unexpected action kind '{action.Kind}'.";
                return false;
        }

        failure = string.Empty;
        return true;
    }

    private sealed class FakeAutocorrectLexicon : AutocorrectSession.IAutocorrectLexicon
    {
        private readonly Dictionary<string, string> _corrections;

        public FakeAutocorrectLexicon(params (string Typed, string Corrected)[] pairs)
        {
            _corrections = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < pairs.Length; index++)
            {
                (string typed, string corrected) = pairs[index];
                _corrections[typed] = corrected;
            }
        }

        public bool EnsureLoaded()
        {
            return true;
        }

        public string? ResolveCorrection(string typedLower, int maxEditDistance)
        {
            _ = maxEditDistance;
            return _corrections.TryGetValue(typedLower, out string? corrected)
                ? corrected
                : null;
        }

        public void Unload()
        {
        }
    }

    private static bool ValidateAtpCapRoundTrip(out string failure)
    {
        string tempRoot = Path.Combine(Path.GetTempPath(), $"glasstokey-linux-selftest-{Guid.NewGuid():N}");
        string capturePath = Path.Combine(tempRoot, "synthetic.atpcap");
        string fixturePath = Path.Combine(tempRoot, "synthetic.fixture.json");
        string tracePath = Path.Combine(tempRoot, "synthetic-trace.json");

        try
        {
            Directory.CreateDirectory(tempRoot);
            LinuxInputDeviceDescriptor device = new(
                DeviceNode: "/dev/input/event-selftest",
                StableId: "selftest-left",
                UniqueId: "selftest-left",
                PhysicalPath: "selftest-phys",
                DisplayName: "SelfTest Trackpad",
                VendorId: 0x05ac,
                ProductId: 0x0324,
                SupportsMultitouch: true,
                SupportsPressure: true,
                SupportsButtonClick: true,
                IsPreferredInterface: true,
                CanOpenEventStream: true,
                AccessError: "ok");
            LinuxTrackpadBinding binding = new(TrackpadSide.Left, device);

            using (LinuxAtpCapCaptureWriter writer = new(capturePath))
            {
                InputFrame baseline = new()
                {
                    ArrivalQpcTicks = 1_000,
                    ReportId = 0xEE,
                    ScanTime = 1,
                    ContactCount = 0,
                    IsButtonClicked = 0
                };
                writer.WriteFrame(new LinuxRuntimeFrame(
                    binding,
                    new LinuxEvdevFrameSnapshot(
                        DeviceNode: device.DeviceNode,
                        MinX: -3678,
                        MinY: -2478,
                        MaxX: 7612,
                        MaxY: 5065,
                        FrameSequence: 1,
                        Frame: baseline)));

                InputFrame active = new()
                {
                    ArrivalQpcTicks = 2_000,
                    ReportId = 0xEE,
                    ScanTime = 2,
                    ContactCount = 1,
                    IsButtonClicked = 1
                };
                active.SetContact(0, new ContactFrame(1, 1200, 800, 0x03, Pressure: 64, Phase: 0, HasForceData: false));
                writer.WriteFrame(new LinuxRuntimeFrame(
                    binding,
                    new LinuxEvdevFrameSnapshot(
                        DeviceNode: device.DeviceNode,
                        MinX: -3678,
                        MinY: -2478,
                        MaxX: 7612,
                        MaxY: 5065,
                        FrameSequence: 2,
                        Frame: active)));

                InputFrame released = new()
                {
                    ArrivalQpcTicks = 3_000,
                    ReportId = 0xEE,
                    ScanTime = 3,
                    ContactCount = 0,
                    IsButtonClicked = 0
                };
                writer.WriteFrame(new LinuxRuntimeFrame(
                    binding,
                    new LinuxEvdevFrameSnapshot(
                        DeviceNode: device.DeviceNode,
                        MinX: -3678,
                        MinY: -2478,
                        MaxX: 7612,
                        MaxY: 5065,
                        FrameSequence: 3,
                        Frame: released)));
            }

            LinuxAtpCapSummaryResult summary = LinuxAtpCapReplayRunner.Summarize(capturePath);
            if (!summary.Success ||
                !summary.Summary.Contains("frames=3", StringComparison.Ordinal) ||
                !summary.Summary.Contains("buttonPressedFrames=1", StringComparison.Ordinal) ||
                !summary.Summary.Contains("buttonDownEdges=1", StringComparison.Ordinal) ||
                !summary.Summary.Contains("buttonUpEdges=1", StringComparison.Ordinal))
            {
                failure = $"Synthetic Linux .atpcap summary failed: {summary.Summary}";
                return false;
            }

            LinuxRuntimeConfiguration configuration = new LinuxAppRuntime().LoadReplayConfiguration();
            LinuxAtpCapReplayResult replay = LinuxAtpCapReplayRunner.Replay(capturePath, configuration, tracePath);
            if (!replay.Success)
            {
                failure = "Synthetic Linux .atpcap replay failed.";
                return false;
            }

            if (replay.Metrics.FramesSeen < 4 || replay.Metrics.FramesParsed < 3 || replay.Metrics.FramesDispatched < 3)
            {
                failure = "Synthetic Linux .atpcap replay metrics were incomplete.";
                return false;
            }

            if (replay.CaptureFingerprint == 0 || replay.DispatchFingerprint == 0)
            {
                failure = "Synthetic Linux .atpcap replay fingerprints were not populated.";
                return false;
            }

            if (!File.Exists(tracePath))
            {
                failure = "Synthetic Linux replay trace was not created.";
                return false;
            }

            LinuxAtpCapFixtureWriteResult fixtureWrite = LinuxAtpCapFixtureRunner.WriteFixture(capturePath, fixturePath, configuration);
            if (!fixtureWrite.Success || !File.Exists(fixturePath))
            {
                failure = $"Synthetic Linux fixture generation failed: {fixtureWrite.Summary}";
                return false;
            }

            LinuxAtpCapFixtureCheckResult fixtureCheck = LinuxAtpCapFixtureRunner.CheckFixture(capturePath, fixturePath, configuration, traceOutputPath: null);
            if (!fixtureCheck.Success)
            {
                failure = $"Synthetic Linux fixture check failed: {fixtureCheck.Summary}";
                return false;
            }

            failure = string.Empty;
            return true;
        }
        catch (Exception ex)
        {
            failure = $"Synthetic Linux .atpcap round-trip failed: {ex.Message}";
            return false;
        }
        finally
        {
            try
            {
                if (Directory.Exists(tempRoot))
                {
                    Directory.Delete(tempRoot, recursive: true);
                }
            }
            catch
            {
            }
        }
    }

    private static bool CanResolveLinuxKey(DispatchSemanticCode semanticCode, ushort virtualKey)
    {
        return (semanticCode != DispatchSemanticCode.None && LinuxKeyCodeMapper.TryMapSemanticCode(semanticCode, out _)) ||
               (virtualKey != 0 && LinuxKeyCodeMapper.TryMapKey(virtualKey, out _));
    }

    private static bool ValidateLinuxForceThresholdDispatch(out string failure)
    {
        const ushort maxX = 7612;
        const ushort maxY = 5065;
        TrackpadLayoutPreset preset = TrackpadLayoutPreset.SixByThree;
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        KeyLayout rightLayout = LayoutBuilder.BuildLayout(preset, 160.0, 114.9, 18.0, 17.0, columns, mirrored: false);
        NormalizedRect keyRect = rightLayout.Rects[0][0];
        ushort keyX = (ushort)Math.Clamp((int)Math.Round((keyRect.X + (keyRect.Width * 0.5)) * maxX), 1, maxX - 1);
        ushort keyY = (ushort)Math.Clamp((int)Math.Round((keyRect.Y + (keyRect.Height * 0.5)) * maxY), 1, maxY - 1);

        UserSettings settings = new()
        {
            LayoutPresetName = preset.Name,
            ForceMin = 200,
            ForceCap = 255
        };
        settings.NormalizeRanges();

        using RecordingDispatcher dispatcher = new();
        using TouchProcessorRuntimeHost host = new(dispatcher, KeymapStore.LoadBundledDefault(), preset, settings);

        long now = 0;
        host.Post(new TrackpadFrameEnvelope(
            TrackpadSide.Right,
            MakeFrame(contactCount: 1, x: keyX, y: keyY, pressure: 32, hasForceData: true),
            maxX,
            maxY,
            now));
        now += 1;
        host.Post(new TrackpadFrameEnvelope(TrackpadSide.Right, MakeFrame(contactCount: 0), maxX, maxY, now));
        if (!dispatcher.WaitForDispatchCount(0, timeoutMs: 150))
        {
            failure = "Low-force key tap was not suppressed by shared Force Min/Max settings.";
            return false;
        }

        now += 10;
        host.Post(new TrackpadFrameEnvelope(
            TrackpadSide.Right,
            MakeFrame(contactCount: 1, x: keyX, y: keyY, pressure: 240, hasForceData: true),
            maxX,
            maxY,
            now));
        now += 1;
        host.Post(new TrackpadFrameEnvelope(TrackpadSide.Right, MakeFrame(contactCount: 0), maxX, maxY, now));
        if (!dispatcher.WaitForDispatchCount(1, timeoutMs: 150))
        {
            failure = "High-force key tap did not dispatch when inside the shared Force Min/Max window.";
            return false;
        }

        DispatchEvent[] events = dispatcher.Snapshot();
        if (events.Length != 1 || events[0].Kind != DispatchEventKind.KeyTap)
        {
            failure = $"Unexpected dispatch sequence for force-threshold validation (events={events.Length}).";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateLinuxAssemblerForceData(out string failure)
    {
        LinuxMtFrameAssembler assembler = new(
            slotCount: 1,
            maxX: 1000,
            maxY: 1000,
            hasMtPressureData: true);
        assembler.SelectSlot(0);
        assembler.SetTrackingId(7);
        assembler.SetPositionX(320);
        assembler.SetPositionY(480);
        assembler.SetPressure(192);

        InputFrame mtFrame = assembler.CommitFrame(timestampTicks: 1);
        if (mtFrame.GetClampedContactCount() != 1)
        {
            failure = "Linux multitouch assembler did not emit the expected slot contact.";
            return false;
        }

        ContactFrame mtContact = mtFrame.GetContact(0);
        if (!mtContact.HasForceData || mtContact.Pressure8 != 192 || mtContact.ForceNorm <= 0)
        {
            failure = "Linux multitouch assembler did not preserve force-capable pressure data.";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateMagicTrackpadSelectionHeuristic(out string failure)
    {
        if (!LinuxTrackpadEnumerator.IsMagicTrackpadCandidateName("Apple Inc. Magic Trackpad") ||
            !LinuxTrackpadEnumerator.IsMagicTrackpadCandidateName("Apple Inc. Magic Trackpad USB-C"))
        {
            failure = "Magic Trackpad enumeration heuristic no longer recognizes the validated Apple Bluetooth/USB names.";
            return false;
        }

        if (LinuxTrackpadEnumerator.IsMagicTrackpadCandidateName("Logitech M720 Triathlon") ||
            LinuxTrackpadEnumerator.IsMagicTrackpadCandidateName("JLabs Augur Mouse"))
        {
            failure = "Magic Trackpad enumeration heuristic started matching non-trackpad devices.";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateLinuxActuatorDescriptorParsing(out string failure)
    {
        byte[] usbActuatorDescriptor = Convert.FromHexString("0600FF090DA1010600FF090D150026FF007508853F960F008102090D8553963F009102C0");
        if (!LinuxMagicTrackpadActuatorProbe.TryParseActuatorOutputReportLength(usbActuatorDescriptor, out int outputReportBytes) ||
            outputReportBytes != 64)
        {
            failure = "Linux actuator HID descriptor parsing no longer recognizes the validated Magic Trackpad actuator interface.";
            return false;
        }

        byte[] bluetoothTouchDescriptor = Convert.FromHexString("05010902A10185020509190129021500250195027501810295017506810305010901A1001681FF267F0036C3FE463D016513550D09300931750895028106750895048101C00602FF09558555150026FF0075089540B1A2C00600FF0914A101859005847501950315002501096105850944094681029505810175089501150026FF0009658102C000");
        if (LinuxMagicTrackpadActuatorProbe.TryParseActuatorOutputReportLength(bluetoothTouchDescriptor, out _))
        {
            failure = "Linux actuator HID descriptor parsing started treating the validated Bluetooth touch interface as an actuator.";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static InputFrame MakeFrame(int contactCount, ushort x = 0, ushort y = 0, byte pressure = 0, bool hasForceData = false)
    {
        InputFrame frame = new()
        {
            ArrivalQpcTicks = 0,
            ReportId = 0xEE,
            ScanTime = 0,
            ContactCount = (byte)contactCount,
            IsButtonClicked = 0
        };

        if (contactCount > 0)
        {
            frame.SetContact(0, new ContactFrame(1, x, y, 0x03, pressure, Phase: 0, HasForceData: hasForceData));
        }

        return frame;
    }

    private sealed class RecordingDispatcher : IInputDispatcher
    {
        private readonly object _gate = new();
        private readonly List<DispatchEvent> _events = [];

        public void Dispatch(in DispatchEvent dispatchEvent)
        {
            lock (_gate)
            {
                _events.Add(dispatchEvent);
            }
        }

        public void Tick(long nowTicks)
        {
            _ = nowTicks;
        }

        public DispatchEvent[] Snapshot()
        {
            lock (_gate)
            {
                return _events.ToArray();
            }
        }

        public bool WaitForDispatchCount(int expectedCount, int timeoutMs)
        {
            long deadline = Environment.TickCount64 + Math.Max(1, timeoutMs);
            while (Environment.TickCount64 < deadline)
            {
                lock (_gate)
                {
                    if (_events.Count == expectedCount)
                    {
                        return true;
                    }
                }

                Thread.Sleep(5);
            }

            lock (_gate)
            {
                return _events.Count == expectedCount;
            }
        }

        public void Dispose()
        {
        }
    }

    private static IEnumerable<string> EnumerateActionLabels(KeymapStore.KeymapFileModel keymap)
    {
        foreach (KeyValuePair<string, KeymapStore.LayoutKeymapData> layoutEntry in keymap.Layouts)
        {
            KeymapStore.LayoutKeymapData layout = layoutEntry.Value;
            if (layout.Mappings != null)
            {
                foreach (KeyValuePair<int, Dictionary<string, KeyMapping>> layerEntry in layout.Mappings)
                {
                    foreach (KeyValuePair<string, KeyMapping> mappingEntry in layerEntry.Value)
                    {
                        KeyMapping mapping = mappingEntry.Value;
                        if (!string.IsNullOrWhiteSpace(mapping.Primary?.Label))
                        {
                            yield return mapping.Primary.Label;
                        }

                        if (!string.IsNullOrWhiteSpace(mapping.Hold?.Label))
                        {
                            yield return mapping.Hold.Label;
                        }
                    }
                }
            }

            if (layout.CustomButtons == null)
            {
                continue;
            }

            foreach (KeyValuePair<int, List<CustomButton>> layerEntry in layout.CustomButtons)
            {
                List<CustomButton> buttons = layerEntry.Value;
                for (int index = 0; index < buttons.Count; index++)
                {
                    CustomButton button = buttons[index];
                    if (!string.IsNullOrWhiteSpace(button.Primary?.Label))
                    {
                        yield return button.Primary.Label;
                    }

                    if (!string.IsNullOrWhiteSpace(button.Hold?.Label))
                    {
                        yield return button.Hold.Label;
                    }
                }
            }
        }
    }
}
