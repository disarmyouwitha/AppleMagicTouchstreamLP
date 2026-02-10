using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace GlassToKey;

internal readonly record struct RawReportSignature(
    uint VendorId,
    uint ProductId,
    ushort UsagePage,
    ushort Usage,
    byte ReportId,
    int PayloadLength);

internal readonly record struct RawSignatureAnalysis(
    RawReportSignature Signature,
    long Frames,
    long DecodedFrames,
    long[] DecodeKindCounts,
    int MinContacts,
    double AvgContacts,
    int MaxContacts,
    int[] DecodeOffsets,
    int[] HotByteIndexes,
    string[] SamplesHex);

internal readonly record struct RawCaptureAnalysisResult(
    string CapturePath,
    int RecordsRead,
    int RecordsDecoded,
    RawSignatureAnalysis[] Signatures)
{
    public string ToSummary()
    {
        StringBuilder sb = new();
        sb.AppendLine($"Raw analysis: {CapturePath}");
        sb.AppendLine($"records={RecordsRead}, decoded={RecordsDecoded}, signatures={Signatures.Length}");
        for (int i = 0; i < Signatures.Length; i++)
        {
            RawSignatureAnalysis signature = Signatures[i];
            sb.AppendLine(
                $"{i + 1}. vid=0x{signature.Signature.VendorId:X4}, pid=0x{signature.Signature.ProductId:X4}, " +
                $"usage=0x{signature.Signature.UsagePage:X2}/0x{signature.Signature.Usage:X2}, " +
                $"reportId=0x{signature.Signature.ReportId:X2}, len={signature.Signature.PayloadLength}, frames={signature.Frames}");

            sb.AppendLine(
                $"   decoded={signature.DecodedFrames} " +
                $"[ptp={signature.DecodeKindCounts[(int)TrackpadReportKind.PtpNative]}, " +
                $"embedded={signature.DecodeKindCounts[(int)TrackpadReportKind.PtpEmbedded]}, " +
                $"apple9={signature.DecodeKindCounts[(int)TrackpadReportKind.AppleNineByte]}]");

            if (signature.DecodedFrames > 0)
            {
                sb.AppendLine(
                    $"   contacts[min/avg/max]={signature.MinContacts}/{signature.AvgContacts:F2}/{signature.MaxContacts}, " +
                    $"offsets=[{string.Join(",", signature.DecodeOffsets)}]");
            }

            if (signature.HotByteIndexes.Length > 0)
            {
                sb.AppendLine($"   hotBytes=[{string.Join(",", signature.HotByteIndexes)}]");
            }

            for (int sampleIndex = 0; sampleIndex < signature.SamplesHex.Length; sampleIndex++)
            {
                sb.AppendLine($"   sample{sampleIndex + 1}: {signature.SamplesHex[sampleIndex]}");
            }
        }

        return sb.ToString().TrimEnd();
    }

    public void WriteJson(string path)
    {
        string? dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(dir))
        {
            Directory.CreateDirectory(dir);
        }

        JsonSerializerOptions options = new() { WriteIndented = true };
        File.WriteAllText(path, JsonSerializer.Serialize(this, options));
    }
}

internal static class RawCaptureAnalyzer
{
    public static RawCaptureAnalysisResult Analyze(string capturePath)
    {
        string fullPath = Path.GetFullPath(capturePath);
        Dictionary<RawReportSignature, MutableSignatureStats> signatures = new();
        int recordsRead = 0;
        int recordsDecoded = 0;

        using InputCaptureReader reader = new(fullPath);
        while (reader.TryReadNext(out CaptureRecord record))
        {
            recordsRead++;
            ReadOnlySpan<byte> payload = record.Payload.Span;
            if (payload.Length == 0)
            {
                continue;
            }

            RawReportSignature signature = new(
                VendorId: record.VendorId,
                ProductId: record.ProductId,
                UsagePage: record.UsagePage,
                Usage: record.Usage,
                ReportId: payload[0],
                PayloadLength: payload.Length);

            if (!signatures.TryGetValue(signature, out MutableSignatureStats? stats))
            {
                stats = new MutableSignatureStats(signature);
                signatures[signature] = stats;
            }

            RawInputDeviceInfo info = new(record.VendorId, record.ProductId, record.UsagePage, record.Usage);
            bool decoded = TrackpadReportDecoder.TryDecode(payload, info, record.ArrivalQpcTicks, out TrackpadDecodeResult decodeResult);
            if (decoded)
            {
                recordsDecoded++;
            }

            stats.Add(payload, decoded, decodeResult);
        }

        RawSignatureAnalysis[] ordered = signatures.Values
            .OrderByDescending(static s => s.Frames)
            .ThenBy(static s => s.Signature.PayloadLength)
            .Select(static s => s.Build())
            .ToArray();

        return new RawCaptureAnalysisResult(fullPath, recordsRead, recordsDecoded, ordered);
    }

    private sealed class MutableSignatureStats
    {
        private const int MaxSamples = 3;
        private const int MaxSampleBytes = 96;
        private const int MaxHotBytes = 8;

        private readonly List<string> _samples = new(MaxSamples);
        private readonly long[] _decodeKindCounts = new long[Enum.GetValues<TrackpadReportKind>().Length];
        private readonly HashSet<int> _decodeOffsets = new();

        private byte[]? _firstPayload;
        private int[]? _changeCounts;

        private long _decodedFrames;
        private long _totalContacts;
        private int _minContacts = int.MaxValue;
        private int _maxContacts;

        public MutableSignatureStats(RawReportSignature signature)
        {
            Signature = signature;
        }

        public RawReportSignature Signature { get; }
        public long Frames { get; private set; }

        public void Add(ReadOnlySpan<byte> payload, bool decoded, in TrackpadDecodeResult decodeResult)
        {
            Frames++;

            if (_samples.Count < MaxSamples)
            {
                _samples.Add(ToHex(payload, MaxSampleBytes));
            }

            if (_firstPayload == null)
            {
                _firstPayload = payload.ToArray();
                _changeCounts = new int[payload.Length];
            }
            else if (_changeCounts != null)
            {
                for (int i = 0; i < payload.Length && i < _firstPayload.Length; i++)
                {
                    if (payload[i] != _firstPayload[i])
                    {
                        _changeCounts[i]++;
                    }
                }
            }

            if (!decoded)
            {
                return;
            }

            _decodedFrames++;
            _decodeKindCounts[(int)decodeResult.Kind]++;
            _decodeOffsets.Add(decodeResult.PayloadOffset);

            int contacts = decodeResult.Frame.GetClampedContactCount();
            _totalContacts += contacts;
            if (contacts < _minContacts)
            {
                _minContacts = contacts;
            }

            if (contacts > _maxContacts)
            {
                _maxContacts = contacts;
            }
        }

        public RawSignatureAnalysis Build()
        {
            int minContacts = _decodedFrames == 0 ? 0 : _minContacts;
            double avgContacts = _decodedFrames == 0 ? 0 : _totalContacts / (double)_decodedFrames;
            int[] decodeOffsets = _decodeOffsets.OrderBy(static value => value).ToArray();
            int[] hotBytes = (_changeCounts ?? Array.Empty<int>())
                .Select(static (count, index) => (count, index))
                .Where(static pair => pair.count > 0)
                .OrderByDescending(static pair => pair.count)
                .ThenBy(static pair => pair.index)
                .Take(MaxHotBytes)
                .Select(static pair => pair.index)
                .ToArray();

            return new RawSignatureAnalysis(
                Signature,
                Frames,
                _decodedFrames,
                (long[])_decodeKindCounts.Clone(),
                minContacts,
                avgContacts,
                _maxContacts,
                decodeOffsets,
                hotBytes,
                _samples.ToArray());
        }

        private static string ToHex(ReadOnlySpan<byte> payload, int maxBytes)
        {
            int length = Math.Min(payload.Length, maxBytes);
            string hex = Convert.ToHexString(payload.Slice(0, length));
            return payload.Length > length ? $"{hex}..." : hex;
        }
    }
}
