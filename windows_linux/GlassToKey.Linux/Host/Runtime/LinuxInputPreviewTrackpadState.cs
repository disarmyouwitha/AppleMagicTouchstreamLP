using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Runtime;

public sealed record LinuxInputPreviewTrackpadState(
    TrackpadSide Side,
    string StableId,
    string? DeviceNode,
    ushort MaxX,
    ushort MaxY,
    bool IsButtonPressed,
    int ContactCount,
    int FrameSequence,
    LinuxRuntimeBindingStatus BindingStatus,
    string BindingMessage,
    IReadOnlyList<LinuxInputPreviewContact> Contacts);
