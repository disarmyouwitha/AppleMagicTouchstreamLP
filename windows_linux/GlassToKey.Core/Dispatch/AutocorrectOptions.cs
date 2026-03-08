using System;

namespace GlassToKey;

public readonly record struct AutocorrectOptions(
    int MaxEditDistance,
    bool DryRunEnabled,
    string BlacklistCsv,
    string OverridesCsv)
{
    public static AutocorrectOptions FromSettings(UserSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return new AutocorrectOptions(
            MaxEditDistance: settings.AutocorrectMaxEditDistance,
            DryRunEnabled: settings.AutocorrectDryRunEnabled,
            BlacklistCsv: settings.AutocorrectBlacklistCsv ?? string.Empty,
            OverridesCsv: settings.AutocorrectOverridesCsv ?? string.Empty);
    }
}
