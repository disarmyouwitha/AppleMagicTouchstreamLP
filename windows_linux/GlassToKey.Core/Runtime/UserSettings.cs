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
    public bool AutocorrectEnabled { get; set; }
    public int AutocorrectMaxEditDistance { get; set; } = 2;
    public bool AutocorrectDryRunEnabled { get; set; }
    public string AutocorrectBlacklistCsv { get; set; } = string.Empty;
    public string AutocorrectOverridesCsv { get; set; } = string.Empty;
    public bool ChordShiftEnabled { get; set; } = true;
    public bool TypingEnabled { get; set; } = true;
    public bool RunAtStartup { get; set; }
    public bool StartInTrayOnLaunch { get; set; }
    public bool MemorySaverEnabled { get; set; }
    public bool HoldRepeatEnabled { get; set; }
    public bool ThreeFingerDragEnabled { get; set; }
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
    public string TopLeftCornerSwipeAction { get; set; } = "None";
    public string TopRightCornerSwipeAction { get; set; } = "None";
    public string BottomLeftCornerSwipeAction { get; set; } = "None";
    public string BottomRightCornerSwipeAction { get; set; } = "None";
    public string TwoFingerHoldAction { get; set; } = "None";
    public string ThreeFingerHoldAction { get; set; } = "None";
    public string FourFingerHoldAction { get; set; } = "Chordal Shift";
    public string LeftEdgeUpAction { get; set; } = "None";
    public string LeftEdgeDownAction { get; set; } = "None";
    public string RightEdgeUpAction { get; set; } = "None";
    public string RightEdgeDownAction { get; set; } = "None";
    public string TopEdgeLeftAction { get; set; } = "None";
    public string TopEdgeRightAction { get; set; } = "None";
    public string BottomEdgeLeftAction { get; set; } = "None";
    public string BottomEdgeRightAction { get; set; } = "None";
    public string ThreeFingerClickAction { get; set; } = "None";
    public string FourFingerClickAction { get; set; } = "None";
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
    public Dictionary<string, int>? GestureRepeatCadenceMsById { get; set; } = new(StringComparer.OrdinalIgnoreCase);
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
        AutocorrectEnabled = source.AutocorrectEnabled;
        AutocorrectMaxEditDistance = source.AutocorrectMaxEditDistance;
        AutocorrectDryRunEnabled = source.AutocorrectDryRunEnabled;
        AutocorrectBlacklistCsv = source.AutocorrectBlacklistCsv;
        AutocorrectOverridesCsv = source.AutocorrectOverridesCsv;
        ChordShiftEnabled = source.ChordShiftEnabled;
        TypingEnabled = source.TypingEnabled;
        RunAtStartup = source.RunAtStartup;
        StartInTrayOnLaunch = source.StartInTrayOnLaunch;
        MemorySaverEnabled = source.MemorySaverEnabled;
        HoldRepeatEnabled = source.HoldRepeatEnabled;
        ThreeFingerDragEnabled = source.ThreeFingerDragEnabled;
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
        TopLeftCornerSwipeAction = source.TopLeftCornerSwipeAction;
        TopRightCornerSwipeAction = source.TopRightCornerSwipeAction;
        BottomLeftCornerSwipeAction = source.BottomLeftCornerSwipeAction;
        BottomRightCornerSwipeAction = source.BottomRightCornerSwipeAction;
        TwoFingerHoldAction = source.TwoFingerHoldAction;
        ThreeFingerHoldAction = source.ThreeFingerHoldAction;
        FourFingerHoldAction = source.FourFingerHoldAction;
        LeftEdgeUpAction = source.LeftEdgeUpAction;
        LeftEdgeDownAction = source.LeftEdgeDownAction;
        RightEdgeUpAction = source.RightEdgeUpAction;
        RightEdgeDownAction = source.RightEdgeDownAction;
        TopEdgeLeftAction = source.TopEdgeLeftAction;
        TopEdgeRightAction = source.TopEdgeRightAction;
        BottomEdgeLeftAction = source.BottomEdgeLeftAction;
        BottomEdgeRightAction = source.BottomEdgeRightAction;
        ThreeFingerClickAction = source.ThreeFingerClickAction;
        FourFingerClickAction = source.FourFingerClickAction;
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
        GestureRepeatCadenceMsById = CloneGestureRepeatCadenceById(source.GestureRepeatCadenceMsById);
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
        return Path.Combine(AppContext.BaseDirectory, "settings.json");
    }

    public static UserSettings Load()
    {
        try
        {
            string path = GetSettingsPath();
            if (!File.Exists(path))
            {
                UserSettings firstRunDefaults = LoadBundledDefaultsOrDefault();
                firstRunDefaults.Save();
                return firstRunDefaults;
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

    public static UserSettings LoadBundledDefaultsOrDefault()
    {
        return TryLoadBundledDefaults(out UserSettings bundledDefaults)
            ? bundledDefaults
            : new UserSettings();
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

        int normalizedAutocorrectMaxEditDistance = Math.Clamp(AutocorrectMaxEditDistance, 0, 5);
        if (normalizedAutocorrectMaxEditDistance != AutocorrectMaxEditDistance)
        {
            AutocorrectMaxEditDistance = normalizedAutocorrectMaxEditDistance;
            changed = true;
        }

        double normalizedHoldDurationMs = Math.Clamp(HoldDurationMs, 10.0, 2000.0);
        if (!AreClose(normalizedHoldDurationMs, HoldDurationMs))
        {
            HoldDurationMs = normalizedHoldDurationMs;
            changed = true;
        }

        double normalizedDragCancelMm = Math.Clamp(DragCancelMm, 0.0, 50.0);
        if (!AreClose(normalizedDragCancelMm, DragCancelMm))
        {
            DragCancelMm = normalizedDragCancelMm;
            changed = true;
        }

        double normalizedTypingGraceMs = Math.Clamp(TypingGraceMs, 0.0, 5000.0);
        if (!AreClose(normalizedTypingGraceMs, TypingGraceMs))
        {
            TypingGraceMs = normalizedTypingGraceMs;
            changed = true;
        }

        double normalizedIntentMoveMm = Math.Clamp(IntentMoveMm, 0.0, 50.0);
        if (!AreClose(normalizedIntentMoveMm, IntentMoveMm))
        {
            IntentMoveMm = normalizedIntentMoveMm;
            changed = true;
        }

        double normalizedIntentVelocity = Math.Clamp(IntentVelocityMmPerSec, 0.0, 1000.0);
        if (!AreClose(normalizedIntentVelocity, IntentVelocityMmPerSec))
        {
            IntentVelocityMmPerSec = normalizedIntentVelocity;
            changed = true;
        }

        double normalizedSnapRadiusPercent = Math.Clamp(SnapRadiusPercent, 0.0, 1000.0);
        if (!AreClose(normalizedSnapRadiusPercent, SnapRadiusPercent))
        {
            SnapRadiusPercent = normalizedSnapRadiusPercent;
            changed = true;
        }

        double normalizedSnapAmbiguityRatio = Math.Clamp(SnapAmbiguityRatio, 1.0, 5.0);
        if (!AreClose(normalizedSnapAmbiguityRatio, SnapAmbiguityRatio))
        {
            SnapAmbiguityRatio = normalizedSnapAmbiguityRatio;
            changed = true;
        }

        double normalizedKeyBufferMs = Math.Clamp(KeyBufferMs, 0.0, 1000.0);
        if (!AreClose(normalizedKeyBufferMs, KeyBufferMs))
        {
            KeyBufferMs = normalizedKeyBufferMs;
            changed = true;
        }

        double normalizedKeyPaddingPercent = Math.Clamp(KeyPaddingPercent, 0.0, 90.0);
        if (!AreClose(normalizedKeyPaddingPercent, KeyPaddingPercent))
        {
            KeyPaddingPercent = normalizedKeyPaddingPercent;
            changed = true;
        }

        int normalizedForceMin = Math.Clamp(ForceMin, 0, ForceNormalizer.Max);
        if (normalizedForceMin != ForceMin)
        {
            ForceMin = normalizedForceMin;
            changed = true;
        }

        int normalizedForceCap = Math.Clamp(ForceCap, 0, ForceNormalizer.Max);
        if (normalizedForceCap != ForceCap)
        {
            ForceCap = normalizedForceCap;
            changed = true;
        }

        if (ForceCap < ForceMin)
        {
            ForceCap = ForceMin;
            changed = true;
        }

        if (KeyPaddingPercentByLayout != null)
        {
            foreach (string key in new List<string>(KeyPaddingPercentByLayout.Keys))
            {
                double normalized = Math.Clamp(KeyPaddingPercentByLayout[key], 0.0, 90.0);
                if (!AreClose(normalized, KeyPaddingPercentByLayout[key]))
                {
                    KeyPaddingPercentByLayout[key] = normalized;
                    changed = true;
                }
            }
        }

        if (DecoderProfilesByDevicePath != null)
        {
            foreach (string originalKey in new List<string>(DecoderProfilesByDevicePath.Keys))
            {
                string normalizedKey = originalKey.Trim();
                string value = DecoderProfilesByDevicePath[originalKey];
                if (string.IsNullOrWhiteSpace(normalizedKey) ||
                    !TrackpadDecoderProfileMap.TryParse(value, out TrackpadDecoderProfile profile))
                {
                    DecoderProfilesByDevicePath.Remove(originalKey);
                    changed = true;
                    continue;
                }

                string normalizedValue = TrackpadDecoderProfileMap.ToSettingsValue(profile);
                bool keyChanged = !string.Equals(originalKey, normalizedKey, StringComparison.Ordinal);
                bool valueChanged = !string.Equals(value, normalizedValue, StringComparison.Ordinal);
                if (!keyChanged && !valueChanged)
                {
                    continue;
                }

                DecoderProfilesByDevicePath.Remove(originalKey);
                DecoderProfilesByDevicePath[normalizedKey] = normalizedValue;
                changed = true;
            }
        }

        if (ColumnSettingsByLayout != null)
        {
            foreach (KeyValuePair<string, List<ColumnLayoutSettings>> pair in ColumnSettingsByLayout)
            {
                if (NormalizeColumnSettingsList(pair.Value))
                {
                    changed = true;
                }
            }
        }

        if (ColumnSettings != null && NormalizeColumnSettingsList(ColumnSettings))
        {
            changed = true;
        }

        if (TypingTuningCatalog.NormalizeSettings(this))
        {
            changed = true;
        }

        if (GestureBindingCatalog.NormalizeSettings(this))
        {
            changed = true;
        }

        return changed;
    }

    private static bool TryLoadBundledDefaults(out UserSettings settings)
    {
        settings = new UserSettings();
        try
        {
            string path = Path.Combine(AppContext.BaseDirectory, "GLASSTOKEY_DEFAULT_KEYMAP.json");
            if (!File.Exists(path))
            {
                return false;
            }

            string json = File.ReadAllText(path);
            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement payload = document.RootElement;
            if (payload.ValueKind == JsonValueKind.Object &&
                TryGetPropertyIgnoreCase(payload, "Settings", out JsonElement bundledSettings))
            {
                if (bundledSettings.ValueKind != JsonValueKind.Object)
                {
                    return false;
                }

                payload = bundledSettings;
            }

            UserSettings? loaded = JsonSerializer.Deserialize<UserSettings>(
                payload.GetRawText(),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (loaded == null)
            {
                return false;
            }

            loaded.NormalizeRanges();
            settings = loaded;
            return true;
        }
        catch
        {
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

    private static Dictionary<string, string>? CloneDecoderProfiles(Dictionary<string, string>? source)
    {
        return source == null
            ? null
            : new Dictionary<string, string>(source, StringComparer.OrdinalIgnoreCase);
    }

    private static Dictionary<string, int>? CloneGestureRepeatCadenceById(Dictionary<string, int>? source)
    {
        return source == null
            ? null
            : new Dictionary<string, int>(source, StringComparer.OrdinalIgnoreCase);
    }

    private static Dictionary<string, double>? CloneKeyPaddingByLayout(Dictionary<string, double>? source)
    {
        return source == null
            ? null
            : new Dictionary<string, double>(source, StringComparer.OrdinalIgnoreCase);
    }

    private static Dictionary<string, Dictionary<int, List<ColumnLayoutSettings>>> CloneColumnSettingsByLayoutLayer(
        Dictionary<string, Dictionary<int, List<ColumnLayoutSettings>>> source)
    {
        Dictionary<string, Dictionary<int, List<ColumnLayoutSettings>>> clone = new(StringComparer.OrdinalIgnoreCase);
        foreach (KeyValuePair<string, Dictionary<int, List<ColumnLayoutSettings>>> layoutPair in source)
        {
            Dictionary<int, List<ColumnLayoutSettings>> byLayer = new();
            foreach (KeyValuePair<int, List<ColumnLayoutSettings>> layerPair in layoutPair.Value)
            {
                byLayer[layerPair.Key] = CloneColumnSettingsList(layerPair.Value) ?? new List<ColumnLayoutSettings>();
            }

            clone[layoutPair.Key] = byLayer;
        }

        return clone;
    }

    private static Dictionary<string, List<ColumnLayoutSettings>>? CloneColumnSettingsByLayout(
        Dictionary<string, List<ColumnLayoutSettings>>? source)
    {
        if (source == null)
        {
            return null;
        }

        Dictionary<string, List<ColumnLayoutSettings>> clone = new(StringComparer.OrdinalIgnoreCase);
        foreach (KeyValuePair<string, List<ColumnLayoutSettings>> pair in source)
        {
            clone[pair.Key] = CloneColumnSettingsList(pair.Value) ?? new List<ColumnLayoutSettings>();
        }

        return clone;
    }

    private static List<ColumnLayoutSettings>? CloneColumnSettingsList(List<ColumnLayoutSettings>? source)
    {
        if (source == null)
        {
            return null;
        }

        List<ColumnLayoutSettings> clone = new(source.Count);
        for (int i = 0; i < source.Count; i++)
        {
            ColumnLayoutSettings item = source[i] ?? new ColumnLayoutSettings();
            clone.Add(new ColumnLayoutSettings(item.ScaleX, item.ScaleY, item.OffsetXPercent, item.OffsetYPercent, item.RowSpacingPercent, item.RotationDegrees));
        }

        return clone;
    }

    private static bool NormalizeColumnSettingsList(List<ColumnLayoutSettings> settings)
    {
        bool changed = false;
        for (int i = 0; i < settings.Count; i++)
        {
            ColumnLayoutSettings item = settings[i] ?? new ColumnLayoutSettings();
            double normalizedScaleX = Math.Clamp(item.ScaleX, RuntimeConfigurationFactory.MinColumnScale, 10.0);
            double normalizedScaleY = Math.Clamp(item.ScaleY, RuntimeConfigurationFactory.MinColumnScale, 10.0);
            double normalizedRotation = Math.Clamp(item.RotationDegrees, 0.0, 360.0);
            if (!AreClose(item.ScaleX, normalizedScaleX) ||
                !AreClose(item.ScaleY, normalizedScaleY) ||
                !AreClose(item.RotationDegrees, normalizedRotation))
            {
                settings[i] = new ColumnLayoutSettings(normalizedScaleX, normalizedScaleY, item.OffsetXPercent, item.OffsetYPercent, item.RowSpacingPercent, normalizedRotation);
                changed = true;
            }
        }

        return changed;
    }

    private static bool AreClose(double left, double right)
    {
        return Math.Abs(left - right) < 0.0001;
    }
}
