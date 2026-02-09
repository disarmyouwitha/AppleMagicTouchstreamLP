using System;
using System.Buffers.Binary;
using System.IO;
using System.Text;

namespace GlassToKey;

internal static class InputCaptureFile
{
    public const int HeaderSize = 20;
    public const int RecordHeaderSize = 32;
    public const int CurrentVersion = 1;

    private static readonly byte[] s_magic = Encoding.ASCII.GetBytes("ATPCAP01");

    public static void WriteHeader(Stream stream)
    {
        Span<byte> header = stackalloc byte[HeaderSize];
        s_magic.CopyTo(header);
        BinaryPrimitives.WriteInt32LittleEndian(header.Slice(8, 4), CurrentVersion);
        BinaryPrimitives.WriteInt64LittleEndian(header.Slice(12, 8), System.Diagnostics.Stopwatch.Frequency);
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
    ReadOnlyMemory<byte> Payload);

internal sealed class InputCaptureWriter : IDisposable
{
    private readonly FileStream _stream;
    private bool _disposed;

    public InputCaptureWriter(string path)
    {
        string? directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        _stream = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read, 64 * 1024, FileOptions.SequentialScan);
        InputCaptureFile.WriteHeader(_stream);
    }

    public void WriteFrame(in RawInputDeviceSnapshot snapshot, ReadOnlySpan<byte> payload, long arrivalQpcTicks)
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof(InputCaptureWriter));
        }

        Span<byte> header = stackalloc byte[InputCaptureFile.RecordHeaderSize];
        BinaryPrimitives.WriteInt32LittleEndian(header.Slice(0, 4), payload.Length);
        BinaryPrimitives.WriteInt64LittleEndian(header.Slice(4, 8), arrivalQpcTicks);
        BinaryPrimitives.WriteInt32LittleEndian(header.Slice(12, 4), snapshot.Tag.Index);
        BinaryPrimitives.WriteUInt32LittleEndian(header.Slice(16, 4), snapshot.Tag.Hash);
        BinaryPrimitives.WriteUInt32LittleEndian(header.Slice(20, 4), snapshot.Info.VendorId);
        BinaryPrimitives.WriteUInt32LittleEndian(header.Slice(24, 4), snapshot.Info.ProductId);
        BinaryPrimitives.WriteUInt16LittleEndian(header.Slice(28, 2), snapshot.Info.UsagePage);
        BinaryPrimitives.WriteUInt16LittleEndian(header.Slice(30, 2), snapshot.Info.Usage);
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

        if (version != InputCaptureFile.CurrentVersion)
        {
            throw new InvalidDataException($"Capture version {version} is unsupported.");
        }

        HeaderQpcFrequency = qpcFrequency;
    }

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
            Payload: new ReadOnlyMemory<byte>(_payloadBuffer, 0, payloadLength));
        return true;
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
