using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace GlassToKey;

public sealed class UserSettings
{
    public string? LeftDevicePath { get; set; }
    public string? RightDevicePath { get; set; }
    public int ActiveLayer { get; set; }
    public string LayoutPresetName { get; set; } = "6x3";
    public Dictionary<string, string>? DecoderProfilesByDevicePath { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public bool VisualizerEnabled { get; set; } = true;
    public bool KeyboardModeEnabled { get; set; }
    public bool AllowMouseTakeover { get; set; } = true;
    public bool ChordShiftEnabled { get; set; } = true;
    public bool TypingEnabled { get; set; } = true;
    public bool RunAtStartup { get; set; }
    public string FiveFingerSwipeLeftAction { get; set; } = "Typing Toggle";
    public string FiveFingerSwipeRightAction { get; set; } = "Typing Toggle";
    public string FiveFingerSwipeUpAction { get; set; } = "None";
    public string FiveFingerSwipeDownAction { get; set; } = "None";
    public string ThreeFingerSwipeLeftAction { get; set; } = "None";
    public string ThreeFingerSwipeRightAction { get; set; } = "None";
    public string ThreeFingerSwipeUpAction { get; set; } = "None";
    public string ThreeFingerSwipeDownAction { get; set; } = "None";
    public string FourFingerSwipeLeftAction { get; set; } = "None";
    public string FourFingerSwipeRightAction { get; set; } = "None";
    public string FourFingerSwipeUpAction { get; set; } = "None";
    public string FourFingerSwipeDownAction { get; set; } = "None";
    public string TwoFingerHoldAction { get; set; } = "None";
    public string ThreeFingerHoldAction { get; set; } = "None";
    public string FourFingerHoldAction { get; set; } = "Chordal Shift";
    public string OuterCornersAction { get; set; } = "None";
    public string InnerCornersAction { get; set; } = "None";
    public string TopLeftTriangleAction { get; set; } = "None";
    public string TopRightTriangleAction { get; set; } = "None";
    public string BottomLeftTriangleAction { get; set; } = "None";
    public string BottomRightTriangleAction { get; set; } = "None";
    public string ForceClick1Action { get; set; } = "None";
    public string ForceClick2Action { get; set; } = "None";
    public string ForceClick3Action { get; set; } = "None";
    public string UpperLeftCornerClickAction { get; set; } = "None";
    public string UpperRightCornerClickAction { get; set; } = "None";
    public string LowerLeftCornerClickAction { get; set; } = "None";
    public string LowerRightCornerClickAction { get; set; } = "None";
    public bool HapticsEnabled { get; set; } = true;
    public uint HapticsStrength { get; set; } = 0x00026C00u | 0x15u;
    public int HapticsMinIntervalMs { get; set; } = 20;
    public double HoldDurationMs { get; set; } = 220.0;
    public double DragCancelMm { get; set; } = 3.0;
    public double TypingGraceMs { get; set; } = 600.0;
    public double IntentMoveMm { get; set; } = 3.0;
    public double IntentVelocityMmPerSec { get; set; } = 30.0;
    public double SnapRadiusPercent { get; set; } = RuntimeConfigurationFactory.HardcodedSnapRadiusPercent;
    public double SnapAmbiguityRatio { get; set; } = 1.15;
    public double KeyBufferMs { get; set; } = 20.0;
    public double KeyPaddingPercent { get; set; } = 10.0;
    public Dictionary<string, double>? KeyPaddingPercentByLayout { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public int ForceMin { get; set; }
    public int ForceCap { get; set; } = 255;
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public Dictionary<string, Dictionary<int, List<ColumnLayoutSettings>>>? ColumnSettingsByLayoutLayer { get; set; }
    public Dictionary<string, List<ColumnLayoutSettings>>? ColumnSettingsByLayout { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public List<ColumnLayoutSettings>? ColumnSettings { get; set; } = new()
    {
        new ColumnLayoutSettings(1.15, -6.0, -3.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -5.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -7.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -5.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -1.0, 0.0),
        new ColumnLayoutSettings(1.15, -6.0, -1.0, 0.0)
    };

    public UserSettings Clone()
    {
        UserSettings clone = new();
        clone.CopyFrom(this);
        return clone;
    }

    public void CopyFrom(UserSettings source)
    {
        if (source == null)
        {
            throw new ArgumentNullException(nameof(source));
        }

        LeftDevicePath = source.LeftDevicePath;
        RightDevicePath = source.RightDevicePath;
        ActiveLayer = source.ActiveLayer;
        LayoutPresetName = source.LayoutPresetName;
        DecoderProfilesByDevicePath = CloneDecoderProfiles(source.DecoderProfilesByDevicePath);
        VisualizerEnabled = source.VisualizerEnabled;
        KeyboardModeEnabled = source.KeyboardModeEnabled;
        AllowMouseTakeover = source.AllowMouseTakeover;
        ChordShiftEnabled = source.ChordShiftEnabled;
        TypingEnabled = source.TypingEnabled;
        RunAtStartup = source.RunAtStartup;
        FiveFingerSwipeLeftAction = source.FiveFingerSwipeLeftAction;
        FiveFingerSwipeRightAction = source.FiveFingerSwipeRightAction;
        FiveFingerSwipeUpAction = source.FiveFingerSwipeUpAction;
        FiveFingerSwipeDownAction = source.FiveFingerSwipeDownAction;
        ThreeFingerSwipeLeftAction = source.ThreeFingerSwipeLeftAction;
        ThreeFingerSwipeRightAction = source.ThreeFingerSwipeRightAction;
        ThreeFingerSwipeUpAction = source.ThreeFingerSwipeUpAction;
        ThreeFingerSwipeDownAction = source.ThreeFingerSwipeDownAction;
        FourFingerSwipeLeftAction = source.FourFingerSwipeLeftAction;
        FourFingerSwipeRightAction = source.FourFingerSwipeRightAction;
        FourFingerSwipeUpAction = source.FourFingerSwipeUpAction;
        FourFingerSwipeDownAction = source.FourFingerSwipeDownAction;
        TwoFingerHoldAction = source.TwoFingerHoldAction;
        ThreeFingerHoldAction = source.ThreeFingerHoldAction;
        FourFingerHoldAction = source.FourFingerHoldAction;
        OuterCornersAction = source.OuterCornersAction;
        InnerCornersAction = source.InnerCornersAction;
        TopLeftTriangleAction = source.TopLeftTriangleAction;
        TopRightTriangleAction = source.TopRightTriangleAction;
        BottomLeftTriangleAction = source.BottomLeftTriangleAction;
        BottomRightTriangleAction = source.BottomRightTriangleAction;
        ForceClick1Action = source.ForceClick1Action;
        ForceClick2Action = source.ForceClick2Action;
        ForceClick3Action = source.ForceClick3Action;
        UpperLeftCornerClickAction = source.UpperLeftCornerClickAction;
        UpperRightCornerClickAction = source.UpperRightCornerClickAction;
        LowerLeftCornerClickAction = source.LowerLeftCornerClickAction;
        LowerRightCornerClickAction = source.LowerRightCornerClickAction;
        HapticsEnabled = source.HapticsEnabled;
        HapticsStrength = source.HapticsStrength;
        HapticsMinIntervalMs = source.HapticsMinIntervalMs;
        HoldDurationMs = source.HoldDurationMs;
        DragCancelMm = source.DragCancelMm;
        TypingGraceMs = source.TypingGraceMs;
        IntentMoveMm = source.IntentMoveMm;
        IntentVelocityMmPerSec = source.IntentVelocityMmPerSec;
        SnapRadiusPercent = source.SnapRadiusPercent;
        SnapAmbiguityRatio = source.SnapAmbiguityRatio;
        KeyBufferMs = source.KeyBufferMs;
        KeyPaddingPercent = source.KeyPaddingPercent;
        KeyPaddingPercentByLayout = CloneKeyPaddingByLayout(source.KeyPaddingPercentByLayout);
        ForceMin = source.ForceMin;
        ForceCap = source.ForceCap;
        ColumnSettingsByLayoutLayer = source.ColumnSettingsByLayoutLayer == null
            ? null
            : CloneColumnSettingsByLayoutLayer(source.ColumnSettingsByLayoutLayer);
        ColumnSettingsByLayout = CloneColumnSettingsByLayout(source.ColumnSettingsByLayout);
        ColumnSettings = CloneColumnSettingsList(source.ColumnSettings);
    }

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
                if (TryLoadBundledDefaults(out UserSettings bundledDefaults))
                {
                    return bundledDefaults;
                }

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
            if (TryLoadBundledDefaults(out UserSettings bundledDefaults))
            {
                return bundledDefaults;
            }

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

        if (string.IsNullOrWhiteSpace(LayoutPresetName))
        {
            LayoutPresetName = "6x3";
            changed = true;
        }
        else
        {
            string trimmedLayoutName = LayoutPresetName.Trim();
            if (!string.Equals(LayoutPresetName, trimmedLayoutName, StringComparison.Ordinal))
            {
                LayoutPresetName = trimmedLayoutName;
                changed = true;
            }
        }

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

        double normalizedPadding = Math.Clamp(KeyPaddingPercent, 0.0, 90.0);
        if (Math.Abs(normalizedPadding - KeyPaddingPercent) > 0.00001)
        {
            KeyPaddingPercent = normalizedPadding;
            changed = true;
        }

        changed |= NormalizeGestureAction(FiveFingerSwipeLeftAction, "Typing Toggle", out string fiveFingerSwipeLeftAction);
        FiveFingerSwipeLeftAction = fiveFingerSwipeLeftAction;
        changed |= NormalizeGestureAction(FiveFingerSwipeRightAction, "Typing Toggle", out string fiveFingerSwipeRightAction);
        FiveFingerSwipeRightAction = fiveFingerSwipeRightAction;
        changed |= NormalizeGestureAction(FiveFingerSwipeUpAction, "None", out string fiveFingerSwipeUpAction);
        FiveFingerSwipeUpAction = fiveFingerSwipeUpAction;
        changed |= NormalizeGestureAction(FiveFingerSwipeDownAction, "None", out string fiveFingerSwipeDownAction);
        FiveFingerSwipeDownAction = fiveFingerSwipeDownAction;
        changed |= NormalizeGestureAction(ThreeFingerSwipeLeftAction, "None", out string threeFingerSwipeLeftAction);
        ThreeFingerSwipeLeftAction = threeFingerSwipeLeftAction;
        changed |= NormalizeGestureAction(ThreeFingerSwipeRightAction, "None", out string threeFingerSwipeRightAction);
        ThreeFingerSwipeRightAction = threeFingerSwipeRightAction;
        changed |= NormalizeGestureAction(ThreeFingerSwipeUpAction, "None", out string threeFingerSwipeUpAction);
        ThreeFingerSwipeUpAction = threeFingerSwipeUpAction;
        changed |= NormalizeGestureAction(ThreeFingerSwipeDownAction, "None", out string threeFingerSwipeDownAction);
        ThreeFingerSwipeDownAction = threeFingerSwipeDownAction;
        changed |= NormalizeGestureAction(FourFingerSwipeLeftAction, "None", out string fourFingerSwipeLeftAction);
        FourFingerSwipeLeftAction = fourFingerSwipeLeftAction;
        changed |= NormalizeGestureAction(FourFingerSwipeRightAction, "None", out string fourFingerSwipeRightAction);
        FourFingerSwipeRightAction = fourFingerSwipeRightAction;
        changed |= NormalizeGestureAction(FourFingerSwipeUpAction, "None", out string fourFingerSwipeUpAction);
        FourFingerSwipeUpAction = fourFingerSwipeUpAction;
        changed |= NormalizeGestureAction(FourFingerSwipeDownAction, "None", out string fourFingerSwipeDownAction);
        FourFingerSwipeDownAction = fourFingerSwipeDownAction;
        changed |= NormalizeGestureAction(TwoFingerHoldAction, "None", out string twoFingerHoldAction);
        TwoFingerHoldAction = twoFingerHoldAction;
        changed |= NormalizeGestureAction(ThreeFingerHoldAction, "None", out string threeFingerHoldAction);
        ThreeFingerHoldAction = threeFingerHoldAction;
        changed |= NormalizeGestureAction(FourFingerHoldAction, "Chordal Shift", out string fourFingerHoldAction);
        FourFingerHoldAction = fourFingerHoldAction;
        changed |= NormalizeGestureAction(OuterCornersAction, "None", out string outerCornersAction);
        OuterCornersAction = outerCornersAction;
        changed |= NormalizeGestureAction(InnerCornersAction, "None", out string innerCornersAction);
        InnerCornersAction = innerCornersAction;
        changed |= NormalizeGestureAction(TopLeftTriangleAction, "None", out string topLeftTriangleAction);
        TopLeftTriangleAction = topLeftTriangleAction;
        changed |= NormalizeGestureAction(TopRightTriangleAction, "None", out string topRightTriangleAction);
        TopRightTriangleAction = topRightTriangleAction;
        changed |= NormalizeGestureAction(BottomLeftTriangleAction, "None", out string bottomLeftTriangleAction);
        BottomLeftTriangleAction = bottomLeftTriangleAction;
        changed |= NormalizeGestureAction(BottomRightTriangleAction, "None", out string bottomRightTriangleAction);
        BottomRightTriangleAction = bottomRightTriangleAction;
        changed |= NormalizeGestureAction(ForceClick1Action, "None", out string forceClick1Action);
        ForceClick1Action = forceClick1Action;
        changed |= NormalizeGestureAction(ForceClick2Action, "None", out string forceClick2Action);
        ForceClick2Action = forceClick2Action;
        changed |= NormalizeGestureAction(ForceClick3Action, "None", out string forceClick3Action);
        ForceClick3Action = forceClick3Action;
        changed |= NormalizeGestureAction(UpperLeftCornerClickAction, "None", out string upperLeftCornerClickAction);
        UpperLeftCornerClickAction = upperLeftCornerClickAction;
        changed |= NormalizeGestureAction(UpperRightCornerClickAction, "None", out string upperRightCornerClickAction);
        UpperRightCornerClickAction = upperRightCornerClickAction;
        changed |= NormalizeGestureAction(LowerLeftCornerClickAction, "None", out string lowerLeftCornerClickAction);
        LowerLeftCornerClickAction = lowerLeftCornerClickAction;
        changed |= NormalizeGestureAction(LowerRightCornerClickAction, "None", out string lowerRightCornerClickAction);
        LowerRightCornerClickAction = lowerRightCornerClickAction;

        bool chordShiftEnabled = IsChordShiftGestureAction(FourFingerHoldAction);
        if (ChordShiftEnabled != chordShiftEnabled)
        {
            ChordShiftEnabled = chordShiftEnabled;
            changed = true;
        }

        int normalizedHapticsInterval = Math.Clamp(HapticsMinIntervalMs, 0, 500);
        if (normalizedHapticsInterval != HapticsMinIntervalMs)
        {
            HapticsMinIntervalMs = normalizedHapticsInterval;
            changed = true;
        }

        int normalizedForceMin = Math.Clamp(ForceMin, 0, 255);
        if (normalizedForceMin != ForceMin)
        {
            ForceMin = normalizedForceMin;
            changed = true;
        }

        int normalizedForceCap = Math.Clamp(ForceCap, 0, 255);
        if (normalizedForceCap != ForceCap)
        {
            ForceCap = normalizedForceCap;
            changed = true;
        }

        if (DecoderProfilesByDevicePath != null && DecoderProfilesByDevicePath.Count > 0)
        {
            Dictionary<string, string> normalized = new(StringComparer.OrdinalIgnoreCase);
            foreach ((string key, string value) in DecoderProfilesByDevicePath)
            {
                if (string.IsNullOrWhiteSpace(key))
                {
                    changed = true;
                    continue;
                }

                if (!TrackpadDecoderProfileMap.TryParse(value, out TrackpadDecoderProfile profile))
                {
                    changed = true;
                    continue;
                }

                string canonical = profile switch
                {
                    TrackpadDecoderProfile.Legacy => "legacy",
                    _ => "official"
                };

                if (!string.Equals(value, canonical, StringComparison.Ordinal))
                {
                    changed = true;
                }

                normalized[key] = canonical;
            }

            if (normalized.Count != DecoderProfilesByDevicePath.Count)
            {
                changed = true;
            }

            DecoderProfilesByDevicePath = normalized;
        }

        Dictionary<string, double> normalizedKeyPaddingByLayout = new(StringComparer.OrdinalIgnoreCase);
        if (KeyPaddingPercentByLayout != null)
        {
            foreach ((string key, double value) in KeyPaddingPercentByLayout)
            {
                if (string.IsNullOrWhiteSpace(key))
                {
                    changed = true;
                    continue;
                }

                string trimmedKey = key.Trim();
                if (!string.Equals(trimmedKey, key, StringComparison.Ordinal))
                {
                    changed = true;
                }

                double clamped = Math.Clamp(value, 0.0, 90.0);
                if (Math.Abs(clamped - value) > 0.00001)
                {
                    changed = true;
                }

                normalizedKeyPaddingByLayout[trimmedKey] = clamped;
            }
        }

        if (!normalizedKeyPaddingByLayout.ContainsKey(LayoutPresetName))
        {
            normalizedKeyPaddingByLayout[LayoutPresetName] = Math.Clamp(KeyPaddingPercent, 0.0, 90.0);
            changed = true;
        }

        if (!AreKeyPaddingMapsEquivalent(KeyPaddingPercentByLayout, normalizedKeyPaddingByLayout))
        {
            KeyPaddingPercentByLayout = normalizedKeyPaddingByLayout;
            changed = true;
        }
        else if (KeyPaddingPercentByLayout == null)
        {
            KeyPaddingPercentByLayout = normalizedKeyPaddingByLayout;
        }

        if (normalizedKeyPaddingByLayout.TryGetValue(LayoutPresetName, out double activePadding) &&
            Math.Abs(KeyPaddingPercent - activePadding) > 0.00001)
        {
            KeyPaddingPercent = activePadding;
            changed = true;
        }

        Dictionary<string, List<ColumnLayoutSettings>> normalizedByLayout = new(StringComparer.OrdinalIgnoreCase);
        if (ColumnSettingsByLayout != null)
        {
            foreach ((string key, List<ColumnLayoutSettings> value) in ColumnSettingsByLayout)
            {
                if (string.IsNullOrWhiteSpace(key))
                {
                    changed = true;
                    continue;
                }

                string trimmedKey = key.Trim();
                if (!string.Equals(trimmedKey, key, StringComparison.Ordinal))
                {
                    changed = true;
                }

                normalizedByLayout[trimmedKey] = NormalizeColumnSettingsList(value);
            }
        }

        // Compatibility migration from older experimental layout+layer storage.
        if (ColumnSettingsByLayoutLayer != null)
        {
            foreach ((string key, Dictionary<int, List<ColumnLayoutSettings>> layers) in ColumnSettingsByLayoutLayer)
            {
                if (string.IsNullOrWhiteSpace(key))
                {
                    changed = true;
                    continue;
                }

                string trimmedKey = key.Trim();
                if (normalizedByLayout.ContainsKey(trimmedKey))
                {
                    continue;
                }

                if (layers != null && layers.TryGetValue(0, out List<ColumnLayoutSettings>? layerZero))
                {
                    normalizedByLayout[trimmedKey] = NormalizeColumnSettingsList(layerZero);
                    changed = true;
                    continue;
                }

                if (layers != null)
                {
                    foreach ((int _, List<ColumnLayoutSettings> value) in layers)
                    {
                        normalizedByLayout[trimmedKey] = NormalizeColumnSettingsList(value);
                        changed = true;
                        break;
                    }
                }
            }
        }

        if (ColumnSettings != null &&
            ColumnSettings.Count > 0 &&
            !normalizedByLayout.ContainsKey(LayoutPresetName))
        {
            normalizedByLayout[LayoutPresetName] = NormalizeColumnSettingsList(ColumnSettings);
            changed = true;
        }

        if (!AreColumnSettingsMapsEquivalent(ColumnSettingsByLayout, normalizedByLayout))
        {
            ColumnSettingsByLayout = normalizedByLayout;
            changed = true;
        }
        else if (ColumnSettingsByLayout == null)
        {
            ColumnSettingsByLayout = normalizedByLayout;
        }

        if (ColumnSettingsByLayoutLayer != null)
        {
            ColumnSettingsByLayoutLayer = null;
            changed = true;
        }

        List<ColumnLayoutSettings> activeColumnSettings =
            normalizedByLayout.TryGetValue(LayoutPresetName, out List<ColumnLayoutSettings>? byLayout)
                ? CloneColumnSettingsList(byLayout)
                : NormalizeColumnSettingsList(ColumnSettings);

        if (activeColumnSettings.Count == 0)
        {
            activeColumnSettings = new List<ColumnLayoutSettings>();
        }

        if (!AreColumnSettingsListsEquivalent(ColumnSettings, activeColumnSettings))
        {
            ColumnSettings = activeColumnSettings;
            changed = true;
        }

        return changed;
    }

    private static Dictionary<string, string> CloneDecoderProfiles(Dictionary<string, string>? source)
    {
        Dictionary<string, string> clone = new(StringComparer.OrdinalIgnoreCase);
        if (source == null)
        {
            return clone;
        }

        foreach ((string key, string value) in source)
        {
            if (string.IsNullOrWhiteSpace(key) || string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            clone[key] = value;
        }

        return clone;
    }

    private static Dictionary<string, double> CloneKeyPaddingByLayout(Dictionary<string, double>? source)
    {
        Dictionary<string, double> clone = new(StringComparer.OrdinalIgnoreCase);
        if (source == null)
        {
            return clone;
        }

        foreach ((string key, double value) in source)
        {
            if (string.IsNullOrWhiteSpace(key))
            {
                continue;
            }

            clone[key] = Math.Clamp(value, 0.0, 90.0);
        }

        return clone;
    }

    private static Dictionary<string, Dictionary<int, List<ColumnLayoutSettings>>> CloneColumnSettingsByLayoutLayer(
        Dictionary<string, Dictionary<int, List<ColumnLayoutSettings>>>? source)
    {
        Dictionary<string, Dictionary<int, List<ColumnLayoutSettings>>> clone = new(StringComparer.OrdinalIgnoreCase);
        if (source == null)
        {
            return clone;
        }

        foreach ((string key, Dictionary<int, List<ColumnLayoutSettings>> value) in source)
        {
            if (string.IsNullOrWhiteSpace(key))
            {
                continue;
            }

            clone[key] = NormalizeColumnSettingsByLayer(value);
        }

        return clone;
    }

    private static Dictionary<string, List<ColumnLayoutSettings>> CloneColumnSettingsByLayout(
        Dictionary<string, List<ColumnLayoutSettings>>? source)
    {
        Dictionary<string, List<ColumnLayoutSettings>> clone = new(StringComparer.OrdinalIgnoreCase);
        if (source == null)
        {
            return clone;
        }

        foreach ((string key, List<ColumnLayoutSettings> value) in source)
        {
            if (string.IsNullOrWhiteSpace(key))
            {
                continue;
            }

            clone[key] = CloneColumnSettingsList(value);
        }

        return clone;
    }

    private static Dictionary<int, List<ColumnLayoutSettings>> NormalizeColumnSettingsByLayer(
        Dictionary<int, List<ColumnLayoutSettings>>? source)
    {
        Dictionary<int, List<ColumnLayoutSettings>> normalized = new();
        if (source == null)
        {
            return normalized;
        }

        foreach ((int layer, List<ColumnLayoutSettings> value) in source)
        {
            int clampedLayer = Math.Clamp(layer, 0, 7);
            normalized[clampedLayer] = NormalizeColumnSettingsList(value);
        }

        return normalized;
    }

    private static List<ColumnLayoutSettings> CloneColumnSettingsList(IEnumerable<ColumnLayoutSettings>? source)
    {
        List<ColumnLayoutSettings> clone = new();
        if (source == null)
        {
            return clone;
        }

        foreach (ColumnLayoutSettings item in source)
        {
            ColumnLayoutSettings safe = item ?? new ColumnLayoutSettings();
            clone.Add(new ColumnLayoutSettings(
                scale: safe.Scale,
                offsetXPercent: safe.OffsetXPercent,
                offsetYPercent: safe.OffsetYPercent,
                rowSpacingPercent: safe.RowSpacingPercent));
        }

        return clone;
    }

    private static List<ColumnLayoutSettings> NormalizeColumnSettingsList(IEnumerable<ColumnLayoutSettings>? source)
    {
        List<ColumnLayoutSettings> normalized = new();
        if (source == null)
        {
            return normalized;
        }

        foreach (ColumnLayoutSettings item in source)
        {
            ColumnLayoutSettings safe = item ?? new ColumnLayoutSettings();
            normalized.Add(new ColumnLayoutSettings(
                scale: Math.Clamp(safe.Scale, 0.25, 3.0),
                offsetXPercent: safe.OffsetXPercent,
                offsetYPercent: safe.OffsetYPercent,
                rowSpacingPercent: safe.RowSpacingPercent));
        }

        return normalized;
    }

    private static bool AreColumnSettingsMapsEquivalent(
        Dictionary<string, List<ColumnLayoutSettings>>? existing,
        Dictionary<string, List<ColumnLayoutSettings>> normalized)
    {
        Dictionary<string, List<ColumnLayoutSettings>> comparable = new(StringComparer.OrdinalIgnoreCase);
        if (existing != null)
        {
            foreach ((string key, List<ColumnLayoutSettings> value) in existing)
            {
                if (string.IsNullOrWhiteSpace(key))
                {
                    continue;
                }

                comparable[key] = NormalizeColumnSettingsList(value);
            }
        }

        if (comparable.Count != normalized.Count)
        {
            return false;
        }

        foreach ((string key, List<ColumnLayoutSettings> value) in normalized)
        {
            if (!comparable.TryGetValue(key, out List<ColumnLayoutSettings>? compareValue))
            {
                return false;
            }

            if (!AreColumnSettingsListsEquivalent(compareValue, value))
            {
                return false;
            }
        }

        return true;
    }

    private static bool AreKeyPaddingMapsEquivalent(
        Dictionary<string, double>? existing,
        Dictionary<string, double> normalized)
    {
        Dictionary<string, double> comparable = new(StringComparer.OrdinalIgnoreCase);
        if (existing != null)
        {
            foreach ((string key, double value) in existing)
            {
                if (string.IsNullOrWhiteSpace(key))
                {
                    continue;
                }

                comparable[key] = Math.Clamp(value, 0.0, 90.0);
            }
        }

        if (comparable.Count != normalized.Count)
        {
            return false;
        }

        foreach ((string key, double value) in normalized)
        {
            if (!comparable.TryGetValue(key, out double compareValue))
            {
                return false;
            }

            if (Math.Abs(compareValue - value) > 0.000001)
            {
                return false;
            }
        }

        return true;
    }

    private static bool AreColumnSettingsListsEquivalent(
        List<ColumnLayoutSettings>? left,
        List<ColumnLayoutSettings>? right)
    {
        if (left == null && right == null)
        {
            return true;
        }

        if (left == null || right == null)
        {
            return false;
        }

        if (left.Count != right.Count)
        {
            return false;
        }

        for (int i = 0; i < left.Count; i++)
        {
            ColumnLayoutSettings lhs = left[i] ?? new ColumnLayoutSettings();
            ColumnLayoutSettings rhs = right[i] ?? new ColumnLayoutSettings();
            if (Math.Abs(lhs.Scale - rhs.Scale) > 0.000001 ||
                Math.Abs(lhs.OffsetXPercent - rhs.OffsetXPercent) > 0.000001 ||
                Math.Abs(lhs.OffsetYPercent - rhs.OffsetYPercent) > 0.000001 ||
                Math.Abs(lhs.RowSpacingPercent - rhs.RowSpacingPercent) > 0.000001)
            {
                return false;
            }
        }

        return true;
    }

    private static bool TryLoadBundledDefaults(out UserSettings settings)
    {
        settings = new UserSettings();
        try
        {
            string bundledPath = KeymapStore.GetDefaultKeymapPath();
            if (!File.Exists(bundledPath))
            {
                return false;
            }

            string json = File.ReadAllText(bundledPath);
            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !TryGetPropertyIgnoreCase(root, "Settings", out JsonElement settingsElement) ||
                settingsElement.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            UserSettings? parsed = settingsElement.Deserialize<UserSettings>(new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
            if (parsed == null)
            {
                return false;
            }

            parsed.NormalizeRanges();
            settings = parsed;
            return true;
        }
        catch
        {
            settings = new UserSettings();
            return false;
        }
    }

    private static bool TryGetPropertyIgnoreCase(JsonElement element, string propertyName, out JsonElement value)
    {
        foreach (JsonProperty property in element.EnumerateObject())
        {
            if (string.Equals(property.Name, propertyName, StringComparison.OrdinalIgnoreCase))
            {
                value = property.Value;
                return true;
            }
        }

        value = default;
        return false;
    }

    private static bool NormalizeGestureAction(string? action, string fallback, out string normalized)
    {
        if (string.IsNullOrWhiteSpace(action))
        {
            normalized = fallback;
            return true;
        }

        string trimmed = action.Trim();
        normalized = trimmed;
        return !string.Equals(trimmed, action, StringComparison.Ordinal);
    }

    private static bool IsChordShiftGestureAction(string? action)
    {
        return string.Equals(action?.Trim(), "Chordal Shift", StringComparison.OrdinalIgnoreCase);
    }
}
