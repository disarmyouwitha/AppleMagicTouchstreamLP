using System;
using System.Collections.Generic;

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
        bool chordShiftEnabled = IsChordShiftGestureAction(settings.FourFingerHoldAction);

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
            FiveFingerSwipeLeftAction = settings.FiveFingerSwipeLeftAction,
            FiveFingerSwipeRightAction = settings.FiveFingerSwipeRightAction,
            ThreeFingerSwipeLeftAction = settings.ThreeFingerSwipeLeftAction,
            ThreeFingerSwipeRightAction = settings.ThreeFingerSwipeRightAction,
            ThreeFingerSwipeUpAction = settings.ThreeFingerSwipeUpAction,
            ThreeFingerSwipeDownAction = settings.ThreeFingerSwipeDownAction,
            FourFingerSwipeLeftAction = settings.FourFingerSwipeLeftAction,
            FourFingerSwipeRightAction = settings.FourFingerSwipeRightAction,
            FourFingerSwipeUpAction = settings.FourFingerSwipeUpAction,
            FourFingerSwipeDownAction = settings.FourFingerSwipeDownAction,
            TwoFingerHoldAction = settings.TwoFingerHoldAction,
            ThreeFingerHoldAction = settings.ThreeFingerHoldAction,
            FourFingerHoldAction = settings.FourFingerHoldAction,
            OuterCornersAction = settings.OuterCornersAction,
            InnerCornersAction = settings.InnerCornersAction,
            TopLeftTriangleAction = settings.TopLeftTriangleAction,
            TopRightTriangleAction = settings.TopRightTriangleAction,
            BottomLeftTriangleAction = settings.BottomLeftTriangleAction,
            BottomRightTriangleAction = settings.BottomRightTriangleAction,
            ForceClick1Action = settings.ForceClick1Action,
            ForceClick2Action = settings.ForceClick2Action,
            ForceClick3Action = settings.ForceClick3Action,
            UpperLeftCornerClickAction = settings.UpperLeftCornerClickAction,
            UpperRightCornerClickAction = settings.UpperRightCornerClickAction,
            LowerLeftCornerClickAction = settings.LowerLeftCornerClickAction,
            LowerRightCornerClickAction = settings.LowerRightCornerClickAction,
            ForceMin = settings.ForceMin,
            ForceCap = settings.ForceCap,
            ChordShiftEnabled = chordShiftEnabled
        };
    }

    private static bool IsChordShiftGestureAction(string? action)
    {
        return string.Equals(action?.Trim(), "Chordal Shift", StringComparison.OrdinalIgnoreCase);
    }

    public static void BuildLayouts(
        UserSettings settings,
        TrackpadLayoutPreset preset,
        ColumnLayoutSettings[] columnSettings,
        out KeyLayout leftLayout,
        out KeyLayout rightLayout)
    {
        double keyPaddingPercent = GetKeyPaddingPercentForPreset(settings, preset);
        leftLayout = LayoutBuilder.BuildLayout(
            preset,
            TrackpadWidthMm,
            TrackpadHeightMm,
            KeyWidthMm,
            KeyHeightMm,
            columnSettings,
            mirrored: true,
            keySpacingPercent: keyPaddingPercent);

        rightLayout = LayoutBuilder.BuildLayout(
            preset,
            TrackpadWidthMm,
            TrackpadHeightMm,
            KeyWidthMm,
            KeyHeightMm,
            columnSettings,
            mirrored: false,
            keySpacingPercent: keyPaddingPercent);
    }

    public static double GetKeyPaddingPercentForPreset(UserSettings settings, TrackpadLayoutPreset preset)
    {
        if (settings.KeyPaddingPercentByLayout != null &&
            settings.KeyPaddingPercentByLayout.TryGetValue(preset.Name, out double byLayout))
        {
            return Math.Clamp(byLayout, 0.0, 90.0);
        }

        if (string.Equals(settings.LayoutPresetName, preset.Name, StringComparison.OrdinalIgnoreCase))
        {
            return Math.Clamp(settings.KeyPaddingPercent, 0.0, 90.0);
        }

        return 10.0;
    }

    public static void SaveKeyPaddingForPreset(
        UserSettings settings,
        TrackpadLayoutPreset preset,
        double keyPaddingPercent)
    {
        settings.KeyPaddingPercentByLayout ??= new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        double clamped = Math.Clamp(keyPaddingPercent, 0.0, 90.0);
        settings.KeyPaddingPercentByLayout[preset.Name] = clamped;
        if (string.Equals(settings.LayoutPresetName, preset.Name, StringComparison.OrdinalIgnoreCase))
        {
            settings.KeyPaddingPercent = clamped;
        }
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
        if (!preset.AllowsColumnSettings)
        {
            return BuildFixedColumnSettingsForPreset(preset);
        }

        ColumnLayoutSettings[] defaults = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        List<ColumnLayoutSettings>? savedSettings = null;

        if (settings.ColumnSettingsByLayout != null &&
            settings.ColumnSettingsByLayout.TryGetValue(preset.Name, out List<ColumnLayoutSettings>? byLayout))
        {
            savedSettings = byLayout;
        }

        if (savedSettings == null &&
            settings.ColumnSettings != null &&
            settings.ColumnSettings.Count > 0 &&
            string.Equals(settings.LayoutPresetName, preset.Name, StringComparison.OrdinalIgnoreCase))
        {
            // Backward compatibility for pre-layout-scoped settings files.
            savedSettings = settings.ColumnSettings;
        }

        if (savedSettings == null || savedSettings.Count != preset.Columns)
        {
            return defaults;
        }

        ColumnLayoutSettings[] output = new ColumnLayoutSettings[preset.Columns];
        for (int i = 0; i < preset.Columns; i++)
        {
            ColumnLayoutSettings saved = savedSettings[i] ?? new ColumnLayoutSettings();
            output[i] = new ColumnLayoutSettings(
                scale: Math.Clamp(saved.Scale, 0.25, 3.0),
                offsetXPercent: saved.OffsetXPercent,
                offsetYPercent: saved.OffsetYPercent,
                rowSpacingPercent: saved.RowSpacingPercent);
        }

        return output;
    }

    public static void SaveColumnSettingsForPreset(
        UserSettings settings,
        TrackpadLayoutPreset preset,
        ColumnLayoutSettings[] columnSettings)
    {
        if (!preset.AllowsColumnSettings)
        {
            ColumnLayoutSettings[] fixedSettings = BuildFixedColumnSettingsForPreset(preset);
            settings.ColumnSettingsByLayout ??= new Dictionary<string, List<ColumnLayoutSettings>>(StringComparer.OrdinalIgnoreCase);
            List<ColumnLayoutSettings> fixedList = new(fixedSettings.Length);
            for (int i = 0; i < fixedSettings.Length; i++)
            {
                ColumnLayoutSettings item = fixedSettings[i];
                fixedList.Add(new ColumnLayoutSettings(item.Scale, item.OffsetXPercent, item.OffsetYPercent, item.RowSpacingPercent));
            }
            settings.ColumnSettingsByLayout[preset.Name] = fixedList;
            settings.ColumnSettings = fixedList;
            return;
        }

        settings.ColumnSettingsByLayout ??= new Dictionary<string, List<ColumnLayoutSettings>>(StringComparer.OrdinalIgnoreCase);

        ColumnLayoutSettings[] cloned = CloneColumnSettings(columnSettings);
        List<ColumnLayoutSettings> asList = new(cloned.Length);
        for (int i = 0; i < cloned.Length; i++)
        {
            asList.Add(cloned[i]);
        }

        settings.ColumnSettingsByLayout[preset.Name] = asList;

        // Keep legacy field synchronized to the active layout for backward compatibility.
        settings.ColumnSettings = new List<ColumnLayoutSettings>(asList.Count);
        for (int i = 0; i < asList.Count; i++)
        {
            ColumnLayoutSettings item = asList[i];
            settings.ColumnSettings.Add(new ColumnLayoutSettings(
                scale: item.Scale,
                offsetXPercent: item.OffsetXPercent,
                offsetYPercent: item.OffsetYPercent,
                rowSpacingPercent: item.RowSpacingPercent));
        }
    }

    private static ColumnLayoutSettings[] BuildFixedColumnSettingsForPreset(TrackpadLayoutPreset preset)
    {
        ColumnLayoutSettings[] fixedSettings = ColumnLayoutDefaults.DefaultSettings(preset.Columns);
        for (int i = 0; i < fixedSettings.Length; i++)
        {
            fixedSettings[i].Scale = preset.FixedKeyScale;
            fixedSettings[i].OffsetXPercent = 0.0;
            fixedSettings[i].OffsetYPercent = 0.0;
            fixedSettings[i].RowSpacingPercent = 0.0;
        }

        return fixedSettings;
    }
}
