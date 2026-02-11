using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

namespace GlassToKey;

internal readonly record struct ReplayVisualFrame(long OffsetStopwatchTicks, RawInputDeviceSnapshot Snapshot, InputFrame Frame);

internal sealed class ReplayVisualData
{
    public ReplayVisualData(
        string sourcePath,
        ReplayVisualFrame[] frames,
        HidDeviceInfo[] devices,
        ReplayLoadStats stats)
    {
        SourcePath = sourcePath;
        Frames = frames;
        Devices = devices;
        Stats = stats;
    }

    public string SourcePath { get; }
    public ReplayVisualFrame[] Frames { get; }
    public HidDeviceInfo[] Devices { get; }
    public ReplayLoadStats Stats { get; }
}

internal readonly record struct ReplayLoadStats(
    int RecordsRead,
    int FramesParsed,
    int DroppedInvalidSize,
    int DroppedNonMultitouch,
    int DroppedParseError);

internal static class ReplayVisualLoader
{
    public static ReplayVisualData Load(string capturePath)
    {
        string fullPath = Path.GetFullPath(capturePath);
        List<ReplayVisualFrame> frames = new();
        Dictionary<(int, uint), ReplayDeviceAccumulator> devicesByTag = new();

        int recordsRead = 0;
        int framesParsed = 0;
        int droppedInvalidSize = 0;
        int droppedNonMultitouch = 0;
        int droppedParseError = 0;
        long firstArrivalTicks = -1;

        using InputCaptureReader reader = new(fullPath);
        while (reader.TryReadNext(out CaptureRecord record))
        {
            recordsRead++;
            ReadOnlySpan<byte> payload = record.Payload.Span;
            if (payload.Length == 0)
            {
                droppedInvalidSize++;
                continue;
            }

            RawInputDeviceInfo info = new(record.VendorId, record.ProductId, record.UsagePage, record.Usage);
            if (!TrackpadReportDecoder.TryDecode(payload, info, record.ArrivalQpcTicks, out TrackpadDecodeResult decoded))
            {
                droppedNonMultitouch++;
                continue;
            }

            framesParsed++;
            if (firstArrivalTicks < 0)
            {
                firstArrivalTicks = record.ArrivalQpcTicks;
            }

            long captureOffsetTicks = record.ArrivalQpcTicks - firstArrivalTicks;
            if (captureOffsetTicks < 0)
            {
                captureOffsetTicks = 0;
            }

            long offsetStopwatchTicks = (long)Math.Round(captureOffsetTicks * (double)Stopwatch.Frequency / reader.HeaderQpcFrequency);
            RawInputDeviceTag tag = new(record.DeviceIndex, record.DeviceHash);
            string replayDeviceName = $"replay://dev/{tag.Index}/{tag.Hash:X8}";
            RawInputDeviceSnapshot snapshot = new(replayDeviceName, info, tag);
            InputFrame frame = decoded.Frame;
            frames.Add(new ReplayVisualFrame(offsetStopwatchTicks, snapshot, frame));

            (int, uint) key = (tag.Index, tag.Hash);
            if (!devicesByTag.TryGetValue(key, out ReplayDeviceAccumulator? device))
            {
                string displayName = $"Replay Device {RawInputInterop.FormatTag(tag)}";
                device = new ReplayDeviceAccumulator(displayName, replayDeviceName, tag.Index, tag.Hash);
                devicesByTag[key] = device;
            }

            int contactCount = frame.GetClampedContactCount();
            for (int i = 0; i < contactCount; i++)
            {
                ContactFrame contact = frame.GetContact(i);
                if (!contact.TipSwitch)
                {
                    continue;
                }

                if (contact.X > device.MaxSeenX)
                {
                    device.MaxSeenX = contact.X;
                }

                if (contact.Y > device.MaxSeenY)
                {
                    device.MaxSeenY = contact.Y;
                }
            }
        }

        List<HidDeviceInfo> orderedDevices = new(devicesByTag.Count);
        foreach (ReplayDeviceAccumulator device in devicesByTag.Values)
        {
            ushort suggestedMaxX = device.MaxSeenX > 0
                ? (ushort)Math.Max(RuntimeConfigurationFactory.DefaultMaxX, device.MaxSeenX)
                : RuntimeConfigurationFactory.DefaultMaxX;
            ushort suggestedMaxY = device.MaxSeenY > 0
                ? (ushort)Math.Max(RuntimeConfigurationFactory.DefaultMaxY, device.MaxSeenY)
                : RuntimeConfigurationFactory.DefaultMaxY;
            orderedDevices.Add(new HidDeviceInfo(
                device.DisplayName,
                device.DevicePath,
                device.DeviceIndex,
                device.DeviceHash,
                suggestedMaxX,
                suggestedMaxY));
        }

        orderedDevices.Sort(static (a, b) => a.DeviceIndex.CompareTo(b.DeviceIndex));
        ReplayLoadStats stats = new(recordsRead, framesParsed, droppedInvalidSize, droppedNonMultitouch, droppedParseError);
        return new ReplayVisualData(fullPath, frames.ToArray(), orderedDevices.ToArray(), stats);
    }

    private sealed class ReplayDeviceAccumulator
    {
        public ReplayDeviceAccumulator(string displayName, string devicePath, int deviceIndex, uint deviceHash)
        {
            DisplayName = displayName;
            DevicePath = devicePath;
            DeviceIndex = deviceIndex;
            DeviceHash = deviceHash;
        }

        public string DisplayName { get; }
        public string DevicePath { get; }
        public int DeviceIndex { get; }
        public uint DeviceHash { get; }
        public ushort MaxSeenX { get; set; }
        public ushort MaxSeenY { get; set; }
    }
}
