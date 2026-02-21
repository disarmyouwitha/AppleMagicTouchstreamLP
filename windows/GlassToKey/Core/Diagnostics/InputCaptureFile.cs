using System;
using System.Buffers.Binary;
using System.IO;
using System.Text;

namespace GlassToKey;

internal static class InputCaptureFile
{
    public const int HeaderSize = 20;
    public const int RecordHeaderSize = 34;
    public const int LegacyVersion = 2;
    public const int CurrentWriteVersion = 3;

    private static readonly byte[] s_magic = Encoding.ASCII.GetBytes("ATPCAP01");

    public static void WriteHeader(Stream stream, int version = CurrentWriteVersion, long? tickFrequency = null)
    {
        Span<byte> header = stackalloc byte[HeaderSize];
        s_magic.CopyTo(header);
        BinaryPrimitives.WriteInt32LittleEndian(header.Slice(8, 4), version);
        BinaryPrimitives.WriteInt64LittleEndian(header.Slice(12, 8), tickFrequency.GetValueOrDefault(System.Diagnostics.Stopwatch.Frequency));
        stream.Write(header);
    }

    public static bool TryReadHeader(Stream stream, out int version, out long qpcFrequency)
    {
        Span<byte> header = stackalloc byte[HeaderSize];
        if (!TryReadExact(stream, header))
        {
            version = 0;
            qpcFrequency = 0;
            return false;
        }

        if (!header.Slice(0, 8).SequenceEqual(s_magic))
        {
            version = 0;
            qpcFrequency = 0;
            return false;
        }

        version = BinaryPrimitives.ReadInt32LittleEndian(header.Slice(8, 4));
        qpcFrequency = BinaryPrimitives.ReadInt64LittleEndian(header.Slice(12, 8));
        return true;
    }

    public static bool IsSupportedReadVersion(int version)
    {
        return version == LegacyVersion || version == CurrentWriteVersion;
    }

    private static bool TryReadExact(Stream stream, Span<byte> destination)
    {
        int totalRead = 0;
        while (totalRead < destination.Length)
        {
            int bytesRead = stream.Read(destination.Slice(totalRead));
            if (bytesRead <= 0)
            {
                return false;
            }

            totalRead += bytesRead;
        }

        return true;
    }
}

internal readonly record struct CaptureRecord(
    long ArrivalQpcTicks,
    int DeviceIndex,
    uint DeviceHash,
    uint VendorId,
    uint ProductId,
    ushort UsagePage,
    ushort Usage,
    CaptureSideHint SideHint,
    TrackpadDecoderProfile DecoderProfile,
    ReadOnlyMemory<byte> Payload);

internal enum CaptureSideHint : byte
{
    Unknown = 0,
    Left = 1,
    Right = 2
}

internal sealed class InputCaptureWriter : IDisposable
{
    private readonly FileStream _stream;
    private readonly int _writeVersion;
    private ulong _v3Sequence = 1;
    private bool _disposed;

    public InputCaptureWriter(string path, int writeVersion = InputCaptureFile.CurrentWriteVersion)
    {
        if (writeVersion != InputCaptureFile.LegacyVersion &&
            writeVersion != InputCaptureFile.CurrentWriteVersion)
        {
            throw new ArgumentOutOfRangeException(nameof(writeVersion), $"Unsupported capture write version {writeVersion}.");
        }

        string? directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        _writeVersion = writeVersion;
        _stream = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read, 64 * 1024, FileOptions.SequentialScan);
        InputCaptureFile.WriteHeader(_stream, _writeVersion);
        if (_writeVersion == InputCaptureFile.CurrentWriteVersion)
        {
            WriteV3MetaRecord();
        }
    }

    public int WriteVersion => _writeVersion;

    public void WriteFrame(
        in RawInputDeviceSnapshot snapshot,
        ReadOnlySpan<byte> payload,
        long arrivalQpcTicks,
        CaptureSideHint sideHint = CaptureSideHint.Unknown,
        TrackpadDecoderProfile decoderProfile = TrackpadDecoderProfile.Official)
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof(InputCaptureWriter));
        }

        if (_writeVersion != InputCaptureFile.LegacyVersion)
        {
            throw new InvalidOperationException("Raw HID payload writes are only valid for ATPCAP v2.");
        }

        byte decoderProfileByte = decoderProfile == TrackpadDecoderProfile.Legacy
            ? (byte)TrackpadDecoderProfile.Legacy
            : (byte)TrackpadDecoderProfile.Official;
        WriteRecord(
            payload,
            arrivalQpcTicks,
            snapshot.Tag.Index,
            snapshot.Tag.Hash,
            snapshot.Info.VendorId,
            snapshot.Info.ProductId,
            snapshot.Info.UsagePage,
            snapshot.Info.Usage,
            sideHint,
            decoderProfileByte);
    }

    public void WriteFrameV3(
        in RawInputDeviceSnapshot snapshot,
        in InputFrame frame,
        long arrivalQpcTicks,
        CaptureSideHint sideHint = CaptureSideHint.Unknown)
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof(InputCaptureWriter));
        }

        if (_writeVersion != InputCaptureFile.CurrentWriteVersion)
        {
            throw new InvalidOperationException("RFV3 frame writes are only valid for ATPCAP v3.");
        }

        ulong deviceNumericId = ((ulong)(uint)snapshot.Tag.Index << 32) | snapshot.Tag.Hash;
        byte[] payload = AtpCapV3Payload.EncodeFramePayload(
            in frame,
            _v3Sequence,
            deviceNumericId,
            RuntimeConfigurationFactory.DefaultMaxX,
            RuntimeConfigurationFactory.DefaultMaxY);
        _v3Sequence++;

        WriteRecord(
            payload,
            arrivalQpcTicks,
            snapshot.Tag.Index,
            snapshot.Tag.Hash,
            snapshot.Info.VendorId,
            snapshot.Info.ProductId,
            snapshot.Info.UsagePage,
            snapshot.Info.Usage,
            sideHint,
            decoderProfile: 0);
    }

    private void WriteV3MetaRecord()
    {
        byte[] payload = AtpCapV3Payload.CreateMetaPayload(
            platform: "windows",
            source: "GlassToKeyCapture",
            framesCaptured: 0);
        WriteRecord(
            payload,
            arrivalQpcTicks: 0,
            deviceIndex: AtpCapV3Payload.MetaDeviceIndex,
            deviceHash: 0,
            vendorId: 0,
            productId: 0,
            usagePage: 0,
            usage: 0,
            sideHint: CaptureSideHint.Unknown,
            decoderProfile: 0);
    }

    private void WriteRecord(
        ReadOnlySpan<byte> payload,
        long arrivalQpcTicks,
        int deviceIndex,
        uint deviceHash,
        uint vendorId,
        uint productId,
        ushort usagePage,
        ushort usage,
        CaptureSideHint sideHint,
        byte decoderProfile)
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
        header[33] = decoderProfile;
        _stream.Write(header);
        _stream.Write(payload);
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
}

internal sealed class InputCaptureReader : IDisposable
{
    private readonly FileStream _stream;
    private byte[] _payloadBuffer = Array.Empty<byte>();
    private bool _disposed;

    public InputCaptureReader(string path)
    {
        _stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 64 * 1024, FileOptions.SequentialScan);
        if (!InputCaptureFile.TryReadHeader(_stream, out int version, out long qpcFrequency))
        {
            throw new InvalidDataException("Capture header is invalid.");
        }

        if (!InputCaptureFile.IsSupportedReadVersion(version))
        {
            throw new InvalidDataException($"Capture version {version} is unsupported.");
        }

        if (qpcFrequency <= 0)
        {
            throw new InvalidDataException($"Capture tick frequency {qpcFrequency} is invalid.");
        }

        HeaderVersion = version;
        HeaderQpcFrequency = qpcFrequency;
    }

    public int HeaderVersion { get; }
    public long HeaderQpcFrequency { get; }

    public bool TryReadNext(out CaptureRecord record)
    {
        record = default;
        Span<byte> header = stackalloc byte[InputCaptureFile.RecordHeaderSize];
        int firstByte = _stream.ReadByte();
        if (firstByte < 0)
        {
            return false;
        }

        header[0] = (byte)firstByte;
        if (!TryReadExact(_stream, header.Slice(1)))
        {
            throw new InvalidDataException("Capture record header is truncated.");
        }

        int payloadLength = BinaryPrimitives.ReadInt32LittleEndian(header.Slice(0, 4));
        if (payloadLength < 0 || payloadLength > 64 * 1024)
        {
            throw new InvalidDataException($"Invalid payload length {payloadLength}.");
        }

        if (_payloadBuffer.Length < payloadLength)
        {
            _payloadBuffer = new byte[payloadLength];
        }

        if (!TryReadExact(_stream, _payloadBuffer.AsSpan(0, payloadLength)))
        {
            throw new InvalidDataException("Capture record payload is truncated.");
        }

        record = new CaptureRecord(
            ArrivalQpcTicks: BinaryPrimitives.ReadInt64LittleEndian(header.Slice(4, 8)),
            DeviceIndex: BinaryPrimitives.ReadInt32LittleEndian(header.Slice(12, 4)),
            DeviceHash: BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(16, 4)),
            VendorId: BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(20, 4)),
            ProductId: BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(24, 4)),
            UsagePage: BinaryPrimitives.ReadUInt16LittleEndian(header.Slice(28, 2)),
            Usage: BinaryPrimitives.ReadUInt16LittleEndian(header.Slice(30, 2)),
            SideHint: ParseSideHint(header[32]),
            DecoderProfile: ParseDecoderProfile(header[33]),
            Payload: new ReadOnlyMemory<byte>(_payloadBuffer, 0, payloadLength));
        return true;
    }

    private static CaptureSideHint ParseSideHint(byte value)
    {
        return value switch
        {
            (byte)CaptureSideHint.Left => CaptureSideHint.Left,
            (byte)CaptureSideHint.Right => CaptureSideHint.Right,
            _ => CaptureSideHint.Unknown
        };
    }

    private static TrackpadDecoderProfile ParseDecoderProfile(byte value)
    {
        return value == (byte)TrackpadDecoderProfile.Legacy
            ? TrackpadDecoderProfile.Legacy
            : TrackpadDecoderProfile.Official;
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

    private static bool TryReadExact(Stream stream, Span<byte> destination)
    {
        int totalRead = 0;
        while (totalRead < destination.Length)
        {
            int bytesRead = stream.Read(destination.Slice(totalRead));
            if (bytesRead <= 0)
            {
                return false;
            }

            totalRead += bytesRead;
        }

        return true;
    }
}
