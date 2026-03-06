namespace GlassToKey.Linux.Runtime;

public sealed record LinuxGuiHostStatus(
    bool IsRunning,
    int? ProcessId,
    bool OwnsRuntime,
    string MarkerPath,
    string Message);

