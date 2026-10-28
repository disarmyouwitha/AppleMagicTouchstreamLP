using System;
using System.Buffers.Binary;
using System.IO;

namespace GlassToKey;

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

    public void WriteFrame(
        in RawInputDeviceSnapshot snapshot,
        ReadOnlySpan<byte> payload,
        long arrivalQpcTicks,
        CaptureSideHint sideHint = CaptureSideHint.Unknown,
        TrackpadDecoderProfile decoderProfile = TrackpadDecoderProfile.Official)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        Span<byte> header = stackalloc byte[InputCaptureFile.RecordHeaderSize];
        BinaryPrimitives.WriteInt32LittleEndian(header.Slice(0, 4), payload.Length);
        BinaryPrimitives.WriteInt64LittleEndian(header.Slice(4, 8), arrivalQpcTicks);
        BinaryPrimitives.WriteInt32LittleEndian(header.Slice(12, 4), snapshot.Tag.Index);
        BinaryPrimitives.WriteUInt32LittleEndian(header.Slice(16, 4), snapshot.Tag.Hash);
        BinaryPrimitives.WriteUInt32LittleEndian(header.Slice(20, 4), snapshot.Info.VendorId);
        BinaryPrimitives.WriteUInt32LittleEndian(header.Slice(24, 4), snapshot.Info.ProductId);
        BinaryPrimitives.WriteUInt16LittleEndian(header.Slice(28, 2), snapshot.Info.UsagePage);
        BinaryPrimitives.WriteUInt16LittleEndian(header.Slice(30, 2), snapshot.Info.Usage);
        header[32] = (byte)sideHint;
        header[33] = decoderProfile == TrackpadDecoderProfile.Legacy
            ? (byte)TrackpadDecoderProfile.Legacy
            : (byte)TrackpadDecoderProfile.Official;
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
