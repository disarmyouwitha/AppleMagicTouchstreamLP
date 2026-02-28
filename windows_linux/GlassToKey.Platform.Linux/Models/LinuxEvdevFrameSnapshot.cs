using GlassToKey;

namespace GlassToKey.Platform.Linux.Models;

public sealed record LinuxEvdevFrameSnapshot(
    string DeviceNode,
    ushort MaxX,
    ushort MaxY,
    int FrameSequence,
    InputFrame Frame);
