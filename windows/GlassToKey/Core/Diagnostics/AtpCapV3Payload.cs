using System;
using System.Buffers.Binary;
using System.Text.Json;

namespace GlassToKey;

internal readonly record struct AtpCapV3Meta(
    string Type,
    string Schema,
    string? CapturedAt,
    string? Platform,
    string? Source,
    long? FramesCaptured);

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
    double TimestampSeconds,
    ulong DeviceNumericId,
    ushort ContactCount,
    AtpCapV3Contact[] Contacts);

internal static class AtpCapV3Payload
{
    public const uint FrameMagic = 0x33564652; // RFV3
    public const byte FrameReportId = 0x52; // low byte of RFV3 marker
    public const int FrameHeaderSize = 32;
    public const int ContactSize = 40;

    public static bool TryParseMeta(ReadOnlySpan<byte> payload, out AtpCapV3Meta meta)
    {
        meta = default;
        try
        {
            using JsonDocument doc = JsonDocument.Parse(payload.ToArray());
            JsonElement root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            if (!root.TryGetProperty("type", out JsonElement typeElem) ||
                !string.Equals(typeElem.GetString(), "meta", StringComparison.Ordinal))
            {
                return false;
            }

            if (!root.TryGetProperty("schema", out JsonElement schemaElem) ||
                !string.Equals(schemaElem.GetString(), "g2k-replay-v1", StringComparison.Ordinal))
            {
                return false;
            }

            long? framesCaptured = null;
            if (root.TryGetProperty("framesCaptured", out JsonElement framesCapturedElem) &&
                framesCapturedElem.ValueKind == JsonValueKind.Number &&
                framesCapturedElem.TryGetInt64(out long parsedFramesCaptured))
            {
                framesCaptured = parsedFramesCaptured;
            }

            meta = new AtpCapV3Meta(
                Type: "meta",
                Schema: "g2k-replay-v1",
                CapturedAt: root.TryGetProperty("capturedAt", out JsonElement capturedAt) ? capturedAt.GetString() : null,
                Platform: root.TryGetProperty("platform", out JsonElement platform) ? platform.GetString() : null,
                Source: root.TryGetProperty("source", out JsonElement source) ? source.GetString() : null,
                FramesCaptured: framesCaptured);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    public static bool TryParseFrame(ReadOnlySpan<byte> payload, out AtpCapV3Frame frame)
    {
        frame = default;
        if (payload.Length < FrameHeaderSize)
        {
            return false;
        }

        if (BinaryPrimitives.ReadUInt32LittleEndian(payload.Slice(0, 4)) != FrameMagic)
        {
            return false;
        }

        ulong sequence = BinaryPrimitives.ReadUInt64LittleEndian(payload.Slice(4, 8));
        double timestampSeconds = BitConverter.Int64BitsToDouble(BinaryPrimitives.ReadInt64LittleEndian(payload.Slice(12, 8)));
        ulong deviceNumericId = BinaryPrimitives.ReadUInt64LittleEndian(payload.Slice(20, 8));
        ushort contactCount = BinaryPrimitives.ReadUInt16LittleEndian(payload.Slice(28, 2));

        int expectedLength = FrameHeaderSize + (contactCount * ContactSize);
        if (payload.Length != expectedLength)
        {
            return false;
        }

        AtpCapV3Contact[] contacts = new AtpCapV3Contact[contactCount];
        int offset = FrameHeaderSize;
        for (int i = 0; i < contactCount; i++)
        {
            int id = BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset, 4));
            float x = BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset + 4, 4)));
            float y = BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset + 8, 4)));
            float total = BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset + 12, 4)));
            float pressure = BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset + 16, 4)));
            float majorAxis = BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset + 20, 4)));
            float minorAxis = BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset + 24, 4)));
            float angle = BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset + 28, 4)));
            float density = BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(payload.Slice(offset + 32, 4)));
            byte state = payload[offset + 36];
            contacts[i] = new AtpCapV3Contact(id, x, y, total, pressure, majorAxis, minorAxis, angle, density, state);
            offset += ContactSize;
        }

        frame = new AtpCapV3Frame(
            Sequence: sequence,
            TimestampSeconds: timestampSeconds,
            DeviceNumericId: deviceNumericId,
            ContactCount: contactCount,
            Contacts: contacts);
        return true;
    }

    public static InputFrame ToInputFrame(in AtpCapV3Frame frame, long arrivalQpcTicks, ushort maxX, ushort maxY)
    {
        int available = frame.Contacts.Length;
        int count = Math.Min(InputFrame.MaxContacts, available);

        InputFrame result = new()
        {
            ArrivalQpcTicks = arrivalQpcTicks,
            ReportId = FrameReportId,
            ScanTime = (ushort)(frame.Sequence & 0xFFFF),
            ContactCount = (byte)count,
            IsButtonClicked = 0
        };

        for (int i = 0; i < count; i++)
        {
            AtpCapV3Contact source = frame.Contacts[i];
            uint id = source.Id >= 0 ? (uint)source.Id : 0;
            ushort x = ToAbsoluteCoordinate(source.X, maxX);
            ushort y = ToAbsoluteCoordinate(source.Y, maxY);
            byte flags = ToContactFlags(source.State);
            result.SetContact(i, new ContactFrame(id, x, y, flags, Pressure: 0, Phase: 0));
        }

        return result;
    }

    private static ushort ToAbsoluteCoordinate(float normalized, ushort maxCoordinate)
    {
        if (!float.IsFinite(normalized))
        {
            return 0;
        }

        double clamped = Math.Clamp((double)normalized, 0.0, 1.0);
        int scaled = (int)Math.Round(clamped * maxCoordinate);
        return (ushort)Math.Clamp(scaled, 0, maxCoordinate);
    }

    private static byte ToContactFlags(byte state)
    {
        return state switch
        {
            2 or 6 or 7 => 0x01, // confidence only
            1 or 3 or 4 or 5 => 0x03, // confidence + tip
            _ => 0x00
        };
    }
}
