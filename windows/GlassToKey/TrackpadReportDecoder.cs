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
    TrackpadDecoderProfile Profile,
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
        return TryDecode(payload, deviceInfo, arrivalQpcTicks, TrackpadDecoderProfile.Auto, out result);
    }

    public static bool TryDecode(
        ReadOnlySpan<byte> payload,
        in RawInputDeviceInfo deviceInfo,
        long arrivalQpcTicks,
        TrackpadDecoderProfile preferredProfile,
        out TrackpadDecodeResult result)
    {
        result = default;
        if (payload.Length == 0)
        {
            return false;
        }

        bool likelyOfficialTransport = IsLikelyOfficialTransport(deviceInfo);

        if (preferredProfile == TrackpadDecoderProfile.Legacy)
        {
            if (TryDecodePtp(payload, arrivalQpcTicks, TrackpadDecoderProfile.Legacy, out result))
            {
                return true;
            }

            return false;
        }

        if (preferredProfile == TrackpadDecoderProfile.Official)
        {
            if (TryDecodePtp(payload, arrivalQpcTicks, TrackpadDecoderProfile.Official, out result))
            {
                return true;
            }

            if (TryDecodePtp(payload, arrivalQpcTicks, TrackpadDecoderProfile.Legacy, out result))
            {
                return true;
            }

            return TryDecodeAppleNineByte(payload, deviceInfo, arrivalQpcTicks, out result);
        }

        if (likelyOfficialTransport)
        {
            if (TryDecodePtp(payload, arrivalQpcTicks, TrackpadDecoderProfile.Official, out result))
            {
                return true;
            }

            if (TryDecodePtp(payload, arrivalQpcTicks, TrackpadDecoderProfile.Legacy, out result))
            {
                return true;
            }
        }
        else
        {
            if (TryDecodePtp(payload, arrivalQpcTicks, TrackpadDecoderProfile.Legacy, out result))
            {
                return true;
            }
        }

        if (TryDecodeAppleNineByte(payload, deviceInfo, arrivalQpcTicks, out result))
        {
            return true;
        }

        return false;
    }

    private static bool TryDecodePtp(
        ReadOnlySpan<byte> payload,
        long arrivalQpcTicks,
        TrackpadDecoderProfile profile,
        out TrackpadDecodeResult result)
    {
        result = default;
        if (payload.Length < PtpReport.ExpectedSize)
        {
            return false;
        }

        if (payload[0] == RawInputInterop.ReportIdMultitouch &&
            TryParsePtpAtOffset(payload, 0, arrivalQpcTicks, profile, TrackpadReportKind.PtpNative, out result))
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

            if (TryParsePtpAtOffset(payload, offset, arrivalQpcTicks, profile, TrackpadReportKind.PtpEmbedded, out result))
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
        TrackpadDecoderProfile profile,
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

        if (profile == TrackpadDecoderProfile.Official)
        {
            if (!LooksReasonableOfficial(in report))
            {
                return false;
            }
        }
        else
        {
            if (!LooksReasonableLegacy(in report))
            {
                return false;
            }
        }

        InputFrame frame = InputFrame.FromReport(arrivalQpcTicks, in report);
        if (profile == TrackpadDecoderProfile.Official)
        {
            NormalizeOfficialTouchFields(ref frame, candidate);
        }
        else
        {
            NormalizeLikelyPackedContactIds(ref frame);
        }

        result = new TrackpadDecodeResult(kind, offset, payload[0], profile, frame);
        return true;
    }

    private static bool LooksReasonableLegacy(in PtpReport report)
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

    private static bool LooksReasonableOfficial(in PtpReport report)
    {
        int count = report.GetClampedContactCount();
        if (report.ContactCount > PtpReport.MaxContacts)
        {
            return false;
        }

        if (count == 0)
        {
            return true;
        }

        bool hasData = false;
        for (int i = 0; i < count; i++)
        {
            PtpContact contact = report.GetContact(i);
            if (contact.X != 0 || contact.Y != 0 || contact.Flags != 0 || contact.ContactId != 0)
            {
                hasData = true;
            }
        }

        return hasData;
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

        result = new TrackpadDecodeResult(TrackpadReportKind.AppleNineByte, bestOffset, sourceReportId, TrackpadDecoderProfile.Official, frame);
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

    private static bool IsLikelyOfficialTransport(in RawInputDeviceInfo deviceInfo)
    {
        if (!RawInputInterop.IsTargetVidPid(deviceInfo.VendorId, deviceInfo.ProductId))
        {
            return false;
        }

        return deviceInfo.UsagePage == 0 && deviceInfo.Usage == 0;
    }

    private static void NormalizeOfficialTouchFields(ref InputFrame frame, ReadOnlySpan<byte> payload)
    {
        int count = frame.GetClampedContactCount();
        for (int i = 0; i < count; i++)
        {
            ContactFrame contact = frame.GetContact(i);
            byte normalizedFlags = (byte)((contact.Flags & 0xFC) | 0x03);
            ushort x = contact.X;
            ushort y = contact.Y;

            int slotOffset = 1 + (i * 9);
            if (slotOffset + 7 < payload.Length)
            {
                int packedX = DecodeOfficialPackedCoordinate(payload[slotOffset + 2], payload[slotOffset + 3], payload[slotOffset + 4]);
                int packedY = DecodeOfficialPackedCoordinate(payload[slotOffset + 5], payload[slotOffset + 6], payload[slotOffset + 7]);
                x = ScaleOfficialCoordinate(packedX, RuntimeConfigurationFactory.DefaultMaxX);
                y = ScaleOfficialCoordinate(packedY, RuntimeConfigurationFactory.DefaultMaxY);
            }

            frame.SetContact(i, new ContactFrame((uint)i, x, y, normalizedFlags));
        }
    }

    private static int DecodeOfficialPackedCoordinate(byte b0, byte b1, byte b2)
    {
        uint packed = ((uint)b0 << 27) | ((uint)b1 << 19) | ((uint)b2 << 11);
        return (int)(packed >> 22);
    }

    private static ushort ScaleOfficialCoordinate(int value, ushort targetMax)
    {
        int clamped = Math.Clamp(value, 0, 1023);
        int scaled = (clamped * targetMax + 511) / 1023;
        return (ushort)Math.Clamp(scaled, 0, targetMax);
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
