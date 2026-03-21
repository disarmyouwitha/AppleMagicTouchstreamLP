using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace GlassToKey;

public sealed class GlassToKeyProfileBundle
{
    public const int CurrentVersion = 1;

    private static readonly JsonSerializerOptions ReadOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public int Version { get; set; } = CurrentVersion;
    public UserSettings Settings { get; set; } = new();
    public string KeymapJson { get; set; } = string.Empty;

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public Dictionary<string, JsonElement>? HostExtensions { get; set; }

    public static GlassToKeyProfileBundle Create(UserSettings settings, KeymapStore keymap)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(keymap);

        return new GlassToKeyProfileBundle
        {
            Version = CurrentVersion,
            Settings = CreatePortableSettingsSnapshot(settings),
            KeymapJson = keymap.SerializeToJson(writeIndented: false),
            HostExtensions = null
        };
    }

    public static UserSettings CreatePortableSettingsSnapshot(UserSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        UserSettings portable = settings.Clone();
        portable.LeftDevicePath = null;
        portable.RightDevicePath = null;
        portable.DecoderProfilesByDevicePath = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        portable.RunAtStartup = false;
        portable.StartInTrayOnLaunch = false;
        portable.NormalizeRanges();
        return portable;
    }

    public string SerializeToJson(bool writeIndented = true)
    {
        JsonSerializerOptions options = new()
        {
            WriteIndented = writeIndented
        };

        return JsonSerializer.Serialize(this, options);
    }

    public bool TryLoadPortableProfile(out UserSettings settings, out KeymapStore keymap, out string error)
    {
        settings = new UserSettings();
        keymap = KeymapStore.LoadBundledDefault();
        error = string.Empty;

        if (Settings == null || string.IsNullOrWhiteSpace(KeymapJson))
        {
            error = "Expected a GlassToKey settings export with both settings and keymap data.";
            return false;
        }

        UserSettings importedSettings = Settings.Clone();
        importedSettings.NormalizeRanges();

        if (!keymap.TryImportFromJson(KeymapJson, out string keymapError))
        {
            error = $"Keymap section is invalid: {keymapError}";
            return false;
        }

        settings = importedSettings;
        return true;
    }

    public void SetHostExtension<T>(string hostId, T value)
    {
        if (string.IsNullOrWhiteSpace(hostId))
        {
            throw new ArgumentException("Host extension id is required.", nameof(hostId));
        }

        HostExtensions ??= new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        HostExtensions[hostId.Trim()] = JsonSerializer.SerializeToElement(value, ReadOptions);
    }

    public bool TryGetHostExtension<T>(string hostId, out T? value)
    {
        value = default;
        if (string.IsNullOrWhiteSpace(hostId) ||
            HostExtensions == null ||
            !HostExtensions.TryGetValue(hostId.Trim(), out JsonElement element))
        {
            return false;
        }

        try
        {
            value = element.Deserialize<T>(ReadOptions);
            return value != null;
        }
        catch
        {
            value = default;
            return false;
        }
    }

    public static bool TryParse(string json, out GlassToKeyProfileBundle bundle, out string error)
    {
        bundle = new GlassToKeyProfileBundle();
        error = string.Empty;

        if (string.IsNullOrWhiteSpace(json))
        {
            error = "Import file is empty.";
            return false;
        }

        try
        {
            GlassToKeyProfileBundle? parsed = JsonSerializer.Deserialize<GlassToKeyProfileBundle>(json, ReadOptions);
            if (parsed == null || parsed.Settings == null || string.IsNullOrWhiteSpace(parsed.KeymapJson))
            {
                error = "Expected a GlassToKey settings export with both settings and keymap data.";
                return false;
            }

            parsed.HostExtensions = parsed.HostExtensions == null
                ? null
                : new Dictionary<string, JsonElement>(parsed.HostExtensions, StringComparer.OrdinalIgnoreCase);
            bundle = parsed;
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }
}
