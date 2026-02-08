namespace AmtPtpVisualizer;

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
}
