namespace GlassToKey;

internal static class TouchProcessorFactory
{
    private const double TrackpadWidthMm = 160.0;
    private const double TrackpadHeightMm = 114.9;
    private const double KeyWidthMm = 18.0;
    private const double KeyHeightMm = 17.0;

    public static TouchProcessorCore CreateDefault(KeymapStore keymap, TrackpadLayoutPreset? preset = null, TouchProcessorConfig? config = null)
    {
        TrackpadLayoutPreset layoutPreset = preset ?? TrackpadLayoutPreset.SixByThree;
        keymap.SetActiveLayout(layoutPreset.Name);
        ColumnLayoutSettings[] columns = ColumnLayoutDefaults.DefaultSettings(layoutPreset.Columns);
        KeyLayout left = LayoutBuilder.BuildLayout(layoutPreset, TrackpadWidthMm, TrackpadHeightMm, KeyWidthMm, KeyHeightMm, columns, mirrored: true);
        KeyLayout right = LayoutBuilder.BuildLayout(layoutPreset, TrackpadWidthMm, TrackpadHeightMm, KeyWidthMm, KeyHeightMm, columns, mirrored: false);
        TouchProcessorCore core = new(left, right, keymap, config);
        core.SetPersistentLayer(0);
        return core;
    }

    public static TouchProcessorCore CreateConfigured(
        KeymapStore keymap,
        UserSettings settings,
        TrackpadLayoutPreset? preset = null)
    {
        ArgumentNullException.ThrowIfNull(keymap);
        ArgumentNullException.ThrowIfNull(settings);

        UserSettings profile = settings.Clone();
        profile.NormalizeRanges();
        TrackpadLayoutPreset layoutPreset = preset ?? TrackpadLayoutPreset.ResolveByNameOrDefault(profile.LayoutPresetName);
        profile.LayoutPresetName = layoutPreset.Name;
        keymap.SetActiveLayout(layoutPreset.Name);

        ColumnLayoutSettings[] columns = RuntimeConfigurationFactory.BuildColumnSettingsForPreset(profile, layoutPreset);
        RuntimeConfigurationFactory.BuildLayouts(profile, keymap, layoutPreset, columns, out KeyLayout left, out KeyLayout right);
        TouchProcessorConfig config = RuntimeConfigurationFactory.BuildTouchConfig(profile);

        TouchProcessorCore core = new(left, right, keymap, config);
        core.SetPersistentLayer(Math.Clamp(profile.ActiveLayer, 0, 7));
        core.SetTypingEnabled(profile.TypingEnabled);
        core.SetKeyboardModeEnabled(profile.KeyboardModeEnabled);
        return core;
    }
}
