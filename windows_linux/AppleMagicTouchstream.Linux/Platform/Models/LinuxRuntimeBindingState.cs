using AppleMagicTouchstream;

namespace AppleMagicTouchstream.Platform.Linux.Models;

public sealed record LinuxRuntimeBindingState(
    TrackpadSide Side,
    string StableId,
    string? DeviceNode,
    LinuxRuntimeBindingStatus Status,
    string Message);
