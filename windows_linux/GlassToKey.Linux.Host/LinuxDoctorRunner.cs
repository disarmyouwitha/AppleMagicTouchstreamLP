using GlassToKey.Linux.Runtime;
using GlassToKey.Platform.Linux.Evdev;
using GlassToKey.Platform.Linux.Models;
using GlassToKey.Platform.Linux.Uinput;

namespace GlassToKey.Linux;

public readonly record struct LinuxDoctorResult(bool Success, string Report);

public static class LinuxDoctorRunner
{
    public static LinuxDoctorResult Run()
    {
        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadConfiguration();
        LinuxUinputAccessStatus uinput = new LinuxUinputPermissionProbe().Probe();
        LinuxEvdevReader reader = new();

        bool ok = true;
        List<string> issues = [];
        StringWriter writer = new();

        writer.WriteLine("GlassToKey Linux doctor");
        writer.WriteLine($"  SettingsPath: {configuration.SettingsPath}");
        writer.WriteLine($"  SettingsFileExists: {File.Exists(configuration.SettingsPath)}");
        writer.WriteLine($"  SettingsDirWritable: {CanWriteDirectory(Path.GetDirectoryName(configuration.SettingsPath), out string settingsError)}");
        if (!string.IsNullOrWhiteSpace(settingsError))
        {
            writer.WriteLine($"  SettingsDirError: {settingsError}");
            ok = false;
            issues.Add("settings");
        }

        string bundledKeymapPath = Path.Combine(AppContext.BaseDirectory, "GLASSTOKEY_DEFAULT_KEYMAP.json");
        bool bundledKeymapPresent = File.Exists(bundledKeymapPath);
        writer.WriteLine($"  BundledKeymap: {bundledKeymapPath}");
        writer.WriteLine($"  BundledKeymapPresent: {bundledKeymapPresent}");
        if (!bundledKeymapPresent)
        {
            ok = false;
            issues.Add("bundled-keymap");
        }

        if (!string.IsNullOrWhiteSpace(configuration.Settings.KeymapPath))
        {
            bool customKeymapPresent = File.Exists(configuration.Settings.KeymapPath);
            writer.WriteLine($"  CustomKeymap: {configuration.Settings.KeymapPath}");
            writer.WriteLine($"  CustomKeymapPresent: {customKeymapPresent}");
            if (!customKeymapPresent)
            {
                ok = false;
                issues.Add("custom-keymap");
            }
        }

        writer.WriteLine("uinput");
        writer.WriteLine($"  Node: {uinput.DeviceNode}");
        writer.WriteLine($"  Present: {uinput.DevicePresent}");
        writer.WriteLine($"  ReadWriteAccess: {uinput.CanOpenReadWrite}");
        writer.WriteLine($"  Access: {uinput.AccessError}");
        writer.WriteLine($"  Guidance: {uinput.Guidance}");
        if (!uinput.IsReady)
        {
            ok = false;
            issues.Add("uinput");
        }

        writer.WriteLine($"DevicesDetected: {configuration.Devices.Count}");
        for (int index = 0; index < configuration.Devices.Count; index++)
        {
            LinuxInputDeviceDescriptor device = configuration.Devices[index];
            writer.WriteLine($"  Device[{index}] {device.DisplayName}");
            writer.WriteLine($"    Node: {device.DeviceNode}");
            writer.WriteLine($"    StableId: {device.StableId}");
            writer.WriteLine($"    EventAccess: {(device.CanOpenEventStream ? "ok" : device.AccessError)}");
            writer.WriteLine($"    PreferredInterface: {device.IsPreferredInterface}");
            writer.WriteLine($"    Pressure: {device.SupportsPressure}");
            writer.WriteLine($"    ButtonClick: {device.SupportsButtonClick}");
            if (!device.CanOpenEventStream)
            {
                ok = false;
                issues.Add($"event:{device.DeviceNode}");
            }
        }

        writer.WriteLine($"BindingsResolved: {configuration.Bindings.Count}");
        if (configuration.Bindings.Count == 0)
        {
            ok = false;
            issues.Add("bindings");
        }

        for (int index = 0; index < configuration.Bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = configuration.Bindings[index];
            writer.WriteLine($"  Binding[{index}] {binding.Side}: {binding.Device.DisplayName}");
            writer.WriteLine($"    Node: {binding.Device.DeviceNode}");
            try
            {
                LinuxTrackpadAxisProfile axis = reader.GetAxisProfile(binding.Device.DeviceNode);
                writer.WriteLine($"    Max: ({axis.MaxX},{axis.MaxY})");
                writer.WriteLine($"    Min: ({axis.MinX},{axis.MinY})");
                writer.WriteLine($"    SlotCount: {axis.SlotCount}");
            }
            catch (Exception ex)
            {
                writer.WriteLine($"    AxisProbeWarning: {ex.Message}");
                writer.WriteLine("    AxisProbeGuidance: If event access is otherwise ok, re-run doctor outside the sandbox before treating this as a product issue.");
            }
        }

        for (int index = 0; index < configuration.Warnings.Count; index++)
        {
            writer.WriteLine($"Warning: {configuration.Warnings[index]}");
        }

        if (issues.Count > 0)
        {
            writer.WriteLine($"Summary: issues detected in {string.Join(", ", issues.Distinct(StringComparer.OrdinalIgnoreCase))}");
        }
        else
        {
            writer.WriteLine("Summary: ok");
        }

        return new LinuxDoctorResult(ok, writer.ToString());
    }

    private static bool CanWriteDirectory(string? directory, out string error)
    {
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(directory))
        {
            error = "missing directory";
            return false;
        }

        try
        {
            Directory.CreateDirectory(directory);
            string probePath = Path.Combine(directory, $".doctor-{Environment.ProcessId}.tmp");
            File.WriteAllText(probePath, "ok");
            File.Delete(probePath);
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }
}
