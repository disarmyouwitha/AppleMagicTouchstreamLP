using System;

namespace GlassToKey;

public sealed class ColumnLayoutSettings
{
    public double Scale { get; set; } = 1.0;
    public double OffsetXPercent { get; set; }
    public double OffsetYPercent { get; set; }
    public double RowSpacingPercent { get; set; }

    public ColumnLayoutSettings() { }

    public ColumnLayoutSettings(double scale, double offsetXPercent, double offsetYPercent, double rowSpacingPercent)
    {
        Scale = scale;
        OffsetXPercent = offsetXPercent;
        OffsetYPercent = offsetYPercent;
        RowSpacingPercent = rowSpacingPercent;
    }
}

public static class ColumnLayoutDefaults
{
    public static ColumnLayoutSettings[] DefaultSettings(int columns)
    {
        ColumnLayoutSettings[] settings = new ColumnLayoutSettings[columns];
        for (int i = 0; i < columns; i++)
        {
            settings[i] = new ColumnLayoutSettings(1.0, 0.0, 0.0, 0.0);
        }
        return settings;
    }
}
