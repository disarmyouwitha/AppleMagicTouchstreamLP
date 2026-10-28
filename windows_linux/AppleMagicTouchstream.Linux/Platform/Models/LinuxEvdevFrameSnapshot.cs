using AppleMagicTouchstream;

namespace AppleMagicTouchstream.Platform.Linux.Models;

public sealed record LinuxEvdevFrameSnapshot(
    string DeviceNode,
    int MinX,
    int MinY,
    ushort MaxX,
    ushort MaxY,
    int FrameSequence,
    InputFrame Frame);
