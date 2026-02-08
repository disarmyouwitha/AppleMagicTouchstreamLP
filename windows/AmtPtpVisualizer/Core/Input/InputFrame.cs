using System;

namespace AmtPtpVisualizer;

public readonly record struct ContactFrame(uint Id, ushort X, ushort Y, byte Flags)
{
    public bool TipSwitch => (Flags & 0x02) != 0;
    public bool Confidence => (Flags & 0x01) != 0;
    public byte Pressure6 => (byte)((Flags >> 2) & 0x3F);
    public byte PressureApprox => (byte)(Pressure6 << 2);

    public static ContactFrame FromPtpContact(in PtpContact contact)
    {
        return new ContactFrame(contact.ContactId, contact.X, contact.Y, contact.Flags);
    }
}

public struct InputFrame
{
    public const int MaxContacts = 5;

    public long ArrivalQpcTicks;
    public byte ReportId;
    public ushort ScanTime;
    public byte ContactCount;
    public byte IsButtonClicked;
    public ContactFrame Contact0;
    public ContactFrame Contact1;
    public ContactFrame Contact2;
    public ContactFrame Contact3;
    public ContactFrame Contact4;

    public readonly int GetClampedContactCount()
    {
        return ContactCount <= MaxContacts ? ContactCount : MaxContacts;
    }

    public readonly ContactFrame GetContact(int index)
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

    public void SetContact(int index, in ContactFrame contact)
    {
        switch (index)
        {
            case 0:
                Contact0 = contact;
                break;
            case 1:
                Contact1 = contact;
                break;
            case 2:
                Contact2 = contact;
                break;
            case 3:
                Contact3 = contact;
                break;
            case 4:
                Contact4 = contact;
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(index));
        }
    }

    public static InputFrame FromReport(long arrivalQpcTicks, in PtpReport report)
    {
        InputFrame frame = new()
        {
            ArrivalQpcTicks = arrivalQpcTicks,
            ReportId = report.ReportId,
            ScanTime = report.ScanTime,
            ContactCount = report.ContactCount,
            IsButtonClicked = report.IsButtonClicked
        };

        int count = report.GetClampedContactCount();
        for (int i = 0; i < count; i++)
        {
            frame.SetContact(i, ContactFrame.FromPtpContact(report.GetContact(i)));
        }

        return frame;
    }
}
