using System;

namespace GlassToKey;

internal static class RuntimeConfigurationFactory
{
    public const double TrackpadWidthMm = 160.0;
    public const double TrackpadHeightMm = 114.9;
    public const double KeyWidthMm = 18.0;
    public const double KeyHeightMm = 17.0;
    public const double HardcodedSnapRadiusPercent = 200.0;
    public const double HardcodedKeyBufferMs = 20.0;
    public const ushort DefaultMaxX = 7612;
    public const ushort DefaultMaxY = 5065;

    public static TouchProcessorConfig BuildTouchConfig(UserSettings settings)
    {
        return TouchProcessorConfig.Default with
        {
            TrackpadWidthMm = TrackpadWidthMm,
            TrackpadHeightMm = TrackpadHeightMm,
            HoldDurationMs = settings.HoldDurationMs,
            DragCancelMm = settings.DragCancelMm,
            TypingGraceMs = settings.TypingGraceMs,
            IntentMoveMm = settings.IntentMoveMm,
            IntentVelocityMmPerSec = settings.IntentVelocityMmPerSec,
            SnapRadiusPercent = settings.SnapRadiusPercent > 0.0 ? HardcodedSnapRadiusPercent : 0.0,
            SnapAmbiguityRatio = settings.SnapAmbiguityRatio,
            KeyBufferMs = HardcodedKeyBufferMs,
            TapClickEnabled = settings.TapClickEnabled,
            TwoFingerTapEnabled = settings.TwoFingerTapEnabled,
            ThreeFingerTapEnabled = settings.ThreeFingerTapEnabled,
            TapStaggerToleranceMs = settings.TapStaggerToleranceMs,
            TapCadenceWindowMs = settings.TapCadenceWindowMs,
            TapMoveThresholdMm = settings.TapMoveThresholdMm,
            ChordShiftEnabled = settings.ChordShiftEnabled
        };
    }

    public static void BuildLayouts(
        UserSettings settings,
        TrackpadLayoutPreset preset,
        ColumnLayoutSettings[] columnSettings,
        out KeyLayout leftLayout,
        out KeyLayout rightLayout)
    {
        leftLayout = LayoutBuilder.BuildLayout(
            preset,
            TrackpadWidthMm,
            TrackpadHeightMm,
            KeyWidthMm,
            KeyHeightMm,
            columnSettings,
            mirrored: true,
            keySpacingPercent: settings.KeyPaddingPercent);

        rightLayout = LayoutBuilder.BuildLayout(
            preset,
            TrackpadWidthMm,
            TrackpadHeightMm,
            KeyWidthMm,
            KeyHeightMm,
            columnSettings,
            mirrored: false,
            keySpacingPercent: settings.KeyPaddingPercent);
    }

    public static ColumnLayoutSettings[] CloneColumnSettings(ColumnLayoutSettings[] source)
    {
        ColumnLayoutSettings[] output = new ColumnLayoutSettings[source.Length];
        for (int i = 0; i < source.Length; i++)
        {
            ColumnLayoutSettings item = source[i];
            output[i] = new ColumnLayoutSettings(item.Scale, item.OffsetXPercent, item.OffsetYPercent, item.RowSpacingPercent);
        }

        return output;
    }

    public static ColumnLayoutSettings[] BuildColumnSettingsForPreset(UserSettings settings, TrackpadLayoutPreset preset)
    {
        ColumnLayoutSettings[] defaults = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        if (settings.ColumnSettings == null || settings.ColumnSettings.Count != preset.Columns)
        {
            return defaults;
        }

        ColumnLayoutSettings[] output = new ColumnLayoutSettings[preset.Columns];
        for (int i = 0; i < preset.Columns; i++)
        {
            ColumnLayoutSettings saved = settings.ColumnSettings[i] ?? new ColumnLayoutSettings();
            output[i] = new ColumnLayoutSettings(
                scale: Math.Clamp(saved.Scale, 0.25, 3.0),
                offsetXPercent: saved.OffsetXPercent,
                offsetYPercent: saved.OffsetYPercent,
                rowSpacingPercent: saved.RowSpacingPercent);
        }

        return output;
    }
}
