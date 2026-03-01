namespace GlassToKey.Linux.Config;

public sealed class LinuxHostSettings
{
    public int Version { get; set; } = 1;
    public string LayoutPresetName { get; set; } = TrackpadLayoutPreset.SixByThree.Name;
    public string? KeymapPath { get; set; }
    public string? LeftTrackpadStableId { get; set; }
    public string? RightTrackpadStableId { get; set; }
}
