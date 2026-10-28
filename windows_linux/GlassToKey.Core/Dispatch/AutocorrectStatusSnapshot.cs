namespace GlassToKey;

public readonly record struct AutocorrectStatusSnapshot(
    bool Enabled,
    bool DryRunEnabled,
    int MaxEditDistance,
    string CurrentApp,
    string LastCorrected,
    string CurrentBuffer,
    string SkipReason,
    string LastResetSource,
    long CorrectedCount,
    long SkippedCount,
    long ResetByClickCount,
    long ResetByAppChangeCount,
    long ShortcutBypassCount,
    string WordHistory);
