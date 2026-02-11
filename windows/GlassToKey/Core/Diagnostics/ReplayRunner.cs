using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace GlassToKey;

internal sealed class ReplayRunner
{
    private const ushort DefaultMaxX = 7612;
    private const ushort DefaultMaxY = 5065;

    public ReplayRunResult Run(string capturePath, string? fixturePath, string? traceOutputPath = null, ReplayRunOptions? options = null)
    {
        ReplayExpectation? expectation = null;
        if (!string.IsNullOrWhiteSpace(fixturePath))
        {
            expectation = ReplayExpectation.Load(fixturePath!, capturePath);
            capturePath = expectation.CapturePath;
        }

        bool collectTrace = !string.IsNullOrWhiteSpace(traceOutputPath);
        ReplayRunMetrics first = ExecuteCapture(capturePath, "replay-pass-1", collectTrace, options, out ReplayTraceData? traceData);
        ReplayRunMetrics second = ExecuteCapture(capturePath, "replay-pass-2", collectTrace: false, options, out _);
        bool deterministic = first.Fingerprint == second.Fingerprint &&
                             first.EngineIntentFingerprint == second.EngineIntentFingerprint &&
                             first.EngineTransitionCount == second.EngineTransitionCount &&
                             first.DispatchFingerprint == second.DispatchFingerprint &&
                             first.DispatchEventCount == second.DispatchEventCount &&
                             first.DispatchEnqueued == second.DispatchEnqueued &&
                             first.DispatchSuppressedTypingDisabled == second.DispatchSuppressedTypingDisabled &&
                             first.DispatchSuppressedRingFull == second.DispatchSuppressedRingFull &&
                             first.ModifierUnbalancedCount == second.ModifierUnbalancedCount &&
                             first.RepeatStartCount == second.RepeatStartCount &&
                             first.RepeatCancelCount == second.RepeatCancelCount &&
                             first.Metrics.FramesSeen == second.Metrics.FramesSeen &&
                             first.Metrics.FramesParsed == second.Metrics.FramesParsed &&
                             first.Metrics.FramesDispatched == second.Metrics.FramesDispatched &&
                             first.Metrics.FramesDropped == second.Metrics.FramesDropped;

        bool fixtureMatched = expectation?.Matches(first) ?? true;
        if (collectTrace && traceData != null)
        {
            WriteReplayTrace(Path.GetFullPath(traceOutputPath!), capturePath, first, traceData);
        }

        return new ReplayRunResult(capturePath, deterministic, fixtureMatched, first, second, expectation);
    }

    private static ReplayRunMetrics ExecuteCapture(
        string capturePath,
        string metricName,
        bool collectTrace,
        ReplayRunOptions? options,
        out ReplayTraceData? traceData)
    {
        traceData = null;
        FrameMetrics metrics = new(metricName);
        ulong fingerprint = 14695981039346656037ul;
        using InputCaptureReader reader = new(capturePath);

        KeymapStore keymap = options?.Keymap ?? KeymapStore.LoadBundledDefault();
        TrackpadLayoutPreset? layoutPreset = options?.LayoutPreset;
        TouchProcessorConfig? config = options?.Config;
        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(keymap, layoutPreset, config);
        using DispatchEventQueue dispatchQueue = new(capacity: 131072);
        using TouchProcessorActor actor = new(core, dispatchQueue: dispatchQueue);
        actor.SetDiagnosticsEnabled(collectTrace);
        ReplaySideMapper sideMapper = new(options?.SideByTag);

        bool hasBaseQpc = false;
        long baseQpcTicks = 0;
        while (reader.TryReadNext(out CaptureRecord record))
        {
            long started = Stopwatch.GetTimestamp();
            metrics.RecordSeen();

            ReadOnlySpan<byte> payload = record.Payload.Span;
            if (payload.Length == 0)
            {
                metrics.RecordDropped(FrameDropReason.InvalidReportSize);
                continue;
            }

            RawInputDeviceInfo info = new(record.VendorId, record.ProductId, record.UsagePage, record.Usage);
            TrackpadDecoderProfile preferredProfile = record.DecoderProfile == TrackpadDecoderProfile.Legacy
                ? TrackpadDecoderProfile.Legacy
                : TrackpadDecoderProfile.Official;
            if (!TrackpadReportDecoder.TryDecode(payload, info, record.ArrivalQpcTicks, preferredProfile, out TrackpadDecodeResult decoded))
            {
                metrics.RecordDropped(FrameDropReason.NonMultitouchReport);
                continue;
            }

            metrics.RecordParsed();
            InputFrame frame = decoded.Frame;
            TrackpadSide side = sideMapper.Resolve(record.DeviceIndex, record.DeviceHash, record.SideHint);

            if (!hasBaseQpc)
            {
                baseQpcTicks = record.ArrivalQpcTicks;
                hasBaseQpc = true;
            }

            long relativeQpc = record.ArrivalQpcTicks - baseQpcTicks;
            long engineTicks = (long)Math.Round(relativeQpc * (double)Stopwatch.Frequency / reader.HeaderQpcFrequency);
            actor.Post(side, in frame, DefaultMaxX, DefaultMaxY, engineTicks);

            metrics.RecordDispatched(started);
            fingerprint = Fingerprint(fingerprint, record, in frame);
        }

        actor.WaitForIdle(5000);
        TouchProcessorSnapshot snapshot = actor.Snapshot();
        IntentTransition[] transitions = new IntentTransition[512];
        int transitionCount = actor.CopyIntentTransitions(transitions);
        ulong transitionFingerprint = snapshot.IntentTraceFingerprint;
        for (int i = 0; i < transitionCount; i++)
        {
            transitionFingerprint = Mix(transitionFingerprint, (ulong)transitions[i].Previous);
            transitionFingerprint = Mix(transitionFingerprint, (ulong)transitions[i].Current);
            transitionFingerprint = Mix(transitionFingerprint, StableStringHash(transitions[i].Reason));
        }

        ulong dispatchFingerprint = 14695981039346656037ul;
        int dispatchCount = 0;
        int[] modifierBalance = new int[256];
        int repeatStarts = 0;
        int repeatCancels = 0;
        List<DispatchEvent>? dispatchEvents = collectTrace ? new List<DispatchEvent>(4096) : null;
        while (dispatchQueue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 0))
        {
            dispatchCount++;
            dispatchEvents?.Add(dispatchEvent);
            dispatchFingerprint = Mix(dispatchFingerprint, (ulong)dispatchEvent.Kind);
            dispatchFingerprint = Mix(dispatchFingerprint, dispatchEvent.VirtualKey);
            dispatchFingerprint = Mix(dispatchFingerprint, (ulong)dispatchEvent.MouseButton);
            dispatchFingerprint = Mix(dispatchFingerprint, dispatchEvent.RepeatToken);
            dispatchFingerprint = Mix(dispatchFingerprint, (ulong)dispatchEvent.Flags);
            dispatchFingerprint = Mix(dispatchFingerprint, (ulong)dispatchEvent.Side);

            if (dispatchEvent.Kind == DispatchEventKind.ModifierDown && dispatchEvent.VirtualKey < modifierBalance.Length)
            {
                modifierBalance[dispatchEvent.VirtualKey]++;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.ModifierUp && dispatchEvent.VirtualKey < modifierBalance.Length)
            {
                modifierBalance[dispatchEvent.VirtualKey]--;
            }

            if (dispatchEvent.Kind == DispatchEventKind.KeyDown &&
                (dispatchEvent.Flags & DispatchEventFlags.Repeatable) != 0 &&
                dispatchEvent.RepeatToken != 0)
            {
                repeatStarts++;
            }
            else if (dispatchEvent.Kind == DispatchEventKind.KeyUp && dispatchEvent.RepeatToken != 0)
            {
                repeatCancels++;
            }
        }

        int modifierUnbalanced = 0;
        for (int i = 0; i < modifierBalance.Length; i++)
        {
            if (modifierBalance[i] != 0)
            {
                modifierUnbalanced++;
            }
        }

        if (collectTrace)
        {
            EngineDiagnosticEvent[] diagnostics = new EngineDiagnosticEvent[8192];
            int diagnosticCount = actor.CopyDiagnostics(diagnostics);
            IntentTransition[] transitionCopy = transitions.AsSpan(0, transitionCount).ToArray();
            DispatchEvent[] dispatchCopy = dispatchEvents?.ToArray() ?? Array.Empty<DispatchEvent>();
            EngineDiagnosticEvent[] diagnosticCopy = diagnostics.AsSpan(0, diagnosticCount).ToArray();
            traceData = new ReplayTraceData(transitionCopy, dispatchCopy, diagnosticCopy);
        }

        return new ReplayRunMetrics(
            Metrics: metrics.CreateSnapshot(),
            Fingerprint: fingerprint,
            EngineIntentFingerprint: transitionFingerprint,
            EngineTransitionCount: transitionCount,
            DispatchFingerprint: dispatchFingerprint,
            DispatchEventCount: dispatchCount,
            DispatchEnqueued: snapshot.DispatchEnqueued,
            DispatchSuppressedTypingDisabled: snapshot.DispatchSuppressedTypingDisabled,
            DispatchSuppressedRingFull: snapshot.DispatchSuppressedRingFull,
            ModifierUnbalancedCount: modifierUnbalanced,
            RepeatStartCount: repeatStarts,
            RepeatCancelCount: repeatCancels);
    }

    private static void WriteReplayTrace(
        string outputPath,
        string capturePath,
        in ReplayRunMetrics metrics,
        ReplayTraceData traceData)
    {
        string? dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrWhiteSpace(dir))
        {
            Directory.CreateDirectory(dir);
        }

        ReplayTraceDump dump = new()
        {
            CapturePath = capturePath,
            GeneratedUtc = DateTime.UtcNow,
            FirstPass = metrics,
            IntentTransitions = traceData.IntentTransitions,
            DispatchEvents = traceData.DispatchEvents,
            EngineDiagnostics = traceData.EngineDiagnostics
        };
        JsonSerializerOptions options = new()
        {
            WriteIndented = true
        };
        options.Converters.Add(new JsonStringEnumConverter());
        File.WriteAllText(outputPath, JsonSerializer.Serialize(dump, options));
    }

    private static ulong Fingerprint(ulong seed, CaptureRecord record, in InputFrame report)
    {
        seed = Mix(seed, (ulong)record.DeviceHash);
        seed = Mix(seed, (ulong)record.DeviceIndex);
        seed = Mix(seed, report.ReportId);
        seed = Mix(seed, report.ScanTime);
        seed = Mix(seed, report.ContactCount);
        seed = Mix(seed, report.IsButtonClicked);
        int count = report.GetClampedContactCount();
        for (int i = 0; i < count; i++)
        {
            ContactFrame c = report.GetContact(i);
            seed = Mix(seed, c.Flags);
            seed = Mix(seed, c.Id);
            seed = Mix(seed, c.X);
            seed = Mix(seed, c.Y);
        }

        return seed;
    }

    private static ulong Mix(ulong hash, ulong value)
    {
        hash ^= value;
        hash *= 1099511628211ul;
        return hash;
    }

    private static ulong StableStringHash(string text)
    {
        ulong hash = 14695981039346656037ul;
        for (int i = 0; i < text.Length; i++)
        {
            ushort ch = text[i];
            hash = Mix(hash, (byte)(ch & 0xFF));
            hash = Mix(hash, (byte)((ch >> 8) & 0xFF));
        }

        return hash;
    }

    private sealed class ReplaySideMapper
    {
        private readonly IReadOnlyDictionary<ReplayDeviceTag, TrackpadSide>? _explicitSides;
        private readonly Dictionary<ReplayDeviceTag, TrackpadSide> _sides = new();
        private int _next;

        public ReplaySideMapper(IReadOnlyDictionary<ReplayDeviceTag, TrackpadSide>? explicitSides = null)
        {
            _explicitSides = explicitSides;
        }

        public TrackpadSide Resolve(int deviceIndex, uint deviceHash, CaptureSideHint sideHint)
        {
            ReplayDeviceTag key = new(deviceIndex, deviceHash);
            if (_explicitSides != null && _explicitSides.TryGetValue(key, out TrackpadSide explicitSide))
            {
                return explicitSide;
            }

            if (sideHint == CaptureSideHint.Left)
            {
                _sides[key] = TrackpadSide.Left;
                return TrackpadSide.Left;
            }

            if (sideHint == CaptureSideHint.Right)
            {
                _sides[key] = TrackpadSide.Right;
                return TrackpadSide.Right;
            }

            if (_sides.TryGetValue(key, out TrackpadSide side))
            {
                return side;
            }

            side = _next == 0 ? TrackpadSide.Left : TrackpadSide.Right;
            _next = (_next + 1) % 2;
            _sides[key] = side;
            return side;
        }
    }
}

internal readonly record struct ReplayDeviceTag(int DeviceIndex, uint DeviceHash);

internal readonly record struct ReplayRunMetrics(
    FrameMetricsSnapshot Metrics,
    ulong Fingerprint,
    ulong EngineIntentFingerprint,
    int EngineTransitionCount,
    ulong DispatchFingerprint,
    int DispatchEventCount,
    long DispatchEnqueued,
    long DispatchSuppressedTypingDisabled,
    long DispatchSuppressedRingFull,
    int ModifierUnbalancedCount,
    int RepeatStartCount,
    int RepeatCancelCount);

internal readonly record struct ReplayRunResult(
    string CapturePath,
    bool Deterministic,
    bool FixtureMatched,
    ReplayRunMetrics FirstPass,
    ReplayRunMetrics SecondPass,
    ReplayExpectation? Expectation)
{
    public bool Success => Deterministic && FixtureMatched;

    public string ToSummary()
    {
        string fingerprint = $"0x{FirstPass.Fingerprint:X16}";
        string expected = Expectation?.ExpectedFingerprint ?? "(none)";
        string intentTrace = $"0x{FirstPass.EngineIntentFingerprint:X16}";
        string dispatchTrace = $"0x{FirstPass.DispatchFingerprint:X16}";
        return string.Create(
            CultureInfo.InvariantCulture,
            $"Replay '{CapturePath}': deterministic={Deterministic}, fixtureMatched={FixtureMatched}, fingerprint={fingerprint}, expected={expected}, intentTrace={intentTrace}, intentTransitions={FirstPass.EngineTransitionCount}, dispatchTrace={dispatchTrace}, dispatchEvents={FirstPass.DispatchEventCount}, dispatchEnqueued={FirstPass.DispatchEnqueued}, suppressed={FirstPass.DispatchSuppressedTypingDisabled}, ringFull={FirstPass.DispatchSuppressedRingFull}, modifierUnbalanced={FirstPass.ModifierUnbalancedCount}, repeats={FirstPass.RepeatStartCount}/{FirstPass.RepeatCancelCount}, pass1={FirstPass.Metrics.ToSummary()}");
    }
}

internal sealed class ReplayTraceData
{
    public ReplayTraceData(
        IntentTransition[] intentTransitions,
        DispatchEvent[] dispatchEvents,
        EngineDiagnosticEvent[] engineDiagnostics)
    {
        IntentTransitions = intentTransitions;
        DispatchEvents = dispatchEvents;
        EngineDiagnostics = engineDiagnostics;
    }

    public IntentTransition[] IntentTransitions { get; }
    public DispatchEvent[] DispatchEvents { get; }
    public EngineDiagnosticEvent[] EngineDiagnostics { get; }
}

internal sealed class ReplayTraceDump
{
    public string CapturePath { get; set; } = string.Empty;
    public DateTime GeneratedUtc { get; set; }
    public ReplayRunMetrics FirstPass { get; set; }
    public IntentTransition[] IntentTransitions { get; set; } = Array.Empty<IntentTransition>();
    public DispatchEvent[] DispatchEvents { get; set; } = Array.Empty<DispatchEvent>();
    public EngineDiagnosticEvent[] EngineDiagnostics { get; set; } = Array.Empty<EngineDiagnosticEvent>();
}

internal sealed class ReplayRunOptions
{
    public ReplayRunOptions(
        KeymapStore keymap,
        TrackpadLayoutPreset layoutPreset,
        TouchProcessorConfig config,
        IReadOnlyDictionary<ReplayDeviceTag, TrackpadSide>? sideByTag = null)
    {
        Keymap = keymap;
        LayoutPreset = layoutPreset;
        Config = config;
        SideByTag = sideByTag;
    }

    public KeymapStore Keymap { get; }
    public TrackpadLayoutPreset LayoutPreset { get; }
    public TouchProcessorConfig Config { get; }
    public IReadOnlyDictionary<ReplayDeviceTag, TrackpadSide>? SideByTag { get; }
}

internal sealed class ReplayExpectation
{
    public string CapturePath { get; init; } = string.Empty;
    public string? ExpectedFingerprint { get; init; }
    public string? ExpectedIntentFingerprint { get; init; }
    public int? ExpectedIntentTransitions { get; init; }
    public string? ExpectedDispatchFingerprint { get; init; }
    public int? ExpectedDispatchEvents { get; init; }
    public long? ExpectedDispatchEnqueued { get; init; }
    public long? ExpectedDispatchSuppressedTypingDisabled { get; init; }
    public long? ExpectedDispatchSuppressedRingFull { get; init; }
    public int? ExpectedModifierUnbalanced { get; init; }
    public int? ExpectedRepeatStarts { get; init; }
    public int? ExpectedRepeatCancels { get; init; }
    public long? ExpectedFramesSeen { get; init; }
    public long? ExpectedFramesParsed { get; init; }
    public long? ExpectedFramesDispatched { get; init; }
    public long? ExpectedFramesDropped { get; init; }

    public bool Matches(in ReplayRunMetrics metrics)
    {
        if (!string.IsNullOrWhiteSpace(ExpectedFingerprint))
        {
            string actual = $"0x{metrics.Fingerprint:X16}";
            if (!string.Equals(actual, ExpectedFingerprint, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        if (!string.IsNullOrWhiteSpace(ExpectedIntentFingerprint))
        {
            string actualIntent = $"0x{metrics.EngineIntentFingerprint:X16}";
            if (!string.Equals(actualIntent, ExpectedIntentFingerprint, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        if (ExpectedIntentTransitions.HasValue && metrics.EngineTransitionCount != ExpectedIntentTransitions.Value) return false;
        if (!string.IsNullOrWhiteSpace(ExpectedDispatchFingerprint))
        {
            string actualDispatch = $"0x{metrics.DispatchFingerprint:X16}";
            if (!string.Equals(actualDispatch, ExpectedDispatchFingerprint, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        if (ExpectedDispatchEvents.HasValue && metrics.DispatchEventCount != ExpectedDispatchEvents.Value) return false;
        if (ExpectedDispatchEnqueued.HasValue && metrics.DispatchEnqueued != ExpectedDispatchEnqueued.Value) return false;
        if (ExpectedDispatchSuppressedTypingDisabled.HasValue && metrics.DispatchSuppressedTypingDisabled != ExpectedDispatchSuppressedTypingDisabled.Value) return false;
        if (ExpectedDispatchSuppressedRingFull.HasValue && metrics.DispatchSuppressedRingFull != ExpectedDispatchSuppressedRingFull.Value) return false;
        if (ExpectedModifierUnbalanced.HasValue && metrics.ModifierUnbalancedCount != ExpectedModifierUnbalanced.Value) return false;
        if (ExpectedRepeatStarts.HasValue && metrics.RepeatStartCount != ExpectedRepeatStarts.Value) return false;
        if (ExpectedRepeatCancels.HasValue && metrics.RepeatCancelCount != ExpectedRepeatCancels.Value) return false;
        if (ExpectedFramesSeen.HasValue && metrics.Metrics.FramesSeen != ExpectedFramesSeen.Value) return false;
        if (ExpectedFramesParsed.HasValue && metrics.Metrics.FramesParsed != ExpectedFramesParsed.Value) return false;
        if (ExpectedFramesDispatched.HasValue && metrics.Metrics.FramesDispatched != ExpectedFramesDispatched.Value) return false;
        if (ExpectedFramesDropped.HasValue && metrics.Metrics.FramesDropped != ExpectedFramesDropped.Value) return false;
        return true;
    }

    public static ReplayExpectation Load(string fixturePath, string fallbackCapturePath)
    {
        string text = File.ReadAllText(fixturePath);
        ReplayExpectationJson? json = JsonSerializer.Deserialize<ReplayExpectationJson>(text);
        if (json == null)
        {
            throw new InvalidDataException($"Fixture {fixturePath} is invalid JSON.");
        }

        string capturePath = json.capturePath;
        if (string.IsNullOrWhiteSpace(capturePath))
        {
            capturePath = fallbackCapturePath;
        }
        else if (!Path.IsPathFullyQualified(capturePath))
        {
            string fixtureDir = Path.GetDirectoryName(Path.GetFullPath(fixturePath)) ?? Directory.GetCurrentDirectory();
            capturePath = Path.GetFullPath(Path.Combine(fixtureDir, capturePath));
        }

        return new ReplayExpectation
        {
            CapturePath = capturePath,
            ExpectedFingerprint = json.expected?.fingerprint,
            ExpectedIntentFingerprint = json.expected?.intentFingerprint,
            ExpectedIntentTransitions = json.expected?.intentTransitions,
            ExpectedDispatchFingerprint = json.expected?.dispatchFingerprint,
            ExpectedDispatchEvents = json.expected?.dispatchEvents,
            ExpectedDispatchEnqueued = json.expected?.dispatchEnqueued,
            ExpectedDispatchSuppressedTypingDisabled = json.expected?.dispatchSuppressedTypingDisabled,
            ExpectedDispatchSuppressedRingFull = json.expected?.dispatchSuppressedRingFull,
            ExpectedModifierUnbalanced = json.expected?.modifierUnbalanced,
            ExpectedRepeatStarts = json.expected?.repeatStarts,
            ExpectedRepeatCancels = json.expected?.repeatCancels,
            ExpectedFramesSeen = json.expected?.framesSeen,
            ExpectedFramesParsed = json.expected?.framesParsed,
            ExpectedFramesDispatched = json.expected?.framesDispatched,
            ExpectedFramesDropped = json.expected?.framesDropped
        };
    }

    private sealed class ReplayExpectationJson
    {
        public string capturePath { get; set; } = string.Empty;
        public ReplayExpectationDetails? expected { get; set; }
    }

    private sealed class ReplayExpectationDetails
    {
        public string? fingerprint { get; set; }
        public string? intentFingerprint { get; set; }
        public int? intentTransitions { get; set; }
        public string? dispatchFingerprint { get; set; }
        public int? dispatchEvents { get; set; }
        public long? dispatchEnqueued { get; set; }
        public long? dispatchSuppressedTypingDisabled { get; set; }
        public long? dispatchSuppressedRingFull { get; set; }
        public int? modifierUnbalanced { get; set; }
        public int? repeatStarts { get; set; }
        public int? repeatCancels { get; set; }
        public long? framesSeen { get; set; }
        public long? framesParsed { get; set; }
        public long? framesDispatched { get; set; }
        public long? framesDropped { get; set; }
    }
}
