namespace GlassToKey.Platform.Linux.Models;

public sealed record LinuxMtContactSnapshot(
    int Slot,
    int TrackingId,
    bool IsActive,
    int XRaw,
    int YRaw,
    int PressureRaw,
    int OrientationRaw);
