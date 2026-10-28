using System.Buffers.Binary;
using System.IO.Compression;
using Avalonia.Controls;

namespace GlassToKey.Linux.Gui;

internal static class TrayModeIconFactory
{
    private const int IconSize = 16;

    public static WindowIcon CreateUnknown() => CreateCircleIcon(107, 114, 121);

    public static WindowIcon CreateMouse() => CreateCircleIcon(231, 76, 60);

    public static WindowIcon CreateMixed() => CreateCircleIcon(46, 204, 113);

    public static WindowIcon CreateKeyboard() => CreateCircleIcon(155, 89, 182);

    public static WindowIcon CreateLayerActive() => CreateCircleIcon(52, 152, 219);

    private static WindowIcon CreateCircleIcon(byte red, byte green, byte blue)
    {
        byte[] png = BuildPng(red, green, blue);
        return new WindowIcon(new MemoryStream(png, writable: false));
    }

    private static byte[] BuildPng(byte red, byte green, byte blue)
    {
        byte[] rgba = new byte[IconSize * IconSize * 4];
        const double center = 7.5;
        const double outerRadius = 6.0;
        const double outlineWidth = 1.1;

        for (int y = 0; y < IconSize; y++)
        {
            for (int x = 0; x < IconSize; x++)
            {
                double fillCoverage = 0.0;
                double outlineCoverage = 0.0;

                for (int sampleY = 0; sampleY < 4; sampleY++)
                {
                    double py = y + (sampleY + 0.5) / 4.0;
                    for (int sampleX = 0; sampleX < 4; sampleX++)
                    {
                        double px = x + (sampleX + 0.5) / 4.0;
                        double dx = px - center;
                        double dy = py - center;
                        double distance = Math.Sqrt((dx * dx) + (dy * dy));

                        if (distance <= outerRadius)
                        {
                            fillCoverage += 1.0;
                            if (distance >= outerRadius - outlineWidth)
                            {
                                outlineCoverage += 1.0;
                            }
                        }
                    }
                }

                fillCoverage /= 16.0;
                outlineCoverage /= 16.0;
                double alpha = Math.Max(fillCoverage, outlineCoverage);
                if (alpha <= 0.0)
                {
                    continue;
                }

                double outlineWeight = outlineCoverage / alpha;
                byte pixelAlpha = (byte)Math.Round(alpha * 255.0);
                byte pixelRed = (byte)Math.Round((red * (1.0 - outlineWeight)) + (12.0 * outlineWeight));
                byte pixelGreen = (byte)Math.Round((green * (1.0 - outlineWeight)) + (14.0 * outlineWeight));
                byte pixelBlue = (byte)Math.Round((blue * (1.0 - outlineWeight)) + (16.0 * outlineWeight));

                int offset = ((y * IconSize) + x) * 4;
                rgba[offset] = pixelRed;
                rgba[offset + 1] = pixelGreen;
                rgba[offset + 2] = pixelBlue;
                rgba[offset + 3] = pixelAlpha;
            }
        }

        return EncodePng(rgba, IconSize, IconSize);
    }

    private static byte[] EncodePng(byte[] rgba, int width, int height)
    {
        using MemoryStream output = new();
        output.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });

        byte[] header = new byte[13];
        BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(0, 4), width);
        BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4, 4), height);
        header[8] = 8;
        header[9] = 6;
        header[10] = 0;
        header[11] = 0;
        header[12] = 0;
        WriteChunk(output, "IHDR", header);

        byte[] scanlines = new byte[(width * 4 + 1) * height];
        for (int y = 0; y < height; y++)
        {
            int scanlineOffset = y * (width * 4 + 1);
            int pixelOffset = y * width * 4;
            scanlines[scanlineOffset] = 0;
            Buffer.BlockCopy(rgba, pixelOffset, scanlines, scanlineOffset + 1, width * 4);
        }

        using MemoryStream compressed = new();
        using (ZLibStream zlib = new(compressed, CompressionLevel.SmallestSize, leaveOpen: true))
        {
            zlib.Write(scanlines, 0, scanlines.Length);
        }

        WriteChunk(output, "IDAT", compressed.ToArray());
        WriteChunk(output, "IEND", Array.Empty<byte>());
        return output.ToArray();
    }

    private static void WriteChunk(Stream output, string type, byte[] data)
    {
        byte[] typeBytes = System.Text.Encoding.ASCII.GetBytes(type);
        byte[] lengthBytes = new byte[4];
        BinaryPrimitives.WriteInt32BigEndian(lengthBytes, data.Length);
        output.Write(lengthBytes, 0, lengthBytes.Length);
        output.Write(typeBytes, 0, typeBytes.Length);
        output.Write(data, 0, data.Length);

        uint crc = 0xFFFFFFFFu;
        UpdateCrc(typeBytes, ref crc);
        UpdateCrc(data, ref crc);
        crc ^= 0xFFFFFFFFu;

        byte[] crcBytes = new byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(crcBytes, crc);
        output.Write(crcBytes, 0, crcBytes.Length);
    }

    private static void UpdateCrc(byte[] data, ref uint crc)
    {
        for (int i = 0; i < data.Length; i++)
        {
            crc ^= data[i];
            for (int bit = 0; bit < 8; bit++)
            {
                crc = (crc & 1u) != 0
                    ? 0xEDB88320u ^ (crc >> 1)
                    : crc >> 1;
            }
        }
    }
}
