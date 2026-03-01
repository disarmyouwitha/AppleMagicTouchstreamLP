using GlassToKey.Linux.Config;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Runtime;

public sealed record LinuxRuntimeConfiguration(
    string SettingsPath,
    LinuxHostSettings Settings,
    UserSettings SharedProfile,
    TrackpadLayoutPreset LayoutPreset,
    KeymapStore Keymap,
    IReadOnlyList<LinuxTrackpadBinding> Bindings,
    IReadOnlyList<string> Warnings,
    IReadOnlyList<LinuxInputDeviceDescriptor> Devices);
