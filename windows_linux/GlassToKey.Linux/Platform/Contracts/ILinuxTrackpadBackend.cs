using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux.Contracts;

public interface ILinuxTrackpadBackend
{
    IReadOnlyList<LinuxInputDeviceDescriptor> EnumerateDevices();
}
