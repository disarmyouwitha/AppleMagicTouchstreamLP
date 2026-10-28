namespace GlassToKey.Platform.Linux.Models;

public enum LinuxRuntimeBindingStatus : byte
{
    Starting = 0,
    WaitingForDevice = 1,
    Rebinding = 2,
    Streaming = 3,
    Disconnected = 4,
    Faulted = 5,
    Stopped = 6
}
