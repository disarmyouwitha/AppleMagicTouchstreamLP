using GlassToKey.Linux.Config;
using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Models;
using System.Text.Json;

namespace GlassToKey.Linux.Runtime;

public sealed class LinuxAppRuntime
{
    private readonly LinuxTrackpadEnumerator _enumerator;
    private readonly LinuxSettingsStore _settingsStore;

    public LinuxAppRuntime(
        LinuxTrackpadEnumerator? enumerator = null,
        LinuxSettingsStore? settingsStore = null)
    {
        _enumerator = enumerator ?? new LinuxTrackpadEnumerator();
        _settingsStore = settingsStore ?? new LinuxSettingsStore();
    }

    public LinuxRuntimeConfiguration LoadConfiguration()
    {
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = _enumerator.EnumerateDevices();
        LinuxHostSettings settings = _settingsStore.LoadOrCreateDefaults(devices);
        UserSettings sharedProfile = settings.GetSharedProfile();
        List<string> warnings = [];
        List<LinuxTrackpadBinding> bindings = ResolveBindings(settings, devices, warnings);
        KeymapStore keymap = LoadKeymap(settings, warnings);
        TrackpadLayoutPreset preset = TrackpadLayoutPreset.ResolveByNameOrDefault(sharedProfile.LayoutPresetName);
        keymap.SetActiveLayout(preset.Name);

        return new LinuxRuntimeConfiguration(
            _settingsStore.GetSettingsPath(),
            settings,
            sharedProfile,
            preset,
            keymap,
            bindings,
            warnings,
            devices);
    }

    public LinuxRuntimeConfiguration LoadReplayConfiguration()
    {
        LinuxHostSettings settings = _settingsStore.Load();
        if (string.IsNullOrWhiteSpace(settings.LayoutPresetName))
        {
            settings.LayoutPresetName = TrackpadLayoutPreset.SixByThree.Name;
        }

        UserSettings sharedProfile = settings.GetSharedProfile();
        List<string> warnings = [];
        KeymapStore keymap = LoadKeymap(settings, warnings);
        TrackpadLayoutPreset preset = TrackpadLayoutPreset.ResolveByNameOrDefault(sharedProfile.LayoutPresetName);
        keymap.SetActiveLayout(preset.Name);

        return new LinuxRuntimeConfiguration(
            _settingsStore.GetSettingsPath(),
            settings,
            sharedProfile,
            preset,
            keymap,
            Array.Empty<LinuxTrackpadBinding>(),
            warnings,
            Array.Empty<LinuxInputDeviceDescriptor>());
    }

    public string InitializeSettings()
    {
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = _enumerator.EnumerateDevices();
        _settingsStore.LoadOrCreateDefaults(devices);
        return _settingsStore.GetSettingsPath();
    }

    public bool TryBindTrackpad(TrackpadSide side, string deviceToken, out string message)
    {
        if (string.IsNullOrWhiteSpace(deviceToken))
        {
            message = "Device token is empty.";
            return false;
        }

        IReadOnlyList<LinuxInputDeviceDescriptor> devices = _enumerator.EnumerateDevices();
        LinuxInputDeviceDescriptor? device = ResolveDevice(deviceToken, devices);
        if (device == null)
        {
            message = $"No device matched '{deviceToken}'.";
            return false;
        }

        LinuxHostSettings settings = _settingsStore.LoadOrCreateDefaults(devices);
        switch (side)
        {
            case TrackpadSide.Left:
                settings.LeftTrackpadStableId = device.StableId;
                if (string.Equals(settings.RightTrackpadStableId, device.StableId, StringComparison.OrdinalIgnoreCase))
                {
                    settings.RightTrackpadStableId = null;
                }

                break;
            case TrackpadSide.Right:
                settings.RightTrackpadStableId = device.StableId;
                if (string.Equals(settings.LeftTrackpadStableId, device.StableId, StringComparison.OrdinalIgnoreCase))
                {
                    settings.LeftTrackpadStableId = null;
                }

                break;
            default:
                message = $"Unsupported side '{side}'.";
                return false;
        }

        _settingsStore.Save(settings);
        message = $"{side} trackpad bound to '{device.DisplayName}' [{device.StableId}].";
        return true;
    }

    public string SwapTrackpadBindings()
    {
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = _enumerator.EnumerateDevices();
        LinuxHostSettings settings = _settingsStore.LoadOrCreateDefaults(devices);
        (settings.LeftTrackpadStableId, settings.RightTrackpadStableId) =
            (settings.RightTrackpadStableId, settings.LeftTrackpadStableId);
        _settingsStore.Save(settings);
        return _settingsStore.GetSettingsPath();
    }

    public IReadOnlyList<LinuxInputDeviceDescriptor> EnumerateDevices()
    {
        return _enumerator.EnumerateDevices();
    }

    public LinuxHostSettings LoadSettings()
    {
        return _settingsStore.Load();
    }

    public string SaveSettings(LinuxHostSettings settings)
    {
        _settingsStore.Save(settings);
        return _settingsStore.GetSettingsPath();
    }

    public bool TryLoadKeymap(string keymapPath, out string message)
    {
        return TryImportProfile(keymapPath, out message);
    }

    public bool TryImportProfile(string path, out string message)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            message = "Import path is empty.";
            return false;
        }

        string fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath))
        {
            message = $"Import file '{fullPath}' was not found.";
            return false;
        }

        string json;
        try
        {
            json = File.ReadAllText(fullPath);
        }
        catch (Exception ex)
        {
            message = $"Import file '{fullPath}' could not be read: {ex.Message}";
            return false;
        }

        string? windowsBundleError = null;

        if (LooksLikeWindowsSettingsBundle(json) &&
            TryImportWindowsSettingsBundle(json, fullPath, out LinuxHostSettings importedWindowsSettings, out windowsBundleError))
        {
            importedWindowsSettings.Normalize();
            _settingsStore.Save(importedWindowsSettings);
            message = $"GlassToKey settings and keymap imported from '{fullPath}'.";
            return true;
        }

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        if (!keymap.TryImportFromJson(json, out string error))
        {
            message = $"Import '{fullPath}' could not be loaded: {windowsBundleError ?? error}";
            return false;
        }

        LinuxHostSettings settings = _settingsStore.Load();
        settings.KeymapPath = fullPath;
        _settingsStore.Save(settings);
        message = $"Linux host keymap set to '{fullPath}'.";
        return true;
    }

    public bool TryExportProfile(string path, out string message)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            message = "Export path is empty.";
            return false;
        }

        try
        {
            LinuxHostSettings settings = _settingsStore.Load();
            KeymapStore keymap = KeymapStore.LoadBundledDefault();
            if (!string.IsNullOrWhiteSpace(settings.KeymapPath) &&
                File.Exists(settings.KeymapPath) &&
                !keymap.TryImportFromFile(settings.KeymapPath, out _))
            {
                keymap = KeymapStore.LoadBundledDefault();
            }

            WindowsSettingsBundleFile bundle = new()
            {
                Version = 1,
                Settings = settings.GetSharedProfile().Clone(),
                KeymapJson = keymap.SerializeToJson(writeIndented: false)
            };

            string? directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            string json = JsonSerializer.Serialize(bundle, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                WriteIndented = true
            });
            File.WriteAllText(path, json);
            message = $"Exported GlassToKey profile to '{path}'.";
            return true;
        }
        catch (Exception ex)
        {
            message = $"Failed to export Linux profile to '{path}': {ex.Message}";
            return false;
        }
    }

    private bool TryImportWindowsSettingsBundle(
        string json,
        string sourcePath,
        out LinuxHostSettings settings,
        out string? error)
    {
        settings = new LinuxHostSettings();
        error = null;

        WindowsSettingsBundleFile? bundle;
        try
        {
            bundle = JsonSerializer.Deserialize<WindowsSettingsBundleFile>(
                json,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }

        if (bundle?.Settings == null || string.IsNullOrWhiteSpace(bundle.KeymapJson))
        {
            error = "Expected a GlassToKey settings export with both settings and keymap data.";
            return false;
        }

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        if (!keymap.TryImportFromJson(bundle.KeymapJson, out string keymapError))
        {
            error = $"Keymap section is invalid: {keymapError}";
            return false;
        }

        string importedKeymapPath = GetImportedKeymapPath(sourcePath);
        if (!keymap.TryExportToFile(importedKeymapPath, out string exportError))
        {
            error = $"Imported keymap could not be persisted: {exportError}";
            return false;
        }

        LinuxHostSettings current = _settingsStore.Load();
        current.SharedProfile = bundle.Settings.Clone();
        current.LayoutPresetName = current.SharedProfile.LayoutPresetName;
        current.KeymapPath = importedKeymapPath;
        settings = current;
        return true;
    }

    private string GetImportedKeymapPath(string sourcePath)
    {
        string settingsPath = _settingsStore.GetSettingsPath();
        string settingsDirectory = Path.GetDirectoryName(settingsPath) ?? AppContext.BaseDirectory;
        string fileName = Path.GetFileNameWithoutExtension(sourcePath);
        if (string.IsNullOrWhiteSpace(fileName))
        {
            fileName = "imported";
        }

        return Path.Combine(settingsDirectory, $"{fileName}.keymap.json");
    }

    private static bool LooksLikeWindowsSettingsBundle(string json)
    {
        return TryDetectSettingsProperty(json, "ActiveLayer") ||
               TryDetectSettingsProperty(json, "ColumnSettingsByLayout") ||
               TryDetectSettingsProperty(json, "LeftDevicePath");
    }

    private static bool TryDetectSettingsProperty(string json, string propertyName)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement root = document.RootElement;
            if (!TryGetPropertyIgnoreCase(root, "Settings", out JsonElement settingsElement) ||
                settingsElement.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            return TryGetPropertyIgnoreCase(settingsElement, propertyName, out _);
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

    private static List<LinuxTrackpadBinding> ResolveBindings(
        LinuxHostSettings settings,
        IReadOnlyList<LinuxInputDeviceDescriptor> devices,
        List<string> warnings)
    {
        List<LinuxTrackpadBinding> bindings = [];
        HashSet<string> usedStableIds = new(StringComparer.OrdinalIgnoreCase);

        AddBinding(TrackpadSide.Left, settings.LeftTrackpadStableId, devices, usedStableIds, bindings, warnings);
        AddBinding(TrackpadSide.Right, settings.RightTrackpadStableId, devices, usedStableIds, bindings, warnings);

        if (bindings.Count == 0)
        {
            for (int index = 0; index < devices.Count && bindings.Count < 2; index++)
            {
                TrackpadSide side = bindings.Count == 0 ? TrackpadSide.Left : TrackpadSide.Right;
                if (usedStableIds.Add(devices[index].StableId))
                {
                    bindings.Add(new LinuxTrackpadBinding(side, devices[index]));
                }
            }
        }

        return bindings;
    }

    private static void AddBinding(
        TrackpadSide side,
        string? requestedStableId,
        IReadOnlyList<LinuxInputDeviceDescriptor> devices,
        HashSet<string> usedStableIds,
        List<LinuxTrackpadBinding> bindings,
        List<string> warnings)
    {
        LinuxInputDeviceDescriptor? chosen = null;
        if (!string.IsNullOrWhiteSpace(requestedStableId))
        {
            for (int index = 0; index < devices.Count; index++)
            {
                if (string.Equals(devices[index].StableId, requestedStableId, StringComparison.OrdinalIgnoreCase))
                {
                    chosen = devices[index];
                    break;
                }
            }

            if (chosen == null)
            {
                warnings.Add($"Configured {side} trackpad '{requestedStableId}' is currently unavailable.");
                return;
            }
        }

        if (chosen == null)
        {
            for (int index = 0; index < devices.Count; index++)
            {
                LinuxInputDeviceDescriptor candidate = devices[index];
                if (usedStableIds.Contains(candidate.StableId))
                {
                    continue;
                }

                chosen = candidate;
                break;
            }
        }

        if (chosen == null)
        {
            return;
        }

        if (usedStableIds.Add(chosen.StableId))
        {
            bindings.Add(new LinuxTrackpadBinding(side, chosen));
        }
    }

    private static KeymapStore LoadKeymap(LinuxHostSettings settings, List<string> warnings)
    {
        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        if (string.IsNullOrWhiteSpace(settings.KeymapPath))
        {
            return keymap;
        }

        if (!keymap.TryImportFromFile(settings.KeymapPath, out string error))
        {
            warnings.Add($"Keymap '{settings.KeymapPath}' could not be loaded: {error}");
        }

        return keymap;
    }

    private static LinuxInputDeviceDescriptor? ResolveDevice(string token, IReadOnlyList<LinuxInputDeviceDescriptor> devices)
    {
        for (int index = 0; index < devices.Count; index++)
        {
            LinuxInputDeviceDescriptor device = devices[index];
            if (string.Equals(device.DeviceNode, token, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(device.StableId, token, StringComparison.OrdinalIgnoreCase))
            {
                return device;
            }
        }

        return null;
    }

    private sealed class WindowsSettingsBundleFile
    {
        public int Version { get; set; } = 1;
        public UserSettings Settings { get; set; } = new();
        public string KeymapJson { get; set; } = string.Empty;
    }
}
