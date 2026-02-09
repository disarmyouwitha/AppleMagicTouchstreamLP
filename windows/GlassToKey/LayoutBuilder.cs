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
                double xMm = anchor.X + (col * spacingXmm);
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
