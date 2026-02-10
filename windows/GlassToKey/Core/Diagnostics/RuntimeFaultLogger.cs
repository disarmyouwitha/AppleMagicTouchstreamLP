using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;

namespace GlassToKey;

internal static class RuntimeFaultLogger
{
    private static readonly object s_gate = new();

    public static string LogPath =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "GlassToKey",
            "runtime-errors.log");

    public static void LogException(string source, Exception exception, string? context = null)
    {
        try
        {
            lock (s_gate)
            {
                string path = LogPath;
                string? dir = Path.GetDirectoryName(path);
                if (!string.IsNullOrWhiteSpace(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                using StreamWriter writer = new(path, append: true, Encoding.UTF8);
                writer.WriteLine("============================================================");
                writer.WriteLine($"{DateTime.UtcNow:O} | {source}");
                writer.WriteLine($"uptime_ticks={Stopwatch.GetTimestamp()}");
                if (!string.IsNullOrWhiteSpace(context))
                {
                    writer.WriteLine(context);
                }
                writer.WriteLine(exception.ToString());
            }
        }
        catch
        {
            // Logging must never throw into the runtime path.
        }
    }

    public static string BuildRawInputContext(
        in RawInputDeviceSnapshot snapshot,
        in RawInputPacket packet,
        uint reportIndex,
        int reportSize,
        int offset,
        ReadOnlySpan<byte> payload)
    {
        StringBuilder sb = new();
        sb.Append("deviceName=").Append(snapshot.DeviceName);
        sb.Append(", tag=").Append(RawInputInterop.FormatTag(snapshot.Tag));
        sb.Append(", vid=0x").Append(((ushort)snapshot.Info.VendorId).ToString("X4", CultureInfo.InvariantCulture));
        sb.Append(", pid=0x").Append(((ushort)snapshot.Info.ProductId).ToString("X4", CultureInfo.InvariantCulture));
        sb.Append(", usage=0x").Append(snapshot.Info.UsagePage.ToString("X2", CultureInfo.InvariantCulture));
        sb.Append("/0x").Append(snapshot.Info.Usage.ToString("X2", CultureInfo.InvariantCulture));
        sb.Append(", packetReportSize=").Append(packet.ReportSize);
        sb.Append(", packetReportCount=").Append(packet.ReportCount);
        sb.Append(", packetValidLength=").Append(packet.ValidLength);
        sb.Append(", reportIndex=").Append(reportIndex);
        sb.Append(", reportSize=").Append(reportSize);
        sb.Append(", reportOffset=").Append(offset);
        if (payload.Length > 0)
        {
            sb.Append(", reportId=0x").Append(payload[0].ToString("X2", CultureInfo.InvariantCulture));
            sb.Append(", payloadHex=").Append(ToHex(payload, 96));
        }
        return sb.ToString();
    }

    private static string ToHex(ReadOnlySpan<byte> payload, int maxBytes)
    {
        int length = Math.Min(payload.Length, maxBytes);
        string hex = Convert.ToHexString(payload.Slice(0, length));
        return payload.Length > length ? $"{hex}..." : hex;
    }
}
