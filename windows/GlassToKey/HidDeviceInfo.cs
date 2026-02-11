using System;

namespace GlassToKey;

public sealed class HidDeviceInfo
{
    public HidDeviceInfo(
        string displayName,
        string? path,
        int deviceIndex = -1,
        uint deviceHash = 0,
        ushort suggestedMaxX = 0,
        ushort suggestedMaxY = 0)
    {
        DisplayName = displayName;
        Path = path;
        DeviceIndex = deviceIndex;
        DeviceHash = deviceHash;
        SuggestedMaxX = suggestedMaxX;
        SuggestedMaxY = suggestedMaxY;
    }

    public string DisplayName { get; }
    public string? Path { get; }
    public int DeviceIndex { get; }
    public uint DeviceHash { get; }
    public ushort SuggestedMaxX { get; }
    public ushort SuggestedMaxY { get; }
    public bool IsNone => string.IsNullOrWhiteSpace(Path);

    public override string ToString() => DisplayName;
}
