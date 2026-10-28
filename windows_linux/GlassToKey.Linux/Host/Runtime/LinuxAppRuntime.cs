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

    public LinuxRuntimeConfiguration LoadConfiguration(LinuxRuntimePolicy policy = LinuxRuntimePolicy.DesktopInteractive)
    {
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = _enumerator.EnumerateDevices();
        LinuxHostSettings settings = _settingsStore.LoadOrCreateDefaults(devices);
        UserSettings sharedProfile = policy.ApplyToProfile(settings.GetSharedProfile());
        List<string> warnings = [];
        List<LinuxTrackpadBinding> bindings = ResolveBindings(settings, devices, warnings, policy);
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

    public bool TrySaveKeymap(KeymapStore keymap, out string keymapPath, out string message)
    {
        keymapPath = string.Empty;
        if (keymap == null)
        {
            message = "Keymap payload is missing.";
            return false;
        }

        LinuxHostSettings settings = _settingsStore.Load();
        string targetPath = ResolveWritableKeymapPath(settings);
        if (!keymap.TryExportToFile(targetPath, out string exportError))
        {
            message = $"Failed to persist Linux keymap to '{targetPath}': {exportError}";
            return false;
        }

        settings.KeymapPath = targetPath;
        settings.KeymapRevision = NextKeymapRevision(settings.KeymapRevision);
        settings.Normalize();
        _settingsStore.Save(settings);

        keymapPath = targetPath;
        message = $"Linux host keymap saved to '{targetPath}'.";
        return true;
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

        if (TryImportProfileBundle(json, fullPath, out LinuxHostSettings importedSettings, out string? bundleError))
        {
            importedSettings.Normalize();
            _settingsStore.Save(importedSettings);
            message = $"GlassToKey settings and keymap imported from '{fullPath}'.";
            return true;
        }

        KeymapStore keymap = KeymapStore.LoadBundledDefault();
        if (!keymap.TryImportFromJson(json, out string error))
        {
            message = $"Import '{fullPath}' could not be loaded: {bundleError ?? error}";
            return false;
        }

        LinuxHostSettings settings = _settingsStore.Load();
        settings.KeymapPath = fullPath;
        settings.KeymapRevision = NextKeymapRevision(settings.KeymapRevision);
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

            GlassToKeyProfileBundle bundle = GlassToKeyProfileBundle.Create(settings.GetSharedProfile(), keymap);
            bundle.SetHostExtension("linux", BuildLinuxHostExtension(settings));

            string? directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            string json = bundle.SerializeToJson(writeIndented: true);
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

    private bool TryImportProfileBundle(
        string json,
        string sourcePath,
        out LinuxHostSettings settings,
        out string? error)
    {
        settings = new LinuxHostSettings();
        error = null;

        if (!GlassToKeyProfileBundle.TryParse(json, out GlassToKeyProfileBundle bundle, out string bundleParseError))
        {
            error = bundleParseError;
            return false;
        }

        if (!bundle.TryLoadPortableProfile(out UserSettings importedProfile, out KeymapStore keymap, out string bundleLoadError))
        {
            error = bundleLoadError;
            return false;
        }

        string importedKeymapPath = GetImportedKeymapPath(sourcePath);
        if (!keymap.TryExportToFile(importedKeymapPath, out string exportError))
        {
            error = $"Imported keymap could not be persisted: {exportError}";
            return false;
        }

        LinuxHostSettings current = _settingsStore.Load();
        current.SharedProfile = importedProfile;
        current.LayoutPresetName = current.SharedProfile.LayoutPresetName;
        current.KeymapPath = importedKeymapPath;
        current.KeymapRevision = NextKeymapRevision(current.KeymapRevision);
        ApplyLinuxHostExtension(bundle, current);

        settings = current;
        return true;
    }

    private string ResolveWritableKeymapPath(LinuxHostSettings settings)
    {
        if (!string.IsNullOrWhiteSpace(settings.KeymapPath))
        {
            return Path.GetFullPath(settings.KeymapPath);
        }

        string settingsPath = _settingsStore.GetSettingsPath();
        string settingsDirectory = Path.GetDirectoryName(settingsPath) ?? AppContext.BaseDirectory;
        return Path.Combine(settingsDirectory, "keymap.json");
    }

    private static int NextKeymapRevision(int current)
    {
        return current == int.MaxValue ? 1 : current + 1;
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

    private static LinuxHostProfileExtension BuildLinuxHostExtension(LinuxHostSettings settings)
    {
        return new LinuxHostProfileExtension
        {
            LeftTrackpadStableId = settings.LeftTrackpadStableId,
            RightTrackpadStableId = settings.RightTrackpadStableId
        };
    }

    private static void ApplyLinuxHostExtension(GlassToKeyProfileBundle bundle, LinuxHostSettings settings)
    {
        if (bundle.TryGetHostExtension("linux", out LinuxHostProfileExtension? hostExtension) &&
            hostExtension != null)
        {
            settings.LeftTrackpadStableId = hostExtension.LeftTrackpadStableId;
            settings.RightTrackpadStableId = hostExtension.RightTrackpadStableId;
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
        List<string> warnings,
        LinuxRuntimePolicy policy)
    {
        bool hasSavedBindings =
            !string.IsNullOrWhiteSpace(settings.LeftTrackpadStableId) ||
            !string.IsNullOrWhiteSpace(settings.RightTrackpadStableId);
        bool allowAutomaticBindingSelection = policy.AllowsAutomaticBindingSelection(hasSavedBindings);
        List<LinuxTrackpadBinding> bindings = [];
        HashSet<string> usedStableIds = new(StringComparer.OrdinalIgnoreCase);

        AddBinding(TrackpadSide.Left, settings.LeftTrackpadStableId, devices, usedStableIds, bindings, warnings, allowAutomaticBindingSelection);
        AddBinding(TrackpadSide.Right, settings.RightTrackpadStableId, devices, usedStableIds, bindings, warnings, allowAutomaticBindingSelection);

        return bindings;
    }

    private static void AddBinding(
        TrackpadSide side,
        string? requestedStableId,
        IReadOnlyList<LinuxInputDeviceDescriptor> devices,
        HashSet<string> usedStableIds,
        List<LinuxTrackpadBinding> bindings,
        List<string> warnings,
        bool allowAutomaticBindingSelection)
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

        if (chosen == null && allowAutomaticBindingSelection)
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

    private sealed class LinuxHostProfileExtension
    {
        public string? LeftTrackpadStableId { get; set; }
        public string? RightTrackpadStableId { get; set; }
    }
}
