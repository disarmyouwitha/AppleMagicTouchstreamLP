namespace GlassToKey.Linux.Runtime;

public sealed record LinuxSystemdServiceStatus(
    string UnitName,
    bool IsRunning,
    int? ProcessId,
    string ActiveState,
    string SubState,
    string Message);
