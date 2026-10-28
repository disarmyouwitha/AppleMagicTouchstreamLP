using System;
using System.Text.Json.Serialization;

namespace GlassToKey;

public sealed class ColumnLayoutSettings
{
    private double _scaleX = 1.0;
    private double _scaleY = 1.0;
    private bool _scaleXExplicit;
    private bool _scaleYExplicit;

    public double ScaleX
    {
        get => _scaleX;
        set
        {
            _scaleX = value;
            _scaleXExplicit = true;
        }
    }

    public double ScaleY
    {
        get => _scaleY;
        set
        {
            _scaleY = value;
            _scaleYExplicit = true;
        }
    }

    // Legacy single-axis alias kept for settings compatibility.
    [JsonPropertyOrder(100)]
    public double Scale
    {
        get => Math.Abs(_scaleX - _scaleY) < 0.0001 ? _scaleX : (_scaleX + _scaleY) * 0.5;
        set
        {
            if (!_scaleXExplicit)
            {
                _scaleX = value;
            }

            if (!_scaleYExplicit)
            {
                _scaleY = value;
            }
        }
    }

    public double OffsetXPercent { get; set; }
    public double OffsetYPercent { get; set; }
    public double RowSpacingPercent { get; set; }
    public double RotationDegrees { get; set; }

    public ColumnLayoutSettings() { }

    public ColumnLayoutSettings(double scale, double offsetXPercent, double offsetYPercent, double rowSpacingPercent, double rotationDegrees = 0.0)
        : this(scale, scale, offsetXPercent, offsetYPercent, rowSpacingPercent, rotationDegrees)
    {
    }

    public ColumnLayoutSettings(double scaleX, double scaleY, double offsetXPercent, double offsetYPercent, double rowSpacingPercent, double rotationDegrees = 0.0)
    {
        ScaleX = scaleX;
        ScaleY = scaleY;
        OffsetXPercent = offsetXPercent;
        OffsetYPercent = offsetYPercent;
        RowSpacingPercent = rowSpacingPercent;
        RotationDegrees = rotationDegrees;
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
