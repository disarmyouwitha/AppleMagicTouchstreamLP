namespace GlassToKey.Linux.Runtime;

public sealed record LinuxDesktopRuntimeSnapshot(
    LinuxDesktopRuntimeStatus Status,
    bool TypingEnabled,
    bool KeyboardModeEnabled,
    int ActiveLayer,
    DateTimeOffset UpdatedUtc,
    string Message,
    string? Failure)
{
    public bool IsRunning => Status == LinuxDesktopRuntimeStatus.Running;

    public static LinuxDesktopRuntimeSnapshot Stopped { get; } = new(
        LinuxDesktopRuntimeStatus.Stopped,
        TypingEnabled: false,
        KeyboardModeEnabled: false,
        ActiveLayer: 0,
        UpdatedUtc: DateTimeOffset.UtcNow,
        Message: "The Linux tray runtime is stopped.",
        Failure: null);
}
