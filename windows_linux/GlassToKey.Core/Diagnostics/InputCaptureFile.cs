using System.Buffers.Binary;
using System.IO;
using System.Text;

namespace GlassToKey;

public static class InputCaptureFile
{
    public const int HeaderSize = 20;
    public const int RecordHeaderSize = 34;
    public const int Version2 = 2;
    public const int Version3 = 3;
    public const int CurrentWriteVersion = Version2;
    public const int CurrentVersion = CurrentWriteVersion;

    private static readonly byte[] s_magic = Encoding.ASCII.GetBytes("ATPCAP01");

    public static void WriteHeader(Stream stream)
    {
        WriteHeader(stream, CurrentWriteVersion, System.Diagnostics.Stopwatch.Frequency);
    }

    public static void WriteHeader(Stream stream, int version, long qpcFrequency)
    {
        if (!IsSupportedReadVersion(version))
        {
            throw new ArgumentOutOfRangeException(nameof(version), $"Capture version {version} is unsupported.");
        }

        Span<byte> header = stackalloc byte[HeaderSize];
        s_magic.CopyTo(header);
        BinaryPrimitives.WriteInt32LittleEndian(header.Slice(8, 4), version);
        BinaryPrimitives.WriteInt64LittleEndian(header.Slice(12, 8), qpcFrequency);
        stream.Write(header);
    }

    public static bool IsSupportedReadVersion(int version)
    {
        return version == Version2 || version == Version3;
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

public readonly record struct CaptureRecord(
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

public enum CaptureSideHint : byte
{
    Unknown = 0,
    Left = 1,
    Right = 2
}

public sealed class InputCaptureReader : IDisposable
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
