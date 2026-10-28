namespace GlassToKey.Linux.Runtime;

public sealed record LinuxRuntimeStateSnapshot(
    bool IsRunning,
    bool TypingEnabled,
    bool KeyboardModeEnabled,
    int ActiveLayer,
    DateTimeOffset UpdatedUtc)
{
    public static LinuxRuntimeStateSnapshot Stopped { get; } = new(
        IsRunning: false,
        TypingEnabled: false,
        KeyboardModeEnabled: false,
        ActiveLayer: 0,
        UpdatedUtc: DateTimeOffset.UtcNow);
}
