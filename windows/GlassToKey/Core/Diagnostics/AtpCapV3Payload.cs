using System;
using System.Buffers.Binary;
using System.Diagnostics;
using System.Text.Json;

namespace GlassToKey;

internal readonly record struct AtpCapV3Meta(
    string Type,
    string Schema,
    string CapturedAt,
    string Platform,
    string Source,
    int FramesCaptured);

internal readonly record struct AtpCapV3Contact(
    int Id,
    float X,
    float Y,
    float Total,
    float Pressure,
    float MajorAxis,
    float MinorAxis,
    float Angle,
    float Density,
    byte State);

internal readonly record struct AtpCapV3Frame(
    ulong Sequence,
    double TimestampSec,
    ulong DeviceNumericId,
    AtpCapV3Contact[] Contacts);

internal static class AtpCapV3Payload
{
    public const string Schema = "g2k-replay-v1";
    public const int MetaDeviceIndex = -1;
    public const uint FrameMagic = 0x33564652; // "RFV3" little-endian
    public const byte ReportIdMarker = 0x52;
    public const int FrameHeaderBytes = 32;
    public const int FrameContactBytes = 40;
    private const bool CanonicalYAxisBottomOrigin = true;

    public static byte[] CreateMetaPayload(string platform, string source, int framesCaptured)
    {
        MetaPayload payload = new()
        {
            type = "meta",
            schema = Schema,
            capturedAt = DateTime.UtcNow.ToString("O"),
            platform = platform,
            source = source,
            framesCaptured = Math.Max(0, framesCaptured)
        };
        return JsonSerializer.SerializeToUtf8Bytes(payload);
    }

    public static bool TryParseMeta(ReadOnlySpan<byte> payload, out AtpCapV3Meta meta)
    {
        meta = default;
        MetaPayload? parsed;
        try
        {
            parsed = JsonSerializer.Deserialize<MetaPayload>(payload);
        }
        catch
        {
            return false;
        }

        if (parsed == null ||
            !string.Equals(parsed.type, "meta", StringComparison.Ordinal) ||
            !string.Equals(parsed.schema, Schema, StringComparison.Ordinal))
        {
            return false;
        }

        meta = new AtpCapV3Meta(
            parsed.type ?? "meta",
            parsed.schema ?? Schema,
            parsed.capturedAt ?? string.Empty,
            parsed.platform ?? string.Empty,
            parsed.source ?? string.Empty,
            parsed.framesCaptured);
        return true;
    }

    public static bool TryParseFrame(ReadOnlySpan<byte> payload, out AtpCapV3Frame frame)
    {
        frame = default;
        if (payload.Length < FrameHeaderBytes)
        {
            return false;
        }

        uint frameMagic = BinaryPrimitives.ReadUInt32LittleEndian(payload.Slice(0, 4));
        if (frameMagic != FrameMagic)
        {
            return false;
        }

        ulong sequence = BinaryPrimitives.ReadUInt64LittleEndian(payload.Slice(4, 8));
        double timestampSec = ReadDoubleLE(payload.Slice(12, 8));
        ulong deviceNumericId = BinaryPrimitives.ReadUInt64LittleEndian(payload.Slice(20, 8));
        int contactCount = BinaryPrimitives.ReadUInt16LittleEndian(payload.Slice(28, 2));
        int expectedLength = FrameHeaderBytes + (contactCount * FrameContactBytes);
        if (payload.Length != expectedLength)
        {
            return false;
        }

        AtpCapV3Contact[] contacts = new AtpCapV3Contact[contactCount];
        int offset = FrameHeaderBytes;
        for (int i = 0; i < contactCount; i++)
        {
            int id = BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset, 4));
            float x = ReadFloatLE(payload.Slice(offset + 4, 4));
            float y = ReadFloatLE(payload.Slice(offset + 8, 4));
            float total = ReadFloatLE(payload.Slice(offset + 12, 4));
            float pressure = ReadFloatLE(payload.Slice(offset + 16, 4));
            float majorAxis = ReadFloatLE(payload.Slice(offset + 20, 4));
            float minorAxis = ReadFloatLE(payload.Slice(offset + 24, 4));
            float angle = ReadFloatLE(payload.Slice(offset + 28, 4));
            float density = ReadFloatLE(payload.Slice(offset + 32, 4));
            byte state = payload[offset + 36];
            if (state > 7)
            {
                return false;
            }

            contacts[i] = new AtpCapV3Contact(
                id,
                x,
                y,
                total,
                pressure,
                majorAxis,
                minorAxis,
                angle,
                density,
                state);
            offset += FrameContactBytes;
        }

        frame = new AtpCapV3Frame(sequence, timestampSec, deviceNumericId, contacts);
        return true;
    }

    public static byte[] EncodeFramePayload(
        in InputFrame frame,
        ulong sequence,
        ulong deviceNumericId,
        ushort maxX,
        ushort maxY)
    {
        int contactCount = frame.GetClampedContactCount();
        byte[] payload = new byte[FrameHeaderBytes + (contactCount * FrameContactBytes)];
        Span<byte> span = payload;
        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(0, 4), FrameMagic);
        BinaryPrimitives.WriteUInt64LittleEndian(span.Slice(4, 8), sequence);
        WriteDoubleLE(span.Slice(12, 8), frame.ArrivalQpcTicks / (double)Stopwatch.Frequency);
        BinaryPrimitives.WriteUInt64LittleEndian(span.Slice(20, 8), deviceNumericId);
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(28, 2), (ushort)contactCount);
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(30, 2), 0);

        int offset = FrameHeaderBytes;
        for (int i = 0; i < contactCount; i++)
        {
            ContactFrame contact = frame.GetContact(i);
            BinaryPrimitives.WriteInt32LittleEndian(span.Slice(offset, 4), unchecked((int)contact.Id));
            WriteFloatLE(span.Slice(offset + 4, 4), NormalizeCoordinate(contact.X, maxX));
            WriteFloatLE(span.Slice(offset + 8, 4), NormalizeCoordinate(contact.Y, maxY, flipAxis: CanonicalYAxisBottomOrigin));
            WriteFloatLE(span.Slice(offset + 12, 4), 0);
            WriteFloatLE(span.Slice(offset + 16, 4), 0);
            WriteFloatLE(span.Slice(offset + 20, 4), 0);
            WriteFloatLE(span.Slice(offset + 24, 4), 0);
            WriteFloatLE(span.Slice(offset + 28, 4), 0);
            WriteFloatLE(span.Slice(offset + 32, 4), 0);
            span[offset + 36] = CanonicalStateFromFlags(contact.Flags);
            offset += FrameContactBytes;
        }

        return payload;
    }

    public static InputFrame ToInputFrame(in AtpCapV3Frame frame, long arrivalQpcTicks, ushort maxX, ushort maxY)
    {
        InputFrame converted = new()
        {
            ArrivalQpcTicks = arrivalQpcTicks,
            ReportId = ReportIdMarker,
            ScanTime = (ushort)(frame.Sequence & 0xFFFF),
            ContactCount = (byte)Math.Min(frame.Contacts.Length, byte.MaxValue),
            IsButtonClicked = 0
        };

        int count = Math.Min(InputFrame.MaxContacts, frame.Contacts.Length);
        for (int i = 0; i < count; i++)
        {
            AtpCapV3Contact contact = frame.Contacts[i];
            converted.SetContact(i, new ContactFrame(
                unchecked((uint)contact.Id),
                ScaleCoordinate(contact.X, maxX),
                ScaleCoordinate(contact.Y, maxY, flipAxis: CanonicalYAxisBottomOrigin),
                FlagsFromCanonicalState(contact.State),
                Pressure: 0,
                Phase: 0));
        }

        return converted;
    }

    private static byte CanonicalStateFromFlags(byte flags)
    {
        if ((flags & 0x02) != 0)
        {
            return 4;
        }

        if ((flags & 0x01) != 0)
        {
            return 2;
        }

        return 0;
    }

    private static byte FlagsFromCanonicalState(byte state)
    {
        return state switch
        {
            0 => 0x00,
            2 => 0x01,
            6 => 0x01,
            7 => 0x01,
            1 => 0x03,
            3 => 0x03,
            4 => 0x03,
            5 => 0x03,
            _ => 0x00
        };
    }

    private static float NormalizeCoordinate(ushort coordinate, ushort maxValue, bool flipAxis = false)
    {
        if (maxValue == 0)
        {
            return 0;
        }

        float normalized = coordinate / (float)maxValue;
        if (flipAxis)
        {
            normalized = 1f - normalized;
        }

        return Math.Clamp(normalized, 0f, 1f);
    }

    private static ushort ScaleCoordinate(float normalized, ushort maxValue, bool flipAxis = false)
    {
        if (maxValue == 0 || !float.IsFinite(normalized))
        {
            return 0;
        }

        double clamped = Math.Clamp((double)normalized, 0, 1);
        if (flipAxis)
        {
            clamped = 1.0 - clamped;
        }

        double scaled = Math.Round(clamped * maxValue, MidpointRounding.AwayFromZero);
        return (ushort)Math.Clamp((int)scaled, 0, maxValue);
    }

    private static float ReadFloatLE(ReadOnlySpan<byte> source)
    {
        return BitConverter.UInt32BitsToSingle(BinaryPrimitives.ReadUInt32LittleEndian(source));
    }

    private static double ReadDoubleLE(ReadOnlySpan<byte> source)
    {
        return BitConverter.UInt64BitsToDouble(BinaryPrimitives.ReadUInt64LittleEndian(source));
    }

    private static void WriteFloatLE(Span<byte> destination, float value)
    {
        BinaryPrimitives.WriteUInt32LittleEndian(destination, BitConverter.SingleToUInt32Bits(value));
    }

    private static void WriteDoubleLE(Span<byte> destination, double value)
    {
        BinaryPrimitives.WriteUInt64LittleEndian(destination, BitConverter.DoubleToUInt64Bits(value));
    }

    private sealed class MetaPayload
    {
        public string? type { get; set; }
        public string? schema { get; set; }
        public string? capturedAt { get; set; }
        public string? platform { get; set; }
        public string? source { get; set; }
        public int framesCaptured { get; set; }
    }
}
