namespace GlassToKey.Linux.Config;

public sealed class LinuxHostSettings
{
    public int Version { get; set; } = 2;
    public string LayoutPresetName { get; set; } = TrackpadLayoutPreset.SixByThree.Name;
    public string? KeymapPath { get; set; }
    public int KeymapRevision { get; set; }
    public string? LeftTrackpadStableId { get; set; }
    public string? RightTrackpadStableId { get; set; }
    public UserSettings SharedProfile { get; set; } = UserSettings.LoadBundledDefaultsOrDefault();

    public UserSettings GetSharedProfile()
    {
        UserSettings profile = SharedProfile?.Clone() ?? UserSettings.LoadBundledDefaultsOrDefault();
        profile.NormalizeRanges();

        string layoutName = string.IsNullOrWhiteSpace(LayoutPresetName)
            ? profile.LayoutPresetName
            : LayoutPresetName.Trim();
        if (string.IsNullOrWhiteSpace(layoutName))
        {
            layoutName = TrackpadLayoutPreset.SixByThree.Name;
        }

        profile.LayoutPresetName = layoutName;
        profile.NormalizeRanges();
        return profile;
    }

    public bool Normalize()
    {
        bool changed = false;

        if (Version < 2)
        {
            Version = 2;
            changed = true;
        }

        string normalizedLayout = string.IsNullOrWhiteSpace(LayoutPresetName)
            ? TrackpadLayoutPreset.SixByThree.Name
            : LayoutPresetName.Trim();
        if (!string.Equals(LayoutPresetName, normalizedLayout, StringComparison.Ordinal))
        {
            LayoutPresetName = normalizedLayout;
            changed = true;
        }

        int normalizedKeymapRevision = Math.Max(0, KeymapRevision);
        if (normalizedKeymapRevision != KeymapRevision)
        {
            KeymapRevision = normalizedKeymapRevision;
            changed = true;
        }

        UserSettings normalizedProfile = GetSharedProfile();
        bool profileChanged = SharedProfile == null || normalizedProfile.NormalizeRanges();
        if (!string.Equals(normalizedProfile.LayoutPresetName, LayoutPresetName, StringComparison.OrdinalIgnoreCase))
        {
            normalizedProfile.LayoutPresetName = LayoutPresetName;
            normalizedProfile.NormalizeRanges();
            profileChanged = true;
        }

        SharedProfile = normalizedProfile;
        return changed || profileChanged;
    }
}
