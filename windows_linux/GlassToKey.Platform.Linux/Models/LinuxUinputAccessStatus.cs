namespace GlassToKey.Platform.Linux.Models;

public sealed record LinuxUinputAccessStatus(
    string DeviceNode,
    bool DevicePresent,
    bool CanOpenReadWrite,
    string AccessError,
    string Guidance)
{
    public bool IsReady => DevicePresent && CanOpenReadWrite;
}
