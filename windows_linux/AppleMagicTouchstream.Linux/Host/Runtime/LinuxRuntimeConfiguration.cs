using AppleMagicTouchstream.Linux.Config;
using AppleMagicTouchstream.Platform.Linux.Models;

namespace AppleMagicTouchstream.Linux.Runtime;

public sealed record LinuxRuntimeConfiguration(
    string SettingsPath,
    LinuxHostSettings Settings,
    UserSettings SharedProfile,
    TrackpadLayoutPreset LayoutPreset,
    KeymapStore Keymap,
    IReadOnlyList<LinuxTrackpadBinding> Bindings,
    IReadOnlyList<string> Warnings,
    IReadOnlyList<LinuxInputDeviceDescriptor> Devices);
