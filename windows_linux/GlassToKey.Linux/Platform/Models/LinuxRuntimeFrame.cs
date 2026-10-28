namespace GlassToKey.Platform.Linux.Models;

public sealed record LinuxRuntimeFrame(
    LinuxTrackpadBinding Binding,
    LinuxEvdevFrameSnapshot Snapshot);
