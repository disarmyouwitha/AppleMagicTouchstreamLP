using System.Diagnostics;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Runtime;

public readonly record struct LinuxAtpCapReplayVisualFrame(
    long OffsetStopwatchTicks,
    LinuxInputPreviewSnapshot PreviewSnapshot,
    LinuxDesktopRuntimeSnapshot RuntimeSnapshot);

public sealed class LinuxAtpCapReplayVisualData
{
    public LinuxAtpCapReplayVisualData(
        string sourcePath,
        LinuxAtpCapReplayVisualFrame[] frames)
    {
        SourcePath = sourcePath;
        Frames = frames;
    }

    public string SourcePath { get; }

    public LinuxAtpCapReplayVisualFrame[] Frames { get; }

    public long DurationStopwatchTicks => Frames.Length == 0 ? 0 : Frames[^1].OffsetStopwatchTicks;
}

public static class LinuxAtpCapReplayVisualLoader
{
    private const ushort DefaultMaxX = 7612;
    private const ushort DefaultMaxY = 5065;

    public static LinuxAtpCapReplayVisualData Load(string capturePath, LinuxRuntimeConfiguration configuration)
    {
        string fullPath = Path.GetFullPath(capturePath);
        List<LinuxAtpCapReplayVisualFrame> frames = [];
        Dictionary<TrackpadSide, LinuxInputPreviewTrackpadState> trackpads = new();
        AtpCapV3Compatibility compatibility = AtpCapV3Compatibility.None;
        LinuxReplayVisualSideMapper sideMapper = new();
        long firstArrivalQpc = 0;
        bool hasFirstArrival = false;

        using InputCaptureReader reader = new(fullPath);
        if (reader.HeaderVersion != InputCaptureFile.Version3)
        {
            throw new InvalidDataException("Linux replay visualizer currently supports only .atpcap version 3 captures.");
        }

        using TouchProcessorRuntimeHost host = new(new LinuxReplayVisualNullDispatcher(), configuration.Keymap, configuration.LayoutPreset, configuration.SharedProfile);
        while (reader.TryReadNext(out CaptureRecord record))
        {
            ReadOnlySpan<byte> payload = record.Payload.Span;
            if (payload.Length == 0)
            {
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

            if (!AtpCapV3Payload.TryParseFrame(payload, out AtpCapV3Frame parsed))
            {
                continue;
            }

            InputFrame frame = AtpCapV3Payload.ToInputFrame(parsed, record.ArrivalQpcTicks, DefaultMaxX, DefaultMaxY, compatibility.FlipY);
            if (!hasFirstArrival)
            {
                firstArrivalQpc = record.ArrivalQpcTicks;
                hasFirstArrival = true;
            }

            TrackpadSide side = sideMapper.Resolve(
                record.DeviceIndex,
                record.DeviceHash,
                AtpCapV3Payload.NormalizeSideHint(record.SideHint, compatibility));

            long relativeQpc = record.ArrivalQpcTicks - firstArrivalQpc;
            long offsetStopwatchTicks = (long)Math.Round(relativeQpc * (double)Stopwatch.Frequency / reader.HeaderQpcFrequency);
            TrackpadFrameEnvelope envelope = new(side, frame, DefaultMaxX, DefaultMaxY, offsetStopwatchTicks);
            host.Post(in envelope);
            host.TryGetSynchronizedSnapshot(4, out TouchProcessorRuntimeSnapshot runtimeSnapshot);

            trackpads[side] = BuildTrackpadState(side, record, frame, compatibility);
            LinuxInputPreviewSnapshot previewSnapshot = new(
                LinuxInputPreviewStatus.Running,
                "Replaying capture frames.",
                Failure: null,
                BuildOrderedTrackpadStates(trackpads));

            frames.Add(new LinuxAtpCapReplayVisualFrame(
                offsetStopwatchTicks,
                previewSnapshot,
                new LinuxDesktopRuntimeSnapshot(
                    LinuxDesktopRuntimeStatus.Running,
                    runtimeSnapshot.TypingEnabled,
                    runtimeSnapshot.KeyboardModeEnabled,
                    runtimeSnapshot.ActiveLayer,
                    DateTimeOffset.UtcNow,
                    "Replaying capture frames.",
                    Failure: null)));
        }

        return new LinuxAtpCapReplayVisualData(fullPath, [.. frames]);
    }

    private static LinuxInputPreviewTrackpadState BuildTrackpadState(
        TrackpadSide side,
        CaptureRecord record,
        in InputFrame frame,
        AtpCapV3Compatibility compatibility)
    {
        int count = frame.GetClampedContactCount();
        LinuxInputPreviewContact[] contacts = new LinuxInputPreviewContact[count];
        for (int index = 0; index < count; index++)
        {
            ContactFrame contact = frame.GetContact(index);
            contacts[index] = new LinuxInputPreviewContact(
                contact.Id,
                contact.X,
                contact.Y,
                contact.Pressure8,
                contact.TipSwitch,
                contact.Confidence);
        }

        return new LinuxInputPreviewTrackpadState(
            side,
            StableId: $"replay://{record.DeviceIndex}/{record.DeviceHash:X8}",
            DeviceNode: BuildReplayDeviceNode(record, compatibility),
            MaxX: DefaultMaxX,
            MaxY: DefaultMaxY,
            IsButtonPressed: frame.IsButtonPressed,
            ContactCount: count,
            FrameSequence: 0,
            BindingStatus: LinuxRuntimeBindingStatus.Streaming,
            BindingMessage: "Replaying capture frames.",
            Contacts: contacts);
    }

    private static string BuildReplayDeviceNode(CaptureRecord record, AtpCapV3Compatibility compatibility)
    {
        string suffix = compatibility == AtpCapV3Compatibility.None ? string.Empty : $" ({compatibility})";
        return $"replay://dev/{record.DeviceIndex}/{record.DeviceHash:X8}{suffix}";
    }

    private static IReadOnlyList<LinuxInputPreviewTrackpadState> BuildOrderedTrackpadStates(
        Dictionary<TrackpadSide, LinuxInputPreviewTrackpadState> trackpads)
    {
        List<LinuxInputPreviewTrackpadState> ordered = [];
        if (trackpads.TryGetValue(TrackpadSide.Left, out LinuxInputPreviewTrackpadState? left))
        {
            ordered.Add(left);
        }

        if (trackpads.TryGetValue(TrackpadSide.Right, out LinuxInputPreviewTrackpadState? right))
        {
            ordered.Add(right);
        }

        return ordered;
    }

    private sealed class LinuxReplayVisualNullDispatcher : IInputDispatcher
    {
        public void Dispatch(in DispatchEvent dispatchEvent)
        {
        }

        public void Tick(long timestampTicks)
        {
        }

        public void Dispose()
        {
        }
    }

    private sealed class LinuxReplayVisualSideMapper
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
}
