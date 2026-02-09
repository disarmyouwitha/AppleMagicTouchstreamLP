using System;
using System.Buffers.Binary;
using System.Runtime.InteropServices;

namespace GlassToKey;

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct PtpContact
{
    public byte Flags;
    public uint ContactId;
    public ushort X;
    public ushort Y;

    public bool TipSwitch => (Flags & 0x02) != 0;
    public bool Confidence => (Flags & 0x01) != 0;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct PtpReport
{
    public const int MaxContacts = 5;
    public const int ExpectedSize = 50;

    public byte ReportId;
    public PtpContact Contact0;
    public PtpContact Contact1;
    public PtpContact Contact2;
    public PtpContact Contact3;
    public PtpContact Contact4;

    public ushort ScanTime;
    public byte ContactCount;
    public byte IsButtonClicked;

    public readonly int GetClampedContactCount()
    {
        return ContactCount <= MaxContacts ? ContactCount : MaxContacts;
    }

    public readonly PtpContact GetContact(int index)
    {
        return index switch
        {
            0 => Contact0,
            1 => Contact1,
            2 => Contact2,
            3 => Contact3,
            4 => Contact4,
            _ => throw new ArgumentOutOfRangeException(nameof(index))
        };
    }

    public void SetContact(int index, in PtpContact value)
    {
        switch (index)
        {
            case 0:
                Contact0 = value;
                break;
            case 1:
                Contact1 = value;
                break;
            case 2:
                Contact2 = value;
                break;
            case 3:
                Contact3 = value;
                break;
            case 4:
                Contact4 = value;
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(index));
        }
    }

    public static PtpReport FromBuffer(byte[] buffer)
    {
        if (buffer == null) throw new ArgumentNullException(nameof(buffer));
        return FromBuffer(buffer.AsSpan());
    }

    public static PtpReport FromBuffer(ReadOnlySpan<byte> buffer)
    {
        if (!TryParse(buffer, out PtpReport report))
        {
            throw new ArgumentException($"Buffer must be at least {ExpectedSize} bytes.", nameof(buffer));
        }

        return report;
    }

    public static bool TryParse(ReadOnlySpan<byte> buffer, out PtpReport report)
    {
        report = default;
        if (buffer.Length < ExpectedSize)
        {
            return false;
        }

        report.ReportId = buffer[0];

        int offset = 1;
        for (int i = 0; i < MaxContacts; i++)
        {
            byte flags = buffer[offset++];
            uint contactId = BinaryPrimitives.ReadUInt32LittleEndian(buffer.Slice(offset, 4));
            offset += 4;
            ushort x = BinaryPrimitives.ReadUInt16LittleEndian(buffer.Slice(offset, 2));
            offset += 2;
            ushort y = BinaryPrimitives.ReadUInt16LittleEndian(buffer.Slice(offset, 2));
            offset += 2;

            report.SetContact(i, new PtpContact
            {
                Flags = flags,
                ContactId = contactId,
                X = x,
                Y = y
            });
        }

        report.ScanTime = BinaryPrimitives.ReadUInt16LittleEndian(buffer.Slice(offset, 2));
        offset += 2;
        report.ContactCount = buffer[offset++];
        report.IsButtonClicked = buffer[offset];
        return true;
    }
}
