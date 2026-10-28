using GlassToKey;

namespace GlassToKey.Platform.Linux.Models;

public sealed record LinuxRuntimeBindingState(
    TrackpadSide Side,
    string StableId,
    string? DeviceNode,
    LinuxRuntimeBindingStatus Status,
    string Message);
