using System;
using System.Collections.Generic;

namespace GlassToKey;

public enum TrackpadDecoderProfile
{
    Legacy = 1,
    Official = 2
}

internal static class TrackpadDecoderProfileMap
{
    public static Dictionary<string, TrackpadDecoderProfile> BuildFromSettings(UserSettings settings)
    {
        Dictionary<string, TrackpadDecoderProfile> map = new(StringComparer.OrdinalIgnoreCase);
        if (settings.DecoderProfilesByDevicePath == null)
        {
            return map;
        }

        foreach (KeyValuePair<string, string> pair in settings.DecoderProfilesByDevicePath)
        {
            if (string.IsNullOrWhiteSpace(pair.Key))
            {
                continue;
            }

            if (!TryParse(pair.Value, out TrackpadDecoderProfile profile))
            {
                continue;
            }

            map[pair.Key] = profile;
        }

        return map;
    }

    public static bool TryParse(string? value, out TrackpadDecoderProfile profile)
    {
        profile = TrackpadDecoderProfile.Official;
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        if (string.Equals(value, "auto", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (string.Equals(value, "legacy", StringComparison.OrdinalIgnoreCase))
        {
            profile = TrackpadDecoderProfile.Legacy;
            return true;
        }

        if (string.Equals(value, "official", StringComparison.OrdinalIgnoreCase))
        {
            profile = TrackpadDecoderProfile.Official;
            return true;
        }

        return false;
    }

    public static string ToSettingsValue(TrackpadDecoderProfile profile)
    {
        return profile == TrackpadDecoderProfile.Legacy ? "legacy" : "official";
    }
}
