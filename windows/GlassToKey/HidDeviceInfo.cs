using System;

namespace GlassToKey;

public sealed class HidDeviceInfo
{
    public HidDeviceInfo(string displayName, string? path, int deviceIndex = -1, uint deviceHash = 0)
    {
        DisplayName = displayName;
        Path = path;
        DeviceIndex = deviceIndex;
        DeviceHash = deviceHash;
    }

    public string DisplayName { get; }
    public string? Path { get; }
    public int DeviceIndex { get; }
    public uint DeviceHash { get; }
    public bool IsNone => string.IsNullOrWhiteSpace(Path);

    public override string ToString() => DisplayName;
}
