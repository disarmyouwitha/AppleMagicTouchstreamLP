using System;

namespace GlassToKey;

internal enum TrackpadReportKind
{
    Unknown = 0,
    PtpNative = 1,
    PtpEmbedded = 2,
    AppleNineByte = 3
}

internal readonly record struct TrackpadDecodeResult(
    TrackpadReportKind Kind,
    int PayloadOffset,
    byte SourceReportId,
    InputFrame Frame);

internal static class TrackpadReportDecoder
{
    private const int MaxEmbeddedScanOffset = 96;
    private const int MaxReasonableX = 20000;
    private const int MaxReasonableY = 15000;

    public static bool TryDecode(
        ReadOnlySpan<byte> payload,
        in RawInputDeviceInfo deviceInfo,
        long arrivalQpcTicks,
        out TrackpadDecodeResult result)
    {
        result = default;
        if (payload.Length == 0)
        {
            return false;
        }

        if (TryDecodePtp(payload, arrivalQpcTicks, out result))
        {
            return true;
        }

        if (TryDecodeAppleNineByte(payload, deviceInfo, arrivalQpcTicks, out result))
        {
            return true;
        }

        return false;
    }

    private static bool TryDecodePtp(ReadOnlySpan<byte> payload, long arrivalQpcTicks, out TrackpadDecodeResult result)
    {
        result = default;
        if (payload.Length < PtpReport.ExpectedSize)
        {
            return false;
        }

        if (payload[0] == RawInputInterop.ReportIdMultitouch &&
            TryParsePtpAtOffset(payload, 0, arrivalQpcTicks, TrackpadReportKind.PtpNative, out result))
        {
            return true;
        }

        int maxOffset = Math.Min(payload.Length - PtpReport.ExpectedSize, MaxEmbeddedScanOffset);
        for (int offset = 1; offset <= maxOffset; offset++)
        {
            if (payload[offset] != RawInputInterop.ReportIdMultitouch)
            {
                continue;
            }

            if (TryParsePtpAtOffset(payload, offset, arrivalQpcTicks, TrackpadReportKind.PtpEmbedded, out result))
            {
                return true;
            }
        }

        return false;
    }

    private static bool TryParsePtpAtOffset(
        ReadOnlySpan<byte> payload,
        int offset,
        long arrivalQpcTicks,
        TrackpadReportKind kind,
        out TrackpadDecodeResult result)
    {
        result = default;
        if (offset < 0 || offset > payload.Length - PtpReport.ExpectedSize)
        {
            return false;
        }

        ReadOnlySpan<byte> candidate = payload.Slice(offset);
        if (candidate[0] != RawInputInterop.ReportIdMultitouch)
        {
            return false;
        }

        if (!PtpReport.TryParse(candidate, out PtpReport report))
        {
            return false;
        }

        if (!LooksReasonable(in report))
        {
            return false;
        }

        InputFrame frame = InputFrame.FromReport(arrivalQpcTicks, in report);
        NormalizeLikelyPackedContactIds(ref frame);
        result = new TrackpadDecodeResult(kind, offset, payload[0], frame);
        return true;
    }

    private static bool LooksReasonable(in PtpReport report)
    {
        if (report.ContactCount > PtpReport.MaxContacts)
        {
            return false;
        }

        int tipContacts = 0;
        for (int i = 0; i < PtpReport.MaxContacts; i++)
        {
            PtpContact contact = report.GetContact(i);
            if (!contact.TipSwitch)
            {
                continue;
            }

            tipContacts++;
            if (contact.X > MaxReasonableX || contact.Y > MaxReasonableY)
            {
                return false;
            }
        }

        if (report.ContactCount == 0)
        {
            return tipContacts == 0;
        }

        return tipContacts > 0 && tipContacts <= report.GetClampedContactCount();
    }

    private static bool TryDecodeAppleNineByte(
        ReadOnlySpan<byte> payload,
        in RawInputDeviceInfo deviceInfo,
        long arrivalQpcTicks,
        out TrackpadDecodeResult result)
    {
        result = default;
        if (!RawInputInterop.IsTargetVidPid(deviceInfo.VendorId, deviceInfo.ProductId))
        {
            return false;
        }

        if ((ushort)deviceInfo.ProductId != RawInputInterop.ProductIdMt2UsbC)
        {
            return false;
        }

        if (payload.Length < 64)
        {
            return false;
        }

        Span<ContactFrame> contacts = stackalloc ContactFrame[InputFrame.MaxContacts];
        int[] baseOffsets = { 9, 1 };

        int bestCount = 0;
        int bestOffset = -1;
        byte sourceReportId = payload[0];
        Span<ContactFrame> bestContacts = stackalloc ContactFrame[InputFrame.MaxContacts];

        for (int candidate = 0; candidate < baseOffsets.Length; candidate++)
        {
            int baseOffset = baseOffsets[candidate];
            if (payload.Length < baseOffset + 9)
            {
                continue;
            }

            int slots = Math.Min(InputFrame.MaxContacts, (payload.Length - baseOffset) / 9);
            if (slots <= 0)
            {
                continue;
            }

            int contactCount = DecodeAppleNineByteSlots(payload, baseOffset, slots, contacts);
            if (contactCount <= bestCount)
            {
                continue;
            }

            bestCount = contactCount;
            bestOffset = baseOffset;
            contacts.Slice(0, contactCount).CopyTo(bestContacts);
        }

        if (bestCount <= 0 || bestOffset < 0)
        {
            return false;
        }

        InputFrame frame = new()
        {
            ArrivalQpcTicks = arrivalQpcTicks,
            ReportId = sourceReportId,
            ContactCount = (byte)bestCount,
            ScanTime = 0,
            IsButtonClicked = 0
        };

        for (int i = 0; i < bestCount; i++)
        {
            frame.SetContact(i, bestContacts[i]);
        }

        result = new TrackpadDecodeResult(TrackpadReportKind.AppleNineByte, bestOffset, sourceReportId, frame);
        return true;
    }

    private static int DecodeAppleNineByteSlots(
        ReadOnlySpan<byte> payload,
        int baseOffset,
        int slotCount,
        Span<ContactFrame> contacts)
    {
        Span<bool> usedIds = stackalloc bool[16];
        int contactCount = 0;

        for (int slot = 0; slot < slotCount; slot++)
        {
            int index = baseOffset + (slot * 9);
            int x = DecodeAppleCoordinate(payload[index], payload[index + 1], payload[index + 2]);
            int y = DecodeAppleCoordinate(payload[index + 3], payload[index + 4], payload[index + 5]);
            if (x < 0 || y < 0 || x > MaxReasonableX || y > MaxReasonableY)
            {
                continue;
            }

            byte id = (byte)(payload[index + 7] & 0x0F);
            if (usedIds[id])
            {
                continue;
            }

            usedIds[id] = true;
            contacts[contactCount++] = new ContactFrame(
                Id: id,
                X: (ushort)x,
                Y: (ushort)y,
                Flags: 0x03);
            if (contactCount >= contacts.Length)
            {
                break;
            }
        }

        return contactCount;
    }

    private static int DecodeAppleCoordinate(byte b0, byte b1, byte b2)
    {
        int packed = (b0 << 27) | (b1 << 19) | (b2 << 11);
        return packed >> 22;
    }

    private static void NormalizeLikelyPackedContactIds(ref InputFrame frame)
    {
        int count = frame.GetClampedContactCount();
        if (count == 0)
        {
            return;
        }

        int tipCount = 0;
        int suspiciousIdCount = 0;
        for (int i = 0; i < count; i++)
        {
            ContactFrame contact = frame.GetContact(i);
            if (!contact.TipSwitch)
            {
                continue;
            }

            tipCount++;
            if ((contact.Id & 0xFFu) == 0 && contact.Id > 0x00FFFFFFu)
            {
                suspiciousIdCount++;
            }
        }

        if (tipCount == 0 || suspiciousIdCount != tipCount)
        {
            return;
        }

        for (int i = 0; i < count; i++)
        {
            ContactFrame contact = frame.GetContact(i);
            if (!contact.TipSwitch)
            {
                continue;
            }

            frame.SetContact(i, new ContactFrame((uint)i, contact.X, contact.Y, contact.Flags));
        }
    }
}
