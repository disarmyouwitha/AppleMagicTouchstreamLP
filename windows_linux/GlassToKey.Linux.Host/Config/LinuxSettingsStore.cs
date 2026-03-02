using System.Text.Json;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Config;

public sealed class LinuxSettingsStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public string GetSettingsPath()
    {
        string? configHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        string root = string.IsNullOrWhiteSpace(configHome)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config")
            : configHome;
        return Path.Combine(root, "GlassToKey.Linux", "settings.json");
    }

    public LinuxHostSettings Load()
    {
        string path = GetSettingsPath();
        if (!File.Exists(path))
        {
            LinuxHostSettings defaults = new();
            defaults.Normalize();
            return defaults;
        }

        try
        {
            string json = File.ReadAllText(path);
            LinuxHostSettings? settings = JsonSerializer.Deserialize<LinuxHostSettings>(json, SerializerOptions);
            LinuxHostSettings resolved = settings ?? new LinuxHostSettings();
            if (resolved.Normalize())
            {
                Save(resolved);
            }

            return resolved;
        }
        catch
        {
            LinuxHostSettings defaults = new();
            defaults.Normalize();
            return defaults;
        }
    }

    public LinuxHostSettings LoadOrCreateDefaults(IReadOnlyList<LinuxInputDeviceDescriptor> devices)
    {
        LinuxHostSettings settings = Load();
        bool changed = ApplyAutoSelectionDefaults(settings, devices);
        string path = GetSettingsPath();
        if (changed || !File.Exists(path))
        {
            Save(settings);
        }

        return settings;
    }

    public void Save(LinuxHostSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        string path = GetSettingsPath();
        string? directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        string json = JsonSerializer.Serialize(settings, SerializerOptions);
        File.WriteAllText(path, json);
    }

    private static bool ApplyAutoSelectionDefaults(LinuxHostSettings settings, IReadOnlyList<LinuxInputDeviceDescriptor> devices)
    {
        bool changed = false;
        if (string.IsNullOrWhiteSpace(settings.LeftTrackpadStableId) && devices.Count >= 1)
        {
            settings.LeftTrackpadStableId = devices[0].StableId;
            changed = true;
        }

        if (string.IsNullOrWhiteSpace(settings.RightTrackpadStableId))
        {
            for (int index = 0; index < devices.Count; index++)
            {
                string stableId = devices[index].StableId;
                if (string.Equals(stableId, settings.LeftTrackpadStableId, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                settings.RightTrackpadStableId = stableId;
                changed = true;
                break;
            }
        }

        if (string.IsNullOrWhiteSpace(settings.LayoutPresetName))
        {
            settings.LayoutPresetName = TrackpadLayoutPreset.SixByThree.Name;
            changed = true;
        }

        changed |= settings.Normalize();

        return changed;
    }
}
