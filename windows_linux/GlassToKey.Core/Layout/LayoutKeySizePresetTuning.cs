using System;

namespace GlassToKey;

public static class LayoutKeySizePresetTuning
{
    public const double MxKeyWidthMm = 19.05;
    public const double MxKeyHeightMm = 19.05;

    public static bool ApplyKeySizePreset(
        TrackpadLayoutPreset preset,
        ColumnLayoutSettings[] columnSettings,
        double trackpadWidthMm,
        double baseKeyWidthMm,
        double baseKeyHeightMm,
        double targetKeyWidthMm,
        double targetKeyHeightMm,
        double keyPaddingPercent)
    {
        ArgumentNullException.ThrowIfNull(preset);
        ArgumentNullException.ThrowIfNull(columnSettings);

        if (!preset.AllowsColumnSettings || columnSettings.Length == 0)
        {
            return false;
        }

        bool changed = false;
        double targetScaleX = targetKeyWidthMm / baseKeyWidthMm;
        double targetScaleY = targetKeyHeightMm / baseKeyHeightMm;
        double spacingScale = Math.Clamp(keyPaddingPercent, 0.0, 200.0) / 100.0;
        double horizontalPaddingMm = targetKeyHeightMm * spacingScale;

        for (int column = 0; column < columnSettings.Length; column++)
        {
            ColumnLayoutSettings settings = columnSettings[column];
            if (Math.Abs(settings.ScaleX - targetScaleX) > 0.00001)
            {
                settings.ScaleX = targetScaleX;
                changed = true;
            }

            if (Math.Abs(settings.ScaleY - targetScaleY) > 0.00001)
            {
                settings.ScaleY = targetScaleY;
                changed = true;
            }

            double targetOffsetX = ComputeHorizontalPitchOffsetPercent(
                preset,
                column,
                trackpadWidthMm,
                baseKeyWidthMm,
                targetKeyWidthMm,
                horizontalPaddingMm);
            if (Math.Abs(settings.OffsetXPercent - targetOffsetX) > 0.00001)
            {
                settings.OffsetXPercent = targetOffsetX;
                changed = true;
            }
        }

        return changed;
    }

    public static double ComputeHorizontalPitchOffsetPercent(
        TrackpadLayoutPreset preset,
        int column,
        double trackpadWidthMm,
        double baseKeyWidthMm,
        double targetKeyWidthMm,
        double horizontalPaddingMm)
    {
        ArgumentNullException.ThrowIfNull(preset);

        if (column < 0 || column >= preset.ColumnAnchorsMm.Length)
        {
            return 0.0;
        }

        PointMm[] anchors = preset.ColumnAnchorsMm;
        if (anchors.Length <= 1)
        {
            return 0.0;
        }

        double scaleX = targetKeyWidthMm / baseKeyWidthMm;
        if (Math.Abs(scaleX - 1.0) < 0.00001 && Math.Abs(horizontalPaddingMm) < 0.00001)
        {
            return 0.0;
        }

        double[] targetAnchorsMm = new double[anchors.Length];
        targetAnchorsMm[0] = anchors[0].X;

        for (int index = 1; index < anchors.Length; index++)
        {
            double baseGapMm = anchors[index].X - anchors[index - 1].X;
            double desiredGapMm = (baseGapMm * scaleX) + horizontalPaddingMm;
            targetAnchorsMm[index] = targetAnchorsMm[index - 1] + desiredGapMm;
        }

        double baselineRightMm = anchors[^1].X + baseKeyWidthMm;
        double baselineCenterMm = (anchors[0].X + baselineRightMm) * 0.5;
        double adjustedRightMm = targetAnchorsMm[^1] + targetKeyWidthMm;
        double adjustedCenterMm = (targetAnchorsMm[0] + adjustedRightMm) * 0.5;
        double centerOffsetMm = baselineCenterMm - adjustedCenterMm;
        double targetAnchorMm = targetAnchorsMm[column] + centerOffsetMm;
        return ((targetAnchorMm - anchors[column].X) / trackpadWidthMm) * 100.0;
    }
}
