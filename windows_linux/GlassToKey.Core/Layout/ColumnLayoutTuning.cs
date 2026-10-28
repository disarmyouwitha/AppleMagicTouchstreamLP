using System;
using System.Collections.Generic;

namespace GlassToKey;

public readonly record struct ColumnAutoSplayTouch(double XNorm, double YNorm);

public static class ColumnLayoutTuning
{
    public const int AutoSplayTouchCount = 4;

    public static bool IsAutoSplaySupported(TrackpadLayoutPreset preset)
    {
        ArgumentNullException.ThrowIfNull(preset);

        if (preset.Columns == 6)
        {
            return true;
        }

        return IsFiveColumnAutoSplayPreset(preset);
    }

    public static bool TryApplyAutoSplay(
        TrackpadLayoutPreset preset,
        KeyLayout rightLayout,
        ColumnLayoutSettings[] columnSettings,
        IReadOnlyList<ColumnAutoSplayTouch> touches,
        out string error)
    {
        ArgumentNullException.ThrowIfNull(preset);
        ArgumentNullException.ThrowIfNull(rightLayout);
        ArgumentNullException.ThrowIfNull(columnSettings);
        ArgumentNullException.ThrowIfNull(touches);

        if (touches.Count != AutoSplayTouchCount)
        {
            error = $"Auto Splay requires {AutoSplayTouchCount} touches.";
            return false;
        }

        int row = ResolveAutoSplayReferenceRow(preset);
        if (rightLayout.Rects.Length <= row || rightLayout.Rects[row].Length < preset.Columns)
        {
            error = "Auto Splay could not resolve a valid reference row.";
            return false;
        }

        if (preset.Columns == 6 && columnSettings.Length >= 6)
        {
            double leftEdgeOffsetX = columnSettings[0].OffsetXPercent - columnSettings[1].OffsetXPercent;
            double rightEdgeOffsetX = columnSettings[5].OffsetXPercent - columnSettings[4].OffsetXPercent;

            for (int i = 0; i < AutoSplayTouchCount; i++)
            {
                int col = i + 1;
                NormalizedRect reference = rightLayout.Rects[row][col];
                double currentX = reference.X + (reference.Width * 0.5);
                double currentY = reference.Y + (reference.Height * 0.5);
                ColumnAutoSplayTouch target = touches[i];

                columnSettings[col].OffsetXPercent += (target.XNorm - currentX) * 100.0;
                columnSettings[col].OffsetYPercent += (target.YNorm - currentY) * 100.0;
            }

            columnSettings[0].OffsetXPercent = columnSettings[1].OffsetXPercent + leftEdgeOffsetX;
            columnSettings[0].OffsetYPercent = columnSettings[1].OffsetYPercent;
            columnSettings[5].OffsetXPercent = columnSettings[4].OffsetXPercent + rightEdgeOffsetX;
            columnSettings[5].OffsetYPercent = columnSettings[4].OffsetYPercent;

            error = string.Empty;
            return true;
        }

        if (IsFiveColumnAutoSplayPreset(preset) && columnSettings.Length >= 5)
        {
            for (int i = 0; i < AutoSplayTouchCount; i++)
            {
                int col = i;
                NormalizedRect reference = rightLayout.Rects[row][col];
                double currentX = reference.X + (reference.Width * 0.5);
                double currentY = reference.Y + (reference.Height * 0.5);
                ColumnAutoSplayTouch target = touches[i];

                columnSettings[col].OffsetXPercent += (target.XNorm - currentX) * 100.0;
                columnSettings[col].OffsetYPercent += (target.YNorm - currentY) * 100.0;
            }

            columnSettings[4].OffsetXPercent = columnSettings[3].OffsetXPercent;
            columnSettings[4].OffsetYPercent = columnSettings[3].OffsetYPercent;

            error = string.Empty;
            return true;
        }

        error = "Auto Splay could not apply to this layout configuration.";
        return false;
    }

    public static bool TryApplyEvenColumnSpacing(
        TrackpadLayoutPreset preset,
        KeyLayout rightLayout,
        ColumnLayoutSettings[] columnSettings,
        out string error)
    {
        ArgumentNullException.ThrowIfNull(preset);
        ArgumentNullException.ThrowIfNull(rightLayout);
        ArgumentNullException.ThrowIfNull(columnSettings);

        if (!preset.AllowsColumnSettings || preset.Columns < 3 || columnSettings.Length < preset.Columns)
        {
            error = "Even spacing requires a layout with at least 3 editable columns.";
            return false;
        }

        int row = ResolveAutoSplayReferenceRow(preset);
        if (rightLayout.Rects.Length <= row || rightLayout.Rects[row].Length < preset.Columns)
        {
            error = "Even spacing could not resolve a valid reference row.";
            return false;
        }

        int last = preset.Columns - 1;
        NormalizedRect firstRect = rightLayout.Rects[row][0];
        NormalizedRect lastRect = rightLayout.Rects[row][last];
        double firstCenter = firstRect.X + (firstRect.Width * 0.5);
        double lastCenter = lastRect.X + (lastRect.Width * 0.5);
        double step = (lastCenter - firstCenter) / last;

        for (int col = 1; col < last; col++)
        {
            NormalizedRect currentRect = rightLayout.Rects[row][col];
            double currentCenter = currentRect.X + (currentRect.Width * 0.5);
            double targetCenter = firstCenter + (step * col);
            columnSettings[col].OffsetXPercent += (targetCenter - currentCenter) * 100.0;
        }

        error = string.Empty;
        return true;
    }

    public static int ResolveAutoSplayReferenceRow(TrackpadLayoutPreset preset)
    {
        ArgumentNullException.ThrowIfNull(preset);

        if (preset.Rows <= 0)
        {
            return 0;
        }

        if (IsFiveColumnAutoSplayPreset(preset))
        {
            return Math.Clamp(preset.Rows - 2, 0, preset.Rows - 1);
        }

        if (string.Equals(preset.Name, TrackpadLayoutPreset.SixByFour.Name, StringComparison.OrdinalIgnoreCase))
        {
            return Math.Clamp(preset.Rows - 2, 0, preset.Rows - 1);
        }

        return Math.Clamp((preset.Rows - 1) / 2, 0, preset.Rows - 1);
    }

    private static bool IsFiveColumnAutoSplayPreset(TrackpadLayoutPreset preset)
    {
        return preset.Columns == 5 &&
               (string.Equals(preset.Name, TrackpadLayoutPreset.FiveByThree.Name, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(preset.Name, TrackpadLayoutPreset.FiveByFour.Name, StringComparison.OrdinalIgnoreCase));
    }
}
