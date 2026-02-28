using System;
using System.Globalization;
using System.Text;

namespace GlassToKey;

internal static class TrackpadDecoderDebugFormatter
{
    public static string BuildContactIdSummary(
        ReadOnlySpan<byte> payload,
        in TrackpadDecodeResult decodeResult)
    {
        int decodedCount = decodeResult.Frame.GetClampedContactCount();
        if (decodedCount <= 0)
        {
            return "contacts=0";
        }

        bool hasRawReport = TryParseRawPtpForDecode(payload, decodeResult, out PtpReport rawReport);
        int rawCount = hasRawReport ? rawReport.GetClampedContactCount() : 0;

        StringBuilder sb = new();
        sb.Append("contacts=").Append(decodedCount).Append(" [");
        for (int i = 0; i < decodedCount; i++)
        {
            if (i > 0)
            {
                sb.Append(" | ");
            }

            ContactFrame decoded = decodeResult.Frame.GetContact(i);
            bool hasRawContact = hasRawReport && i < rawCount;
            PtpContact raw = hasRawContact ? rawReport.GetContact(i) : default;
            sb.Append('#').Append(i).Append(' ');
            if (hasRawContact)
            {
                sb.Append("raw=0x").Append(raw.ContactId.ToString("X8", CultureInfo.InvariantCulture));
            }
            else
            {
                sb.Append("raw=NA");
            }

            sb.Append(" -> id=0x").Append(decoded.Id.ToString("X8", CultureInfo.InvariantCulture));
            if (hasRawContact)
            {
                sb.Append(" flags 0x")
                  .Append(raw.Flags.ToString("X2", CultureInfo.InvariantCulture))
                  .Append("->0x")
                  .Append(decoded.Flags.ToString("X2", CultureInfo.InvariantCulture));
            }
        }

        sb.Append(']');
        return sb.ToString();
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
}
