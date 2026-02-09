using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace GlassToKey;

public sealed class UserSettings
{
    public string? LeftDevicePath { get; set; }
    public string? RightDevicePath { get; set; }
    public int ActiveLayer { get; set; }
    public string LayoutPresetName { get; set; } = "6x3";
    public bool VisualizerEnabled { get; set; } = true;
    public bool KeyboardModeEnabled { get; set; }
    public bool AllowMouseTakeover { get; set; } = true;
    public bool ChordShiftEnabled { get; set; } = true;
    public bool TypingEnabled { get; set; } = true;
    public bool RunAtStartup { get; set; }
    public bool TapClickEnabled { get; set; } = true;
    public bool TwoFingerTapEnabled { get; set; } = true;
    public bool ThreeFingerTapEnabled { get; set; } = true;
    public double HoldDurationMs { get; set; } = 220.0;
    public double DragCancelMm { get; set; } = 3.0;
    public double TypingGraceMs { get; set; } = 600.0;
    public double IntentMoveMm { get; set; } = 3.0;
    public double IntentVelocityMmPerSec { get; set; } = 30.0;
    public double SnapRadiusPercent { get; set; } = RuntimeConfigurationFactory.HardcodedSnapRadiusPercent;
    public double SnapAmbiguityRatio { get; set; } = 1.15;
    public double KeyBufferMs { get; set; } = 20.0;
    public double KeyPaddingPercent { get; set; } = 10.0;
    public double TapStaggerToleranceMs { get; set; } = 80.0;
    public double TapCadenceWindowMs { get; set; } = 200.0;
    public double TapMoveThresholdMm { get; set; } = 3.0;
    public List<ColumnLayoutSettings>? ColumnSettings { get; set; } = new()
    {
        new ColumnLayoutSettings(1.15, -6.0, -3.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -5.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -7.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -5.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -1.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -1.0, 0.0)
    };

    public static string GetSettingsPath()
    {
        string root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string dir = Path.Combine(root, "GlassToKey");
        return Path.Combine(dir, "settings.json");
    }

    public static UserSettings Load()
    {
        try
        {
            string path = GetSettingsPath();
            if (!File.Exists(path))
            {
                return new UserSettings();
            }

            string json = File.ReadAllText(path);
            UserSettings? settings = JsonSerializer.Deserialize<UserSettings>(json);
            UserSettings loaded = settings ?? new UserSettings();
            if (loaded.NormalizeRanges())
            {
                loaded.Save();
            }

            return loaded;
        }
        catch
        {
            return new UserSettings();
        }
    }

    public void Save()
    {
        try
        {
            string path = GetSettingsPath();
            string? dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(dir))
            {
                Directory.CreateDirectory(dir);
            }

            var options = new JsonSerializerOptions { WriteIndented = true };
            string json = JsonSerializer.Serialize(this, options);
            File.WriteAllText(path, json);
        }
        catch
        {
            // Best-effort persistence.
        }
    }

    public bool NormalizeRanges()
    {
        bool changed = false;

        int normalizedLayer = Math.Clamp(ActiveLayer, 0, 3);
        if (normalizedLayer != ActiveLayer)
        {
            ActiveLayer = normalizedLayer;
            changed = true;
        }

        double normalizedSnap = SnapRadiusPercent > 0.0 ? RuntimeConfigurationFactory.HardcodedSnapRadiusPercent : 0.0;
        if (Math.Abs(normalizedSnap - SnapRadiusPercent) > 0.00001)
        {
            SnapRadiusPercent = normalizedSnap;
            changed = true;
        }

        if (Math.Abs(KeyBufferMs - RuntimeConfigurationFactory.HardcodedKeyBufferMs) > 0.00001)
        {
            KeyBufferMs = RuntimeConfigurationFactory.HardcodedKeyBufferMs;
            changed = true;
        }

        if (TwoFingerTapEnabled != TapClickEnabled)
        {
            TwoFingerTapEnabled = TapClickEnabled;
            changed = true;
        }

        if (ThreeFingerTapEnabled != TapClickEnabled)
        {
            ThreeFingerTapEnabled = TapClickEnabled;
            changed = true;
        }

        return changed;
    }
}
