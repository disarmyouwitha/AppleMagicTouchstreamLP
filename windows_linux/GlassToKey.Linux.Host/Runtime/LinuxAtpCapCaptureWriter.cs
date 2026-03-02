using System.Buffers.Binary;
using System.Text;
using System.Text.Json;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Runtime;

internal sealed class LinuxAtpCapCaptureWriter : IDisposable
{
    private const ushort UsagePageDigitizer = 0x0D;
    private const ushort UsageTouchpad = 0x05;

    private readonly FileStream _stream;
    private readonly Dictionary<string, DeviceCaptureIdentity> _devicesByStableId = new(StringComparer.OrdinalIgnoreCase);
    private readonly long _baseTimestampTicks;
    private bool _disposed;

    public LinuxAtpCapCaptureWriter(string path)
    {
        Path = System.IO.Path.GetFullPath(path);
        string? directory = System.IO.Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        _stream = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read, 64 * 1024, FileOptions.SequentialScan);
        InputCaptureFile.WriteHeader(_stream, InputCaptureFile.Version3, System.Diagnostics.Stopwatch.Frequency);
        _baseTimestampTicks = System.Diagnostics.Stopwatch.GetTimestamp();
        WriteMetaRecord();
    }

    public string Path { get; }

    public void WriteFrame(in LinuxRuntimeFrame frame)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        DeviceCaptureIdentity identity = ResolveIdentity(frame.Binding.Device);
        byte[] payload = BuildFramePayload(identity.NumericId, frame.Snapshot);
        WriteRecord(
            deviceIndex: identity.Index,
            deviceHash: identity.Hash32,
            vendorId: frame.Binding.Device.VendorId,
            productId: frame.Binding.Device.ProductId,
            usagePage: UsagePageDigitizer,
            usage: UsageTouchpad,
            sideHint: ToSideHint(frame.Binding.Side),
            decoderProfile: TrackpadDecoderProfile.Official,
            arrivalQpcTicks: frame.Snapshot.Frame.ArrivalQpcTicks,
            payload: payload);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _stream.Dispose();
    }

    private void WriteMetaRecord()
    {
        byte[] payload = JsonSerializer.SerializeToUtf8Bytes(new
        {
            type = "meta",
            schema = "g2k-replay-v1",
            capturedAt = DateTimeOffset.UtcNow.ToString("O"),
            platform = "linux",
            source = "glasstokey-linux-tray-runtime"
        });

        WriteRecord(
            deviceIndex: -1,
            deviceHash: 0,
            vendorId: 0,
            productId: 0,
            usagePage: 0,
            usage: 0,
            sideHint: CaptureSideHint.Unknown,
            decoderProfile: TrackpadDecoderProfile.Official,
            arrivalQpcTicks: _baseTimestampTicks,
            payload: payload);
    }

    private DeviceCaptureIdentity ResolveIdentity(LinuxInputDeviceDescriptor device)
    {
        if (_devicesByStableId.TryGetValue(device.StableId, out DeviceCaptureIdentity identity))
        {
            return identity;
        }

        int index = _devicesByStableId.Count;
        uint hash32 = StableHash32(device.StableId);
        ulong numericId = StableHash64($"{device.StableId}|{device.DeviceNode}");
        identity = new DeviceCaptureIdentity(index, hash32, numericId);
        _devicesByStableId[device.StableId] = identity;
        return identity;
    }

    private byte[] BuildFramePayload(ulong deviceNumericId, LinuxEvdevFrameSnapshot snapshot)
    {
        int contactCount = snapshot.Frame.GetClampedContactCount();
        byte[] payload = new byte[AtpCapV3Payload.FrameHeaderSize + (contactCount * AtpCapV3Payload.ContactSize)];
        Span<byte> span = payload.AsSpan();

        BinaryPrimitives.WriteUInt32LittleEndian(span.Slice(0, 4), AtpCapV3Payload.FrameMagic);
        BinaryPrimitives.WriteUInt64LittleEndian(span.Slice(4, 8), (ulong)Math.Max(0, snapshot.FrameSequence));

        double timestampSeconds = (snapshot.Frame.ArrivalQpcTicks - _baseTimestampTicks) / (double)System.Diagnostics.Stopwatch.Frequency;
        BinaryPrimitives.WriteInt64LittleEndian(span.Slice(12, 8), BitConverter.DoubleToInt64Bits(Math.Max(0.0, timestampSeconds)));
        BinaryPrimitives.WriteUInt64LittleEndian(span.Slice(20, 8), deviceNumericId);
        BinaryPrimitives.WriteUInt16LittleEndian(span.Slice(28, 2), (ushort)contactCount);
        span[30] = snapshot.Frame.IsButtonPressed ? AtpCapV3Payload.FrameFlagButtonClicked : (byte)0;
        span[31] = 0;

        int offset = AtpCapV3Payload.FrameHeaderSize;
        for (int index = 0; index < contactCount; index++)
        {
            ContactFrame contact = snapshot.Frame.GetContact(index);
            WriteContact(span.Slice(offset, AtpCapV3Payload.ContactSize), contact, snapshot.MaxX, snapshot.MaxY);
            offset += AtpCapV3Payload.ContactSize;
        }

        return payload;
    }

    private static void WriteContact(Span<byte> destination, ContactFrame contact, ushort maxX, ushort maxY)
    {
        BinaryPrimitives.WriteInt32LittleEndian(destination.Slice(0, 4), unchecked((int)contact.Id));
        WriteSingle(destination.Slice(4, 4), NormalizeCoordinate(contact.X, maxX));
        WriteSingle(destination.Slice(8, 4), NormalizeCoordinate(contact.Y, maxY));
        float normalizedPressure = contact.Pressure / 255.0f;
        WriteSingle(destination.Slice(12, 4), normalizedPressure);
        WriteSingle(destination.Slice(16, 4), normalizedPressure);
        WriteSingle(destination.Slice(20, 4), 0.0f);
        WriteSingle(destination.Slice(24, 4), 0.0f);
        WriteSingle(destination.Slice(28, 4), 0.0f);
        WriteSingle(destination.Slice(32, 4), 0.0f);
        destination[36] = contact.TipSwitch ? (byte)1 : (byte)0;
    }

    private void WriteRecord(
        int deviceIndex,
        uint deviceHash,
        ushort vendorId,
        ushort productId,
        ushort usagePage,
        ushort usage,
        CaptureSideHint sideHint,
        TrackpadDecoderProfile decoderProfile,
        long arrivalQpcTicks,
        ReadOnlySpan<byte> payload)
    {
        Span<byte> header = stackalloc byte[InputCaptureFile.RecordHeaderSize];
        BinaryPrimitives.WriteInt32LittleEndian(header.Slice(0, 4), payload.Length);
        BinaryPrimitives.WriteInt64LittleEndian(header.Slice(4, 8), arrivalQpcTicks);
        BinaryPrimitives.WriteInt32LittleEndian(header.Slice(12, 4), deviceIndex);
        BinaryPrimitives.WriteUInt32LittleEndian(header.Slice(16, 4), deviceHash);
        BinaryPrimitives.WriteUInt32LittleEndian(header.Slice(20, 4), vendorId);
        BinaryPrimitives.WriteUInt32LittleEndian(header.Slice(24, 4), productId);
        BinaryPrimitives.WriteUInt16LittleEndian(header.Slice(28, 2), usagePage);
        BinaryPrimitives.WriteUInt16LittleEndian(header.Slice(30, 2), usage);
        header[32] = (byte)sideHint;
        header[33] = (byte)decoderProfile;
        _stream.Write(header);
        _stream.Write(payload);
    }

    private static CaptureSideHint ToSideHint(TrackpadSide side)
    {
        return side switch
        {
            TrackpadSide.Left => CaptureSideHint.Left,
            TrackpadSide.Right => CaptureSideHint.Right,
            _ => CaptureSideHint.Unknown
        };
    }

    private static float NormalizeCoordinate(ushort value, ushort max)
    {
        if (max == 0)
        {
            return 0.0f;
        }

        return Math.Clamp(value / (float)max, 0.0f, 1.0f);
    }

    private static void WriteSingle(Span<byte> destination, float value)
    {
        BinaryPrimitives.WriteInt32LittleEndian(destination, BitConverter.SingleToInt32Bits(value));
    }

    private static uint StableHash32(string text)
    {
        return unchecked((uint)StableHash64(text));
    }

    private static ulong StableHash64(string text)
    {
        ulong hash = 14695981039346656037UL;
        ReadOnlySpan<byte> utf8 = Encoding.UTF8.GetBytes(text);
        for (int index = 0; index < utf8.Length; index++)
        {
            hash ^= utf8[index];
            hash *= 1099511628211UL;
        }

        return hash;
    }

    private readonly record struct DeviceCaptureIdentity(int Index, uint Hash32, ulong NumericId);
}
