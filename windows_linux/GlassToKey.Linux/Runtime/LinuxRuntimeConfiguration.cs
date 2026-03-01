using GlassToKey.Linux.Config;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Runtime;

internal sealed record LinuxRuntimeConfiguration(
    string SettingsPath,
    LinuxHostSettings Settings,
    TrackpadLayoutPreset LayoutPreset,
    KeymapStore Keymap,
    IReadOnlyList<LinuxTrackpadBinding> Bindings,
    IReadOnlyList<string> Warnings,
    IReadOnlyList<LinuxInputDeviceDescriptor> Devices);
