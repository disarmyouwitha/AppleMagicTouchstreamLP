using System;
using System.Collections.Generic;

namespace AppleMagicTouchstream;

internal static class TrackpadDecoderProfileResolver
{
    private const int OfficialMaxRawX = 14720;
    private const int OfficialMaxRawY = 10240;
    // These are normalization extents, not strict packet-format bounds. The
    // recorded Apple stream exceeds X=14720 near the physical right edge.
    // Permit bounded edge overshoot; the official decoder clamps coordinates.
    private const int OfficialEdgeSlackPercent = 10;
    private const int MaxReasonableLegacyX = 20000;
    private const int MaxReasonableLegacyY = 15000;

    public static bool TryGetConfiguredOverride(
        Dictionary<string, TrackpadDecoderProfile> profilesByPath,
        string? deviceName,
        out TrackpadDecoderProfile profile)
    {
        profile = TrackpadDecoderProfile.Official;
        return !string.IsNullOrWhiteSpace(deviceName) &&
               profilesByPath.TryGetValue(deviceName, out profile);
    }

    public static TrackpadDecoderProfile ResolveForPacket(
        Dictionary<string, TrackpadDecoderProfile> profilesByPath,
        string? deviceName,
        ReadOnlySpan<byte> payload,
        in RawInputDeviceInfo deviceInfo)
    {
        if (TryGetConfiguredOverride(profilesByPath, deviceName, out TrackpadDecoderProfile configuredProfile))
        {
            return configuredProfile;
        }

        return ResolveAuto(payload, in deviceInfo);
    }

    public static TrackpadDecoderProfile ResolveAuto(
        ReadOnlySpan<byte> payload,
        in RawInputDeviceInfo deviceInfo)
    {
        TryResolveAuto(payload,in deviceInfo,out var profile);
        return profile;
    }

    public static bool TryResolveAuto(ReadOnlySpan<byte> payload,in RawInputDeviceInfo deviceInfo,out TrackpadDecoderProfile profile)
    {
        profile=TrackpadDecoderProfile.Official;
        // Extended open-source reports have their own unambiguous layout.
        if (ExtendedPtpReportDecoder.IsExtendedReport(payload,in deviceInfo))
        {
            profile=TrackpadDecoderProfile.Legacy; return true;
        }

        // Apple Bluetooth can advertise digitizer/touchpad usage while still
        // delivering Apple's packed fields. Usage alone is not a wire format.
        if (LooksLikeOfficialPacket(payload, in deviceInfo))
        {
            return true;
        }

        if (LooksLikeNativeTouchpadUsage(in deviceInfo))
        {
            profile=TrackpadDecoderProfile.Legacy; return true;
        }

        if (LooksLikeLegacyPtpPacket(payload))
        {
            profile=TrackpadDecoderProfile.Legacy; return true;
        }

        return false;
    }

    private static bool LooksLikeNativeTouchpadUsage(in RawInputDeviceInfo deviceInfo)
    {
        return deviceInfo.UsagePage == RawInputInterop.UsagePageDigitizer &&
               deviceInfo.Usage == RawInputInterop.UsageTouchpad;
    }

    internal static bool LooksLikeOfficialPacket(
        ReadOnlySpan<byte> payload,
        in RawInputDeviceInfo deviceInfo)
    {
        if (!RawInputInterop.IsTargetVidPid(deviceInfo.VendorId, deviceInfo.ProductId) ||
            !((deviceInfo.UsagePage == 0 && deviceInfo.Usage == 0) || LooksLikeNativeTouchpadUsage(in deviceInfo)) ||
            payload.Length < PtpReport.ExpectedSize ||
            payload[0] != RawInputInterop.ReportIdMultitouch)
        {
            return false;
        }

        int contactCount = payload[48];
        if (contactCount <= 0 || contactCount > PtpReport.MaxContacts)
        {
            return false;
        }

        for (int i = 0; i < contactCount; i++)
        {
            int offset = 1 + (i * 9);
            if (offset + 8 >= payload.Length)
            {
                return false;
            }

            int rawX = ReadLittleEndianU16(payload[offset + 2], payload[offset + 3]);
            int rawY = ReadLittleEndianU16(payload[offset + 4], payload[offset + 5]);
            byte phase = payload[offset + 7];
            byte lifecycle = payload[offset + 8];
            if (payload[offset + 1] != 0 ||
                rawX > OfficialMaxRawX * (100 + OfficialEdgeSlackPercent) / 100 ||
                rawY > OfficialMaxRawY * (100 + OfficialEdgeSlackPercent) / 100 ||
                phase > 3 ||
                (lifecycle != 0x00 && lifecycle != 0x01 && lifecycle != 0x03))
            {
                return false;
            }
        }

        return true;
    }

    private static bool LooksLikeLegacyPtpPacket(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < PtpReport.ExpectedSize ||
            payload[0] != RawInputInterop.ReportIdMultitouch ||
            !PtpReport.TryParse(payload, out PtpReport report) ||
            report.ContactCount > PtpReport.MaxContacts)
        {
            return false;
        }

        int count = report.GetClampedContactCount();
        if (count <= 0)
        {
            return false;
        }

        int plausibleFlagCount = 0;
        for (int i = 0; i < count; i++)
        {
            PtpContact contact = report.GetContact(i);
            if (contact.X > MaxReasonableLegacyX || contact.Y > MaxReasonableLegacyY)
            {
                return false;
            }

            if ((contact.Flags & 0x03) != 0)
            {
                plausibleFlagCount++;
            }
        }

        return plausibleFlagCount > 0;
    }

    private static int ReadLittleEndianU16(byte lo, byte hi)
    {
        return lo | (hi << 8);
    }
}
