using System;
using System.Collections.Generic;
using System.Globalization;
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
    public static RawCaptureAnalysisResult Analyze(string capturePath, string? contactsCsvPath = null)
    {
        string fullPath = Path.GetFullPath(capturePath);
        Dictionary<RawReportSignature, MutableSignatureStats> signatures = new();
        int recordsRead = 0;
        int recordsDecoded = 0;
        int frameIndex = 0;

        StreamWriter? contactsWriter = null;
        if (!string.IsNullOrWhiteSpace(contactsCsvPath))
        {
            string fullContactsCsvPath = Path.GetFullPath(contactsCsvPath);
            string? csvDir = Path.GetDirectoryName(fullContactsCsvPath);
            if (!string.IsNullOrWhiteSpace(csvDir))
            {
                Directory.CreateDirectory(csvDir);
            }

            contactsWriter = new StreamWriter(fullContactsCsvPath, append: false, Encoding.UTF8);
            WriteContactTraceHeader(contactsWriter);
        }

        try
        {
            using InputCaptureReader reader = new(fullPath);
            while (reader.TryReadNext(out CaptureRecord record))
            {
                recordsRead++;
                ReadOnlySpan<byte> payload = record.Payload.Span;
                if (payload.Length == 0)
                {
                    frameIndex++;
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
                TrackpadDecoderProfile preferredProfile = record.DecoderProfile == TrackpadDecoderProfile.Legacy
                    ? TrackpadDecoderProfile.Legacy
                    : TrackpadDecoderProfile.Official;
                bool decoded = TrackpadReportDecoder.TryDecode(payload, info, record.ArrivalQpcTicks, preferredProfile, out TrackpadDecodeResult decodeResult);
                if (decoded)
                {
                    recordsDecoded++;
                }

                stats.Add(payload, decoded, decodeResult);
                if (contactsWriter != null && decoded)
                {
                    WriteContactTraceRows(contactsWriter, frameIndex, record, payload, decodeResult);
                }

                frameIndex++;
            }
        }
        finally
        {
            contactsWriter?.Dispose();
        }

        RawSignatureAnalysis[] ordered = signatures.Values
            .OrderByDescending(static s => s.Frames)
            .ThenBy(static s => s.Signature.PayloadLength)
            .Select(static s => s.Build())
            .ToArray();

        return new RawCaptureAnalysisResult(fullPath, recordsRead, recordsDecoded, ordered);
    }

    private static void WriteContactTraceHeader(TextWriter writer)
    {
        writer.WriteLine(
            "frame_index,decode_kind,profile,payload_offset,vendor_id,product_id,usage_page,usage,source_report_id,payload_length,contact_index,raw_contact_id,assigned_contact_id,raw_flags,assigned_flags,raw_x,raw_y,decoded_x,decoded_y,slot_offset,slot_hex");
    }

    private static void WriteContactTraceRows(
        TextWriter writer,
        int frameIndex,
        in CaptureRecord record,
        ReadOnlySpan<byte> payload,
        in TrackpadDecodeResult decodeResult)
    {
        int decodedCount = decodeResult.Frame.GetClampedContactCount();
        if (decodedCount <= 0)
        {
            return;
        }

        bool hasRawReport = TryParseRawPtpForDecode(payload, decodeResult, out PtpReport rawReport);
        int rawCount = hasRawReport ? rawReport.GetClampedContactCount() : 0;
        for (int i = 0; i < decodedCount; i++)
        {
            ContactFrame decodedContact = decodeResult.Frame.GetContact(i);
            bool hasRawContact = hasRawReport && i < rawCount;
            PtpContact rawContact = hasRawContact ? rawReport.GetContact(i) : default;

            int slotOffset = decodeResult.PayloadOffset + 1 + (i * 9);
            bool hasSlotBytes = slotOffset >= 0 && slotOffset + 8 < payload.Length;
            string slotHex = hasSlotBytes
                ? Convert.ToHexString(payload.Slice(slotOffset, 9))
                : string.Empty;

            writer.Write(frameIndex.ToString(CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write(decodeResult.Kind.ToString());
            writer.Write(',');
            writer.Write(decodeResult.Profile.ToString());
            writer.Write(',');
            writer.Write(decodeResult.PayloadOffset.ToString(CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write("0x");
            writer.Write(((ushort)record.VendorId).ToString("X4", CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write("0x");
            writer.Write(((ushort)record.ProductId).ToString("X4", CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write("0x");
            writer.Write(record.UsagePage.ToString("X2", CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write("0x");
            writer.Write(record.Usage.ToString("X2", CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write("0x");
            writer.Write(decodeResult.SourceReportId.ToString("X2", CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write(payload.Length.ToString(CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write(i.ToString(CultureInfo.InvariantCulture));
            writer.Write(',');
            if (hasRawContact)
            {
                writer.Write("0x");
                writer.Write(rawContact.ContactId.ToString("X8", CultureInfo.InvariantCulture));
            }
            writer.Write(',');
            writer.Write("0x");
            writer.Write(decodedContact.Id.ToString("X8", CultureInfo.InvariantCulture));
            writer.Write(',');
            if (hasRawContact)
            {
                writer.Write("0x");
                writer.Write(rawContact.Flags.ToString("X2", CultureInfo.InvariantCulture));
            }
            writer.Write(',');
            writer.Write("0x");
            writer.Write(decodedContact.Flags.ToString("X2", CultureInfo.InvariantCulture));
            writer.Write(',');
            if (hasRawContact)
            {
                writer.Write(rawContact.X.ToString(CultureInfo.InvariantCulture));
            }
            writer.Write(',');
            if (hasRawContact)
            {
                writer.Write(rawContact.Y.ToString(CultureInfo.InvariantCulture));
            }
            writer.Write(',');
            writer.Write(decodedContact.X.ToString(CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write(decodedContact.Y.ToString(CultureInfo.InvariantCulture));
            writer.Write(',');
            writer.Write(hasSlotBytes ? slotOffset.ToString(CultureInfo.InvariantCulture) : string.Empty);
            writer.Write(',');
            writer.Write(slotHex);
            writer.WriteLine();
        }
    }

    private static bool TryParseRawPtpForDecode(
        ReadOnlySpan<byte> payload,
        in TrackpadDecodeResult decodeResult,
        out PtpReport report)
    {
        report = default;
        if (decodeResult.Kind is not TrackpadReportKind.PtpNative and not TrackpadReportKind.PtpEmbedded)
        {
            return false;
        }

        if (decodeResult.PayloadOffset < 0 || decodeResult.PayloadOffset > payload.Length - PtpReport.ExpectedSize)
        {
            return false;
        }

        return PtpReport.TryParse(payload.Slice(decodeResult.PayloadOffset), out report);
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
