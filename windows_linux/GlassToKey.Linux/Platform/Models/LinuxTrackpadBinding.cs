using GlassToKey;

namespace GlassToKey.Platform.Linux.Models;

public sealed record LinuxTrackpadBinding(
    TrackpadSide Side,
    LinuxInputDeviceDescriptor Device);
