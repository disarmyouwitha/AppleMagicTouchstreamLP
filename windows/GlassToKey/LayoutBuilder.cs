using System;
using System.Windows;

namespace GlassToKey;

public static class LayoutBuilder
{
    public static KeyLayout BuildLayout(
        TrackpadLayoutPreset preset,
        double trackpadWidthMm,
        double trackpadHeightMm,
        double keyWidthMm,
        double keyHeightMm,
        ColumnLayoutSettings[] columnSettings,
        bool mirrored,
        double keySpacingPercent = 0.0
    )
    {
        int columns = preset.Columns;
        int rows = preset.Rows;
        if (mirrored && preset.BlankLeftSide)
        {
            return new KeyLayout(Array.Empty<NormalizedRect[]>(), Array.Empty<string[]>());
        }

        if (!mirrored && preset.UseFixedRightStaggeredQwerty)
        {
            return BuildFixedRightStaggeredQwertyLayout(
                preset,
                trackpadWidthMm,
                trackpadHeightMm,
                keyWidthMm,
                keyHeightMm,
                keySpacingPercent);
        }

        if (columns <= 0 || rows <= 0 || preset.ColumnAnchorsMm.Length != columns)
        {
            return new KeyLayout(Array.Empty<NormalizedRect[]>(), Array.Empty<string[]>());
        }

        ColumnLayoutSettings[] settings = columnSettings.Length == columns
            ? columnSettings
            : ColumnLayoutDefaults.DefaultSettings(columns);

        double[] columnScales = new double[columns];
        for (int i = 0; i < columns; i++)
        {
            columnScales[i] = settings[i].Scale;
        }

        PointMm[] adjustedAnchors = ScaledColumnAnchors(preset.ColumnAnchorsMm, columnScales);
        double spacingXmm = keyWidthMm * (Math.Clamp(keySpacingPercent, 0.0, 200.0) / 100.0);
        double spacingYmm = keyHeightMm * (Math.Clamp(keySpacingPercent, 0.0, 200.0) / 100.0);

        NormalizedRect[][] rects = new NormalizedRect[rows][];
        for (int row = 0; row < rows; row++)
        {
            rects[row] = new NormalizedRect[columns];
            for (int col = 0; col < columns; col++)
            {
                PointMm anchor = adjustedAnchors[col];
                double scale = columnScales[col];
                double widthMm = keyWidthMm * scale;
                double heightMm = keyHeightMm * scale;
                double rowSpacing = heightMm * (settings[col].RowSpacingPercent / 100.0);
                double xMm = anchor.X;
                double yMm = anchor.Y + row * (heightMm + rowSpacing + spacingYmm);

                NormalizedRect rect = new NormalizedRect(
                    X: xMm / trackpadWidthMm,
                    Y: yMm / trackpadHeightMm,
                    Width: widthMm / trackpadWidthMm,
                    Height: heightMm / trackpadHeightMm
                );
                rects[row][col] = rect;
            }
        }

        for (int col = 0; col < columns; col++)
        {
            double offsetX = settings[col].OffsetXPercent / 100.0;
            double offsetY = settings[col].OffsetYPercent / 100.0;
            for (int row = 0; row < rows; row++)
            {
                NormalizedRect rect = rects[row][col];
                rects[row][col] = rect with
                {
                    X = rect.X + offsetX,
                    Y = rect.Y + offsetY
                };
            }
        }

        if (mirrored)
        {
            for (int row = 0; row < rows; row++)
            {
                for (int col = 0; col < columns; col++)
                {
                    NormalizedRect rect = rects[row][col];
                    rects[row][col] = rect with
                    {
                        X = 1.0 - rect.X - rect.Width
                    };
                }
            }
        }

        string[][] labels = mirrored ? preset.LeftLabels : preset.RightLabels;
        return new KeyLayout(rects, labels);
    }

    private static KeyLayout BuildFixedRightStaggeredQwertyLayout(
        TrackpadLayoutPreset preset,
        double trackpadWidthMm,
        double trackpadHeightMm,
        double keyWidthMm,
        double keyHeightMm,
        double keySpacingPercent)
    {
        string[][] labels = preset.RightLabels;
        int rowCount = labels.Length;
        if (rowCount == 0)
        {
            return new KeyLayout(Array.Empty<NormalizedRect[]>(), Array.Empty<string[]>());
        }

        int maxColumns = 0;
        for (int row = 0; row < rowCount; row++)
        {
            int rowColumns = labels[row].Length;
            if (rowColumns <= 0)
            {
                return new KeyLayout(Array.Empty<NormalizedRect[]>(), Array.Empty<string[]>());
            }

            if (rowColumns > maxColumns)
            {
                maxColumns = rowColumns;
            }
        }

        if (maxColumns <= 0)
        {
            return new KeyLayout(Array.Empty<NormalizedRect[]>(), Array.Empty<string[]>());
        }

        double keyScale = preset.FixedKeyScale;
        double widthMm = keyWidthMm * keyScale;
        double heightMm = keyHeightMm * keyScale;
        double spacingXmm = widthMm * (Math.Clamp(keySpacingPercent, 0.0, 200.0) / 100.0);
        double spacingYmm = heightMm * (Math.Clamp(keySpacingPercent, 0.0, 200.0) / 100.0);

        double referenceRowWidthMm = maxColumns * widthMm + (maxColumns - 1) * spacingXmm;
        double maxOffsetMm = widthMm * 0.60;
        double baseXmm = Math.Max(0.0, (trackpadWidthMm - referenceRowWidthMm - maxOffsetMm) * 0.5);
        double[] rowOffsetsMm =
        {
            0.0,
            widthMm * 0.30,
            widthMm * 0.60,
            widthMm * 0.12
        };

        double totalHeightMm = rowCount * heightMm + (rowCount - 1) * spacingYmm;
        double baseYmm = Math.Max(0.0, (trackpadHeightMm - totalHeightMm) * 0.5);

        NormalizedRect[][] rects = new NormalizedRect[rowCount][];
        for (int row = 0; row < rowCount; row++)
        {
            int rowColumns = labels[row].Length;
            rects[row] = new NormalizedRect[rowColumns];
            double rowYmm = baseYmm + row * (heightMm + spacingYmm);

            if (row == rowCount - 1 && rowColumns == 1)
            {
                double longSpaceWidthMm = Math.Min(referenceRowWidthMm * 0.72, trackpadWidthMm * 0.78);
                double longSpaceXmm = Math.Max(0.0, (trackpadWidthMm - longSpaceWidthMm) * 0.5);
                rects[row][0] = new NormalizedRect(
                    X: longSpaceXmm / trackpadWidthMm,
                    Y: rowYmm / trackpadHeightMm,
                    Width: longSpaceWidthMm / trackpadWidthMm,
                    Height: heightMm / trackpadHeightMm);
                continue;
            }

            double rowWidthMm = rowColumns * widthMm + (rowColumns - 1) * spacingXmm;
            double rowStartXmm = baseXmm + rowOffsetsMm[Math.Min(row, rowOffsetsMm.Length - 1)];
            if (rowStartXmm + rowWidthMm > trackpadWidthMm)
            {
                rowStartXmm = Math.Max(0.0, trackpadWidthMm - rowWidthMm);
            }

            for (int col = 0; col < rowColumns; col++)
            {
                double xMm = rowStartXmm + col * (widthMm + spacingXmm);
                rects[row][col] = new NormalizedRect(
                    X: xMm / trackpadWidthMm,
                    Y: rowYmm / trackpadHeightMm,
                    Width: widthMm / trackpadWidthMm,
                    Height: heightMm / trackpadHeightMm);
            }
        }

        return new KeyLayout(rects, labels);
    }

    private static PointMm[] ScaledColumnAnchors(PointMm[] anchors, double[] columnScales)
    {
        if (anchors.Length == 0)
        {
            return anchors;
        }

        PointMm[] output = new PointMm[anchors.Length];
        double originX = anchors[0].X;
        for (int i = 0; i < anchors.Length; i++)
        {
            double scale = i < columnScales.Length ? columnScales[i] : 1.0;
            double offsetX = anchors[i].X - originX;
            output[i] = new PointMm(originX + offsetX * scale, anchors[i].Y);
        }
        return output;
    }
}
