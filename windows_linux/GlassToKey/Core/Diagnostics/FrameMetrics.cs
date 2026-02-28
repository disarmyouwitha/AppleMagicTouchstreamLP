using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text.Json;

namespace GlassToKey;

internal enum FrameDropReason
{
    NonMultitouchReport = 0,
    ParseFailed = 1,
    RoutedToNoSession = 2,
    PacketTruncated = 3,
    InvalidReportSize = 4,
    EngineQueueFull = 5
}

internal sealed class FrameMetrics
{
    private static readonly int[] s_latencyBucketsUs = { 250, 500, 1000, 2000, 4000, 8000, 16000 };

    private readonly string _name;
    private readonly long[] _dropCounts = new long[Enum.GetValues<FrameDropReason>().Length];
    private readonly long[] _latencyCounts = new long[s_latencyBucketsUs.Length + 1];
    private readonly long _allocationBaseline;
    private readonly long _timestampStarted;

    private long _framesSeen;
    private long _framesParsed;
    private long _framesDispatched;
    private long _framesDropped;
    private long _latencyMinTicks = long.MaxValue;
    private long _latencyMaxTicks;
    private long _latencyTotalTicks;
    private long _allocationSampleCount;
    private long _allocationMaxSampleDelta;

    public FrameMetrics(string name)
    {
        _name = name;
        _timestampStarted = Stopwatch.GetTimestamp();
        _allocationBaseline = GC.GetAllocatedBytesForCurrentThread();
    }

    public void RecordSeen()
    {
        _framesSeen++;
    }

    public void RecordParsed()
    {
        _framesParsed++;
    }

    public void RecordDropped(FrameDropReason reason)
    {
        _framesDropped++;
        _dropCounts[(int)reason]++;
    }

    public void RecordDispatched(long startedTimestamp)
    {
        _framesDispatched++;
        long elapsedTicks = Stopwatch.GetTimestamp() - startedTimestamp;
        _latencyTotalTicks += elapsedTicks;
        if (elapsedTicks < _latencyMinTicks)
        {
            _latencyMinTicks = elapsedTicks;
        }

        if (elapsedTicks > _latencyMaxTicks)
        {
            _latencyMaxTicks = elapsedTicks;
        }

        int bucketIndex = ResolveLatencyBucket(elapsedTicks);
        _latencyCounts[bucketIndex]++;

        if ((_framesDispatched & 63) == 0)
        {
            long allocated = GC.GetAllocatedBytesForCurrentThread() - _allocationBaseline;
            _allocationSampleCount++;
            if (allocated > _allocationMaxSampleDelta)
            {
                _allocationMaxSampleDelta = allocated;
            }
        }
    }

    public FrameMetricsSnapshot CreateSnapshot()
    {
        long runTicks = Stopwatch.GetTimestamp() - _timestampStarted;
        return new FrameMetricsSnapshot(
            _name,
            _framesSeen,
            _framesParsed,
            _framesDispatched,
            _framesDropped,
            _dropCounts,
            _latencyCounts,
            s_latencyBucketsUs,
            _latencyMinTicks == long.MaxValue ? 0 : _latencyMinTicks,
            _latencyMaxTicks,
            _latencyTotalTicks,
            runTicks,
            Stopwatch.Frequency,
            GC.GetAllocatedBytesForCurrentThread() - _allocationBaseline,
            _allocationMaxSampleDelta,
            _allocationSampleCount);
    }

    public void WriteSnapshotJson(string path)
    {
        FrameMetricsSnapshot snapshot = CreateSnapshot();
        snapshot.WriteSnapshotJson(path);
    }

    private static int ResolveLatencyBucket(long elapsedTicks)
    {
        double elapsedUs = elapsedTicks * 1_000_000.0 / Stopwatch.Frequency;
        for (int i = 0; i < s_latencyBucketsUs.Length; i++)
        {
            if (elapsedUs <= s_latencyBucketsUs[i])
            {
                return i;
            }
        }

        return s_latencyBucketsUs.Length;
    }
}

internal readonly record struct FrameMetricsSnapshot(
    string Name,
    long FramesSeen,
    long FramesParsed,
    long FramesDispatched,
    long FramesDropped,
    long[] DropCounts,
    long[] LatencyBucketCounts,
    int[] LatencyBucketEdgesUs,
    long LatencyMinTicks,
    long LatencyMaxTicks,
    long LatencyTotalTicks,
    long RunTicks,
    long StopwatchFrequency,
    long AllocationDeltaBytes,
    long AllocationMaxSampleBytes,
    long AllocationSampleCount)
{
    public string ToSummary()
    {
        double runSeconds = RunTicks / (double)StopwatchFrequency;
        double avgLatencyUs = FramesDispatched == 0 ? 0 : (LatencyTotalTicks * 1_000_000.0 / StopwatchFrequency) / FramesDispatched;
        double minLatencyUs = LatencyMinTicks * 1_000_000.0 / StopwatchFrequency;
        double maxLatencyUs = LatencyMaxTicks * 1_000_000.0 / StopwatchFrequency;
        return string.Create(CultureInfo.InvariantCulture, $"{Name}: seen={FramesSeen}, parsed={FramesParsed}, dispatched={FramesDispatched}, dropped={FramesDropped}, run_s={runSeconds:F3}, latency_us[min/avg/max]={minLatencyUs:F2}/{avgLatencyUs:F2}/{maxLatencyUs:F2}, alloc_delta_b={AllocationDeltaBytes}");
    }

    public object ToModel()
    {
        return new
        {
            name = Name,
            framesSeen = FramesSeen,
            framesParsed = FramesParsed,
            framesDispatched = FramesDispatched,
            framesDropped = FramesDropped,
            dropReasons = new
            {
                nonMultitouchReport = DropCounts[(int)FrameDropReason.NonMultitouchReport],
                parseFailed = DropCounts[(int)FrameDropReason.ParseFailed],
                routedToNoSession = DropCounts[(int)FrameDropReason.RoutedToNoSession],
                packetTruncated = DropCounts[(int)FrameDropReason.PacketTruncated],
                invalidReportSize = DropCounts[(int)FrameDropReason.InvalidReportSize],
                engineQueueFull = DropCounts[(int)FrameDropReason.EngineQueueFull]
            },
            latency = new
            {
                bucketEdgesUs = LatencyBucketEdgesUs,
                buckets = LatencyBucketCounts,
                minUs = LatencyMinTicks * 1_000_000.0 / StopwatchFrequency,
                avgUs = FramesDispatched == 0 ? 0 : (LatencyTotalTicks * 1_000_000.0 / StopwatchFrequency) / FramesDispatched,
                maxUs = LatencyMaxTicks * 1_000_000.0 / StopwatchFrequency
            },
            allocations = new
            {
                deltaBytes = AllocationDeltaBytes,
                maxSampleBytes = AllocationMaxSampleBytes,
                sampleCount = AllocationSampleCount
            },
            runtimeSeconds = RunTicks / (double)StopwatchFrequency
        };
    }

    public void WriteSnapshotJson(string path)
    {
        string? directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        JsonSerializerOptions options = new() { WriteIndented = true };
        File.WriteAllText(path, JsonSerializer.Serialize(ToModel(), options));
    }
}
