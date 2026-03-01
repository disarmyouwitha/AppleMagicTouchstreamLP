using GlassToKey.Linux.Config;
using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Runtime;

internal sealed class LinuxAppRuntime
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
        List<string> warnings = [];
        List<LinuxTrackpadBinding> bindings = ResolveBindings(settings, devices, warnings);
        KeymapStore keymap = LoadKeymap(settings, warnings);
        TrackpadLayoutPreset preset = TrackpadLayoutPreset.ResolveByNameOrDefault(settings.LayoutPresetName);

        return new LinuxRuntimeConfiguration(
            _settingsStore.GetSettingsPath(),
            settings,
            preset,
            keymap,
            bindings,
            warnings,
            devices);
    }

    public string InitializeSettings()
    {
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = _enumerator.EnumerateDevices();
        _settingsStore.LoadOrCreateDefaults(devices);
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
                if (!string.IsNullOrWhiteSpace(requestedStableId))
                {
                    warnings.Add($"Configured {side} trackpad '{requestedStableId}' was unavailable. Falling back to '{candidate.StableId}'.");
                }

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
}
