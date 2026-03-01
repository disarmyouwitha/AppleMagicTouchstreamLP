using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using GlassToKey;
using GlassToKey.Linux.Runtime;

namespace GlassToKey.Linux;

internal readonly record struct LinuxAtpCapReplayResult(
    bool Success,
    string CapturePath,
    FrameMetricsSnapshot Metrics,
    ulong CaptureFingerprint,
    ulong DispatchFingerprint,
    int DispatchEventCount,
    int IntentTransitionCount,
    string Summary);

internal readonly record struct LinuxAtpCapSummaryResult(
    bool Success,
    string Summary);

internal static class LinuxAtpCapReplayRunner
{
    private const ushort DefaultMaxX = 7612;
    private const ushort DefaultMaxY = 5065;

    public static LinuxAtpCapReplayResult Replay(
        string capturePath,
        LinuxRuntimeConfiguration configuration,
        string? traceOutputPath)
    {
        string fullPath = Path.GetFullPath(capturePath);
        FrameMetrics metrics = new("linux-replay");
        using InputCaptureReader reader = new(fullPath);
        if (reader.HeaderVersion != InputCaptureFile.Version3)
        {
            return new LinuxAtpCapReplayResult(false, fullPath, metrics.CreateSnapshot(), 0, 0, 0, 0, $"Replay '{fullPath}': only capture version 3 is supported on Linux right now.");
        }

        TouchProcessorCore core = TouchProcessorFactory.CreateDefault(configuration.Keymap, configuration.LayoutPreset);
        using DispatchEventQueue dispatchQueue = new(capacity: 131072);
        using TouchProcessorActor actor = new(core, dispatchQueue: dispatchQueue);
        actor.SetDiagnosticsEnabled(!string.IsNullOrWhiteSpace(traceOutputPath));

        long baseQpcTicks = 0;
        bool hasBaseQpc = false;
        AtpCapV3Compatibility compatibility = AtpCapV3Compatibility.None;
        LinuxReplaySideMapper sideMapper = new();
        ulong captureFingerprint = 14695981039346656037UL;

        while (reader.TryReadNext(out CaptureRecord record))
        {
            metrics.RecordSeen();
            ReadOnlySpan<byte> payload = record.Payload.Span;
            if (payload.Length == 0)
            {
                metrics.RecordDropped(FrameDropReason.InvalidReportSize);
                continue;
            }

            if (record.DeviceIndex == -1)
            {
                if (AtpCapV3Payload.TryParseMeta(payload, out AtpCapV3Meta meta))
                {
                    compatibility = AtpCapV3Payload.ResolveCompatibility(meta);
                }

                continue;
            }

            if (!AtpCapV3Payload.TryParseFrame(payload, out AtpCapV3Frame frame))
            {
                metrics.RecordDropped(FrameDropReason.ParseFailed);
                continue;
            }

            InputFrame mapped = AtpCapV3Payload.ToInputFrame(frame, record.ArrivalQpcTicks, DefaultMaxX, DefaultMaxY, compatibility.FlipY);
            metrics.RecordParsed();

            if (!hasBaseQpc)
            {
                baseQpcTicks = record.ArrivalQpcTicks;
                hasBaseQpc = true;
            }

            TrackpadSide side = sideMapper.Resolve(record.DeviceIndex, record.DeviceHash, AtpCapV3Payload.NormalizeSideHint(record.SideHint, compatibility));
            captureFingerprint = Fingerprint(captureFingerprint, record, in mapped, side);
            long relativeQpc = record.ArrivalQpcTicks - baseQpcTicks;
            long engineTicks = (long)Math.Round(relativeQpc * (double)Stopwatch.Frequency / reader.HeaderQpcFrequency);
            long started = Stopwatch.GetTimestamp();
            actor.Post(side, in mapped, DefaultMaxX, DefaultMaxY, engineTicks);
            metrics.RecordDispatched(started);
        }

        actor.WaitForIdle(5000);
        ulong dispatchFingerprint = 14695981039346656037UL;
        int dispatchCount = 0;
        List<DispatchEvent>? dispatchEvents = !string.IsNullOrWhiteSpace(traceOutputPath) ? [] : null;
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
        }

        IntentTransition[] transitions = new IntentTransition[512];
        int transitionCount = actor.CopyIntentTransitions(transitions);
        FrameMetricsSnapshot snapshot = metrics.CreateSnapshot();
        if (!string.IsNullOrWhiteSpace(traceOutputPath))
        {
            WriteTrace(traceOutputPath!, fullPath, snapshot, dispatchEvents?.ToArray() ?? Array.Empty<DispatchEvent>(), transitions.AsSpan(0, transitionCount).ToArray(), actor);
        }

        string summary = string.Create(
            CultureInfo.InvariantCulture,
            $"Replay '{fullPath}': captureTrace=0x{captureFingerprint:X16}, dispatchTrace=0x{dispatchFingerprint:X16}, dispatchEvents={dispatchCount}, intentTransitions={transitionCount}, metrics={snapshot.ToSummary()}");
        return new LinuxAtpCapReplayResult(true, fullPath, snapshot, captureFingerprint, dispatchFingerprint, dispatchCount, transitionCount, summary);
    }

    public static LinuxAtpCapSummaryResult Summarize(string capturePath)
    {
        string fullPath = Path.GetFullPath(capturePath);
        using InputCaptureReader reader = new(fullPath);
        int metaRecords = 0;
        int frameRecords = 0;
        int parsedFrames = 0;
        int maxContacts = 0;
        int buttonPressedFrames = 0;
        int buttonDownEdges = 0;
        int buttonUpEdges = 0;
        long firstArrival = 0;
        long lastArrival = 0;
        bool hasArrival = false;
        bool previousButtonPressed = false;
        bool hasPreviousButton = false;
        HashSet<string> devices = new(StringComparer.OrdinalIgnoreCase);

        while (reader.TryReadNext(out CaptureRecord record))
        {
            if (record.DeviceIndex == -1)
            {
                metaRecords++;
                continue;
            }

            frameRecords++;
            string deviceKey = $"{record.DeviceIndex}:{record.DeviceHash:X8}";
            devices.Add(deviceKey);

            if (!hasArrival)
            {
                firstArrival = record.ArrivalQpcTicks;
                hasArrival = true;
            }

            lastArrival = record.ArrivalQpcTicks;
            if (reader.HeaderVersion == InputCaptureFile.Version3 &&
                AtpCapV3Payload.TryParseFrame(record.Payload.Span, out AtpCapV3Frame frame))
            {
                parsedFrames++;
                maxContacts = Math.Max(maxContacts, frame.ContactCount);
                bool buttonPressed = (frame.Flags & AtpCapV3Payload.FrameFlagButtonClicked) != 0;
                if (buttonPressed)
                {
                    buttonPressedFrames++;
                }

                if (hasPreviousButton)
                {
                    if (!previousButtonPressed && buttonPressed)
                    {
                        buttonDownEdges++;
                    }
                    else if (previousButtonPressed && !buttonPressed)
                    {
                        buttonUpEdges++;
                    }
                }

                previousButtonPressed = buttonPressed;
                hasPreviousButton = true;
            }
        }

        double durationSeconds = hasArrival
            ? (lastArrival - firstArrival) / (double)reader.HeaderQpcFrequency
            : 0.0;

        string summary = string.Create(
            CultureInfo.InvariantCulture,
            $"Capture '{fullPath}': version={reader.HeaderVersion}, meta={metaRecords}, frames={frameRecords}, parsedFrames={parsedFrames}, devices={devices.Count}, duration_s={durationSeconds:F3}, maxContacts={maxContacts}, buttonPressedFrames={buttonPressedFrames}, buttonDownEdges={buttonDownEdges}, buttonUpEdges={buttonUpEdges}");
        return new LinuxAtpCapSummaryResult(true, summary);
    }

    private static void WriteTrace(
        string outputPath,
        string capturePath,
        in FrameMetricsSnapshot metrics,
        DispatchEvent[] dispatchEvents,
        IntentTransition[] transitions,
        TouchProcessorActor actor)
    {
        string? directory = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        EngineDiagnosticEvent[] diagnostics = new EngineDiagnosticEvent[8192];
        int diagnosticCount = actor.CopyDiagnostics(diagnostics);
        LinuxReplayTraceDump dump = new()
        {
            CapturePath = capturePath,
            GeneratedUtc = DateTime.UtcNow,
            Metrics = metrics,
            DispatchEvents = dispatchEvents,
            IntentTransitions = transitions,
            EngineDiagnostics = diagnostics.AsSpan(0, diagnosticCount).ToArray()
        };

        JsonSerializerOptions options = new()
        {
            WriteIndented = true
        };
        options.Converters.Add(new JsonStringEnumConverter());
        File.WriteAllText(outputPath, JsonSerializer.Serialize(dump, options));
    }

    private static ulong Mix(ulong hash, ulong value)
    {
        hash ^= value;
        hash *= 1099511628211UL;
        return hash;
    }

    private static ulong Fingerprint(ulong seed, CaptureRecord record, in InputFrame frame, TrackpadSide side)
    {
        seed = Mix(seed, (ulong)record.DeviceHash);
        seed = Mix(seed, (ulong)record.DeviceIndex);
        seed = Mix(seed, (ulong)side);
        seed = Mix(seed, frame.ReportId);
        seed = Mix(seed, frame.ScanTime);
        seed = Mix(seed, frame.ContactCount);
        seed = Mix(seed, frame.IsButtonClicked);
        int count = frame.GetClampedContactCount();
        for (int index = 0; index < count; index++)
        {
            ContactFrame contact = frame.GetContact(index);
            seed = Mix(seed, contact.Flags);
            seed = Mix(seed, contact.Id);
            seed = Mix(seed, contact.X);
            seed = Mix(seed, contact.Y);
        }

        return seed;
    }

    private sealed class LinuxReplaySideMapper
    {
        private readonly Dictionary<(int DeviceIndex, uint DeviceHash), TrackpadSide> _sides = new();
        private int _next;

        public TrackpadSide Resolve(int deviceIndex, uint deviceHash, CaptureSideHint sideHint)
        {
            (int, uint) key = (deviceIndex, deviceHash);
            if (_sides.TryGetValue(key, out TrackpadSide side))
            {
                return side;
            }

            side = sideHint switch
            {
                CaptureSideHint.Left => TrackpadSide.Left,
                CaptureSideHint.Right => TrackpadSide.Right,
                _ => (_next++ & 1) == 0 ? TrackpadSide.Left : TrackpadSide.Right
            };
            _sides[key] = side;
            return side;
        }
    }

    private sealed class LinuxReplayTraceDump
    {
        public string CapturePath { get; set; } = string.Empty;
        public DateTime GeneratedUtc { get; set; }
        public FrameMetricsSnapshot Metrics { get; set; }
        public DispatchEvent[] DispatchEvents { get; set; } = Array.Empty<DispatchEvent>();
        public IntentTransition[] IntentTransitions { get; set; } = Array.Empty<IntentTransition>();
        public EngineDiagnosticEvent[] EngineDiagnostics { get; set; } = Array.Empty<EngineDiagnosticEvent>();
    }
}
