using AppleMagicTouchstream.Platform.Linux.Models;

namespace AppleMagicTouchstream.Platform.Linux.Contracts;

public interface ILinuxTrackpadBackend
{
    IReadOnlyList<LinuxInputDeviceDescriptor> EnumerateDevices();
}
