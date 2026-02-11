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
    private const int OfficialMaxRawX = 14720;
    private const int OfficialMaxRawY = 10240;

    public static bool TryDecode(
        ReadOnlySpan<byte> payload,
        in RawInputDeviceInfo deviceInfo,
        long arrivalQpcTicks,
        out TrackpadDecodeResult result)
    {
        return TryDecode(payload, deviceInfo, arrivalQpcTicks, TrackpadDecoderProfile.Official, out result);
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

        if (preferredProfile == TrackpadDecoderProfile.Legacy)
        {
            if (TryDecodePtp(
                payload,
                arrivalQpcTicks,
                TrackpadDecoderProfile.Legacy,
                strictLegacyValidation: false,
                out result))
            {
                return true;
            }

            return false;
        }

        if (TryDecodePtp(
            payload,
            arrivalQpcTicks,
            TrackpadDecoderProfile.Official,
            strictLegacyValidation: true,
            out result))
        {
            return true;
        }

        if (TryDecodePtp(
            payload,
            arrivalQpcTicks,
            TrackpadDecoderProfile.Legacy,
            strictLegacyValidation: false,
            out result))
        {
            return true;
        }

        return TryDecodeAppleNineByte(payload, deviceInfo, arrivalQpcTicks, out result);
    }

    private static bool TryDecodePtp(
        ReadOnlySpan<byte> payload,
        long arrivalQpcTicks,
        TrackpadDecoderProfile profile,
        bool strictLegacyValidation,
        out TrackpadDecodeResult result)
    {
        result = default;
        if (payload.Length < PtpReport.ExpectedSize)
        {
            return false;
        }

        if (payload[0] == RawInputInterop.ReportIdMultitouch &&
            TryParsePtpAtOffset(
                payload,
                0,
                arrivalQpcTicks,
                profile,
                strictLegacyValidation,
                TrackpadReportKind.PtpNative,
                out result))
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

            if (TryParsePtpAtOffset(
                payload,
                offset,
                arrivalQpcTicks,
                profile,
                strictLegacyValidation,
                TrackpadReportKind.PtpEmbedded,
                out result))
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
        bool strictLegacyValidation,
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
            if (!LooksReasonableLegacy(in report, strictLegacyValidation))
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

    private static bool LooksReasonableLegacy(in PtpReport report, bool strictValidation)
    {
        if (report.ContactCount > PtpReport.MaxContacts)
        {
            return false;
        }

        int count = report.GetClampedContactCount();
        if (!strictValidation)
        {
            for (int i = 0; i < count; i++)
            {
                PtpContact contact = report.GetContact(i);
                if (contact.X > MaxReasonableX || contact.Y > MaxReasonableY)
                {
                    return false;
                }
            }

            return true;
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
                // Official stream (usage 0/0) does not match native PTP field packing.
                // The most stable slot mapping seen in captures is:
                // X  -> little-endian [slot+2..3]
                // Y  -> little-endian [slot+4..5]
                // Keeping fields non-overlapping prevents axis pollution from adjacent bytes.
                int rawX = ReadLittleEndianU16(payload[slotOffset + 2], payload[slotOffset + 3]);
                int rawY = ReadLittleEndianU16(payload[slotOffset + 4], payload[slotOffset + 5]);
                x = ScaleOfficialCoordinate(rawX, maxRaw: OfficialMaxRawX, RuntimeConfigurationFactory.DefaultMaxX);
                y = ScaleOfficialCoordinate(rawY, maxRaw: OfficialMaxRawY, RuntimeConfigurationFactory.DefaultMaxY);
            }

            frame.SetContact(i, new ContactFrame((uint)i, x, y, normalizedFlags));
        }
    }

    private static int ReadBigEndianU16(byte hi, byte lo)
    {
        return (hi << 8) | lo;
    }

    private static int ReadLittleEndianU16(byte lo, byte hi)
    {
        return lo | (hi << 8);
    }

    private static ushort ScaleOfficialCoordinate(int value, int maxRaw, ushort targetMax)
    {
        int clamped = Math.Clamp(value, 0, maxRaw);
        int scaled = (clamped * targetMax + (maxRaw / 2)) / maxRaw;
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
