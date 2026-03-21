using System;
using System.Collections.Generic;

namespace GlassToKey;

internal static class TrackpadDecoderProfileResolver
{
    private const int OfficialMaxRawX = 14720;
    private const int OfficialMaxRawY = 10240;
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
        if (LooksLikeNativeTouchpadUsage(in deviceInfo))
        {
            return TrackpadDecoderProfile.Legacy;
        }

        if (LooksLikeOfficialUsageZeroPacket(payload, in deviceInfo))
        {
            return TrackpadDecoderProfile.Official;
        }

        if (LooksLikeLegacyPtpPacket(payload))
        {
            return TrackpadDecoderProfile.Legacy;
        }

        return TrackpadDecoderProfile.Official;
    }

    private static bool LooksLikeNativeTouchpadUsage(in RawInputDeviceInfo deviceInfo)
    {
        return deviceInfo.UsagePage == RawInputInterop.UsagePageDigitizer &&
               deviceInfo.Usage == RawInputInterop.UsageTouchpad;
    }

    private static bool LooksLikeOfficialUsageZeroPacket(
        ReadOnlySpan<byte> payload,
        in RawInputDeviceInfo deviceInfo)
    {
        if (!RawInputInterop.IsTargetVidPid(deviceInfo.VendorId, deviceInfo.ProductId) ||
            deviceInfo.UsagePage != 0 ||
            deviceInfo.Usage != 0 ||
            payload.Length < PtpReport.ExpectedSize ||
            payload[0] != RawInputInterop.ReportIdMultitouch)
        {
            return false;
        }

        int contactCount = Math.Min((int)payload[48], PtpReport.MaxContacts);
        if (contactCount <= 0)
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
            if (rawX > OfficialMaxRawX ||
                rawY > OfficialMaxRawY ||
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
