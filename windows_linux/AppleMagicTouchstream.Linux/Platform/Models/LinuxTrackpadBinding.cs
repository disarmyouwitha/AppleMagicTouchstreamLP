using AppleMagicTouchstream;

namespace AppleMagicTouchstream.Platform.Linux.Models;

public sealed record LinuxTrackpadBinding(
    TrackpadSide Side,
    LinuxInputDeviceDescriptor Device);
