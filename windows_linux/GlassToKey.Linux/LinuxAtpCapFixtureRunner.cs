using System.Text.Json;
using System.Text.Json.Serialization;
using GlassToKey.Linux.Runtime;

namespace GlassToKey.Linux;

internal readonly record struct LinuxAtpCapFixtureWriteResult(
    bool Success,
    string Summary);

internal readonly record struct LinuxAtpCapFixtureCheckResult(
    bool Success,
    string Summary);

internal static class LinuxAtpCapFixtureRunner
{
    public static LinuxAtpCapFixtureWriteResult WriteFixture(
        string capturePath,
        string fixturePath,
        LinuxRuntimeConfiguration configuration)
    {
        string fullCapturePath = Path.GetFullPath(capturePath);
        string fullFixturePath = Path.GetFullPath(fixturePath);
        LinuxAtpCapReplayResult replay = LinuxAtpCapReplayRunner.Replay(fullCapturePath, configuration, traceOutputPath: null);
        if (!replay.Success)
        {
            return new LinuxAtpCapFixtureWriteResult(false, replay.Summary);
        }

        string fixtureDirectory = Path.GetDirectoryName(fullFixturePath) ?? Directory.GetCurrentDirectory();
        Directory.CreateDirectory(fixtureDirectory);

        LinuxReplayFixtureDocument document = new()
        {
            CapturePath = Path.GetRelativePath(fixtureDirectory, fullCapturePath),
            Expected = new LinuxReplayFixtureExpected
            {
                CaptureFingerprint = $"0x{replay.CaptureFingerprint:X16}",
                DispatchFingerprint = $"0x{replay.DispatchFingerprint:X16}",
                DispatchEvents = replay.DispatchEventCount,
                IntentTransitions = replay.IntentTransitionCount,
                FramesSeen = replay.Metrics.FramesSeen,
                FramesParsed = replay.Metrics.FramesParsed,
                FramesDispatched = replay.Metrics.FramesDispatched,
                FramesDropped = replay.Metrics.FramesDropped
            }
        };

        JsonSerializerOptions options = new()
        {
            WriteIndented = true
        };
        File.WriteAllText(fullFixturePath, JsonSerializer.Serialize(document, options));
        return new LinuxAtpCapFixtureWriteResult(true, $"Fixture written: {fullFixturePath}");
    }

    public static LinuxAtpCapFixtureCheckResult CheckFixture(
        string capturePath,
        string fixturePath,
        LinuxRuntimeConfiguration configuration,
        string? traceOutputPath)
    {
        string fullFixturePath = Path.GetFullPath(fixturePath);
        LinuxReplayFixture fixture = LoadFixture(fullFixturePath, capturePath);
        LinuxAtpCapReplayResult replay = LinuxAtpCapReplayRunner.Replay(fixture.CapturePath, configuration, traceOutputPath);
        if (!replay.Success)
        {
            return new LinuxAtpCapFixtureCheckResult(false, replay.Summary);
        }

        List<string> mismatches = [];
        LinuxReplayFixtureExpected expected = fixture.Expected;
        CompareHex("captureFingerprint", expected.CaptureFingerprint, replay.CaptureFingerprint, mismatches);
        CompareHex("dispatchFingerprint", expected.DispatchFingerprint, replay.DispatchFingerprint, mismatches);
        CompareInt("dispatchEvents", expected.DispatchEvents, replay.DispatchEventCount, mismatches);
        CompareInt("intentTransitions", expected.IntentTransitions, replay.IntentTransitionCount, mismatches);
        CompareLong("framesSeen", expected.FramesSeen, replay.Metrics.FramesSeen, mismatches);
        CompareLong("framesParsed", expected.FramesParsed, replay.Metrics.FramesParsed, mismatches);
        CompareLong("framesDispatched", expected.FramesDispatched, replay.Metrics.FramesDispatched, mismatches);
        CompareLong("framesDropped", expected.FramesDropped, replay.Metrics.FramesDropped, mismatches);

        if (mismatches.Count != 0)
        {
            return new LinuxAtpCapFixtureCheckResult(
                false,
                $"Fixture '{fullFixturePath}' did not match '{fixture.CapturePath}': {string.Join("; ", mismatches)}");
        }

        return new LinuxAtpCapFixtureCheckResult(
            true,
            $"Fixture '{fullFixturePath}' matched '{fixture.CapturePath}': captureTrace=0x{replay.CaptureFingerprint:X16}, dispatchTrace=0x{replay.DispatchFingerprint:X16}, dispatchEvents={replay.DispatchEventCount}, intentTransitions={replay.IntentTransitionCount}");
    }

    private static LinuxReplayFixture LoadFixture(string fixturePath, string fallbackCapturePath)
    {
        string text = File.ReadAllText(fixturePath);
        LinuxReplayFixtureDocument? document = JsonSerializer.Deserialize<LinuxReplayFixtureDocument>(text);
        if (document?.Expected == null)
        {
            throw new InvalidDataException($"Fixture '{fixturePath}' is invalid.");
        }

        string capturePath = document.CapturePath;
        if (string.IsNullOrWhiteSpace(capturePath))
        {
            capturePath = fallbackCapturePath;
        }
        else if (!Path.IsPathFullyQualified(capturePath))
        {
            string fixtureDirectory = Path.GetDirectoryName(fixturePath) ?? Directory.GetCurrentDirectory();
            capturePath = Path.GetFullPath(Path.Combine(fixtureDirectory, capturePath));
        }

        return new LinuxReplayFixture(capturePath, document.Expected);
    }

    private static void CompareHex(string label, string? expected, ulong actual, List<string> mismatches)
    {
        if (string.IsNullOrWhiteSpace(expected))
        {
            return;
        }

        string actualText = $"0x{actual:X16}";
        if (!string.Equals(expected, actualText, StringComparison.OrdinalIgnoreCase))
        {
            mismatches.Add($"{label} expected={expected} actual={actualText}");
        }
    }

    private static void CompareInt(string label, int? expected, int actual, List<string> mismatches)
    {
        if (expected.HasValue && expected.Value != actual)
        {
            mismatches.Add($"{label} expected={expected.Value} actual={actual}");
        }
    }

    private static void CompareLong(string label, long? expected, long actual, List<string> mismatches)
    {
        if (expected.HasValue && expected.Value != actual)
        {
            mismatches.Add($"{label} expected={expected.Value} actual={actual}");
        }
    }

    private readonly record struct LinuxReplayFixture(string CapturePath, LinuxReplayFixtureExpected Expected);

    private sealed class LinuxReplayFixtureDocument
    {
        [JsonPropertyName("capturePath")]
        public string CapturePath { get; set; } = string.Empty;

        [JsonPropertyName("expected")]
        public LinuxReplayFixtureExpected? Expected { get; set; }
    }

    private sealed class LinuxReplayFixtureExpected
    {
        [JsonPropertyName("captureFingerprint")]
        public string? CaptureFingerprint { get; set; }

        [JsonPropertyName("dispatchFingerprint")]
        public string? DispatchFingerprint { get; set; }

        [JsonPropertyName("dispatchEvents")]
        public int? DispatchEvents { get; set; }

        [JsonPropertyName("intentTransitions")]
        public int? IntentTransitions { get; set; }

        [JsonPropertyName("framesSeen")]
        public long? FramesSeen { get; set; }

        [JsonPropertyName("framesParsed")]
        public long? FramesParsed { get; set; }

        [JsonPropertyName("framesDispatched")]
        public long? FramesDispatched { get; set; }

        [JsonPropertyName("framesDropped")]
        public long? FramesDropped { get; set; }
    }
}
