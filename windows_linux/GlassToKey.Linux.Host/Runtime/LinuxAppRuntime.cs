using GlassToKey.Linux.Config;
using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Models;

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
}
