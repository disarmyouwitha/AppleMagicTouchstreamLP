namespace GlassToKey.Linux.Runtime;

public sealed record LinuxBackgroundRuntimeStatus(
    bool IsRunning,
    int? ProcessId,
    string MarkerPath,
    string Message);
