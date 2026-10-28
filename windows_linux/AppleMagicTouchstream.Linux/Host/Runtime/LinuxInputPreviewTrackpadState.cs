using AppleMagicTouchstream.Platform.Linux.Models;

namespace AppleMagicTouchstream.Linux.Runtime;

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
