using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using GlassToKey.Linux.Runtime;
using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Evdev;
using GlassToKey.Platform.Linux.Haptics;
using GlassToKey.Platform.Linux.Models;
using GlassToKey.Platform.Linux.Contracts;
using GlassToKey.Platform.Linux.Uinput;
using GlassToKey.Platform.Linux;

namespace GlassToKey.Linux;

internal static class Program
{
    private const string CliName = "glasstokey";
    private const string GuiCliName = "glasstokey-gui";

    private static int Main(string[] args)
    {
        if (string.Equals(GetCommand(args), "__background-run", StringComparison.OrdinalIgnoreCase))
        {
            return RunBackgroundAsync(args).GetAwaiter().GetResult();
        }

        if (args.Length == 0)
        {
            return LaunchTrayHost();
        }

        if (string.Equals(args[0], "list-devices", StringComparison.OrdinalIgnoreCase))
        {
            return ListDevices();
        }

        if (string.Equals(args[0], "help", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(args[0], "--help", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(args[0], "-h", StringComparison.OrdinalIgnoreCase))
        {
            PrintUsage();
            return 0;
        }

        if (string.Equals(args[0], "read-frames", StringComparison.OrdinalIgnoreCase))
        {
            return ReadFramesAsync(args).GetAwaiter().GetResult();
        }

        if (string.Equals(args[0], "read-events", StringComparison.OrdinalIgnoreCase))
        {
            return ReadEventsAsync(args).GetAwaiter().GetResult();
        }

        if (string.Equals(args[0], "probe-axes", StringComparison.OrdinalIgnoreCase))
        {
            return ProbeAxes(args);
        }

        if (string.Equals(args[0], "probe-uinput", StringComparison.OrdinalIgnoreCase))
        {
            return ProbeUinput();
        }

        if (string.Equals(args[0], "pulse-haptics", StringComparison.OrdinalIgnoreCase))
        {
            return PulseHaptics(args);
        }

        if (string.Equals(args[0], "doctor", StringComparison.OrdinalIgnoreCase))
        {
            return RunDoctor();
        }

        if (string.Equals(args[0], "init-config", StringComparison.OrdinalIgnoreCase))
        {
            return InitConfig();
        }

        if (string.Equals(args[0], "print-keymap", StringComparison.OrdinalIgnoreCase))
        {
            return PrintKeymap();
        }

        if (string.Equals(args[0], "bind-left", StringComparison.OrdinalIgnoreCase))
        {
            return BindTrackpad(args, TrackpadSide.Left);
        }

        if (string.Equals(args[0], "bind-right", StringComparison.OrdinalIgnoreCase))
        {
            return BindTrackpad(args, TrackpadSide.Right);
        }

        if (string.Equals(args[0], "swap-sides", StringComparison.OrdinalIgnoreCase))
        {
            return SwapSides();
        }

        if (string.Equals(args[0], "print-udev-rules", StringComparison.OrdinalIgnoreCase))
        {
            return PrintUdevRules();
        }

        if (string.Equals(args[0], "load-keymap", StringComparison.OrdinalIgnoreCase))
        {
            return LoadKeymap(args);
        }

        if (string.Equals(args[0], "selftest", StringComparison.OrdinalIgnoreCase))
        {
            return RunSelfTest();
        }

        if (string.Equals(args[0], "capture-atpcap", StringComparison.OrdinalIgnoreCase))
        {
            return CaptureAtpCapAsync(args).GetAwaiter().GetResult();
        }

        if (string.Equals(args[0], "replay-atpcap", StringComparison.OrdinalIgnoreCase))
        {
            return ReplayAtpCap(args);
        }

        if (string.Equals(args[0], "summarize-atpcap", StringComparison.OrdinalIgnoreCase))
        {
            return SummarizeAtpCap(args);
        }

        if (string.Equals(args[0], "write-atpcap-fixture", StringComparison.OrdinalIgnoreCase))
        {
            return WriteAtpCapFixture(args);
        }

        if (string.Equals(args[0], "check-atpcap-fixture", StringComparison.OrdinalIgnoreCase))
        {
            return CheckAtpCapFixture(args);
        }

        if (string.Equals(args[0], "uinput-smoke", StringComparison.OrdinalIgnoreCase))
        {
            return SmokeUinput(args);
        }

        if (string.Equals(args[0], "watch-runtime", StringComparison.OrdinalIgnoreCase))
        {
            return WatchRuntimeAsync(args).GetAwaiter().GetResult();
        }

        if (string.Equals(args[0], "start", StringComparison.OrdinalIgnoreCase))
        {
            return StartBackgroundRuntimeAsync(args).GetAwaiter().GetResult();
        }

        if (string.Equals(args[0], "stop", StringComparison.OrdinalIgnoreCase))
        {
            return StopBackgroundRuntimeAsync().GetAwaiter().GetResult();
        }

        if (string.Equals(args[0], "run-engine", StringComparison.OrdinalIgnoreCase))
        {
            return RunEngineAsync(args).GetAwaiter().GetResult();
        }

        Console.Error.WriteLine($"Unknown command '{args[0]}'.");
        PrintUsage();
        return 1;
    }

    private static int ListDevices()
    {
        LinuxTrackpadEnumerator enumerator = new();
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = enumerator.EnumerateDevices();
        if (devices.Count == 0)
        {
            Console.WriteLine("No supported Apple Magic Trackpad multitouch event nodes found.");
            return 0;
        }

        foreach (LinuxInputDeviceDescriptor device in devices)
        {
            LinuxMagicTrackpadActuatorProbeResult haptics = LinuxMagicTrackpadActuatorProbe.Probe(device.DeviceNode);
            Console.WriteLine(device.DisplayName);
            Console.WriteLine($"  Node: {device.DeviceNode}");
            Console.WriteLine($"  StableId: {device.StableId}");
            Console.WriteLine($"  Vendor/Product: 0x{device.VendorId:x4}/0x{device.ProductId:x4}");
            Console.WriteLine($"  Multitouch: {device.SupportsMultitouch}");
            Console.WriteLine($"  Pressure: {device.SupportsPressure}");
            Console.WriteLine($"  ButtonClick: {device.SupportsButtonClick}");
            Console.WriteLine($"  EventAccess: {(device.CanOpenEventStream ? "ok" : device.AccessError)}");
            if (haptics.Supported)
            {
                Console.WriteLine($"  Haptics: {(haptics.CanOpenWrite ? "ok" : haptics.Status)}");
                Console.WriteLine($"  HapticsNode: {haptics.HidrawDeviceNode}");
                Console.WriteLine($"  HapticsInterface: {haptics.InterfaceName ?? "(unknown)"}");
            }
            else
            {
                Console.WriteLine($"  Haptics: {haptics.Status}");
            }
            Console.WriteLine();
        }

        return 0;
    }

    private static void PrintUsage()
    {
        Console.WriteLine("[After install]:");
        Console.WriteLine("  1. Reconnect the trackpads or wait a few seconds for refreshed udev permissions on both");
        Console.WriteLine("     `/dev/input/event*` and the Magic Trackpad actuator `/dev/hidraw*` nodes.");
        Console.WriteLine("  2. Add the desktop user to the 'glasstokey' group:");
        Console.WriteLine("     sudo usermod -aG glasstokey $USER");
        Console.WriteLine("  3. Log out and back in so the new group membership applies.");
        Console.WriteLine();

        Console.WriteLine("[Usage]:");
        Console.WriteLine($"  {CliName}            # start tray GUI");
        Console.WriteLine($"  {CliName} start      # start headless mode");
        Console.WriteLine($"  {CliName} stop       # stop headless mode");
        Console.WriteLine();
        Console.WriteLine("[Other Commands]:");
        Console.WriteLine($"  {CliName} print-keymap");
        Console.WriteLine($"  {CliName} list-devices");
        Console.WriteLine($"  {CliName} bind-left [device-node-or-stable-id]");
        Console.WriteLine($"  {CliName} bind-right [device-node-or-stable-id]");
        Console.WriteLine($"  {CliName} print-udev-rules");
        Console.WriteLine($"  {CliName} swap-sides");
        Console.WriteLine($"  {CliName} doctor");
        Console.WriteLine();
    }

    private static int LaunchTrayHost()
    {
        if (!LinuxGuiLauncher.IsGraphicalSession())
        {
            Console.Error.WriteLine("No graphical session detected. Use 'glasstokey start' for headless mode.");
            return 1;
        }

        LinuxGuiHostController trayController = new();
        LinuxGuiHostStatus trayStatus = trayController.Query();
        if (trayStatus.IsRunning && trayStatus.OwnsRuntime)
        {
            if (LinuxGuiLauncher.TryShowConfig())
            {
                Console.WriteLine("GlassToKey is already running in the tray.");
                return 0;
            }

            Console.Error.WriteLine("GlassToKey is already running in the tray, but the window could not be shown.");
            return 1;
        }

        if (TryHandOffHeadlessRuntimeToGui(out string? handoffMessage, out bool handoffSucceeded))
        {
            if (handoffSucceeded)
            {
                Console.WriteLine(handoffMessage);
                return 0;
            }

            Console.Error.WriteLine(handoffMessage);
            return 1;
        }

        if (LinuxGuiLauncher.TryShowConfig())
        {
            Console.WriteLine("Launching GlassToKey tray host.");
            return 0;
        }

        Console.Error.WriteLine("Could not launch GlassToKey tray host.");
        return 1;
    }

    private static string? GetCommand(string[] args)
    {
        return args.Length == 0 ? null : args[0];
    }

    private static async Task<int> ReadFramesAsync(string[] args)
    {
        LinuxTrackpadEnumerator enumerator = new();
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = enumerator.EnumerateDevices();
        LinuxInputDeviceDescriptor? device = ResolveDevice(args, devices);
        if (device == null)
        {
            Console.Error.WriteLine("No matching device found.");
            return 1;
        }

        double seconds = args.Length >= 3 && double.TryParse(args[2], out double parsedSeconds)
            ? parsedSeconds
            : 10.0;
        int maxFrames = args.Length >= 4 && int.TryParse(args[3], out int parsedMaxFrames)
            ? parsedMaxFrames
            : 20;

        LinuxEvdevReader reader = new();
        IReadOnlyList<LinuxEvdevFrameSnapshot> frames =
            await reader.ReadFramesAsync(device.DeviceNode, TimeSpan.FromSeconds(seconds), maxFrames).ConfigureAwait(false);

        Console.WriteLine($"Frames captured: {frames.Count}");
        foreach (LinuxEvdevFrameSnapshot snapshot in frames)
        {
            PrintFrame(snapshot);
        }

        return 0;
    }

    private static async Task<int> ReadEventsAsync(string[] args)
    {
        LinuxTrackpadEnumerator enumerator = new();
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = enumerator.EnumerateDevices();
        LinuxInputDeviceDescriptor? device = ResolveDevice(args, devices);
        if (device == null)
        {
            Console.Error.WriteLine("No matching device found.");
            return 1;
        }

        double seconds = args.Length >= 3 && double.TryParse(args[2], out double parsedSeconds)
            ? parsedSeconds
            : 10.0;
        int maxEvents = args.Length >= 4 && int.TryParse(args[3], out int parsedMaxEvents)
            ? parsedMaxEvents
            : 80;

        LinuxEvdevReader reader = new();
        IReadOnlyList<string> events =
            await reader.ReadRawEventsAsync(device.DeviceNode, TimeSpan.FromSeconds(seconds), maxEvents).ConfigureAwait(false);

        Console.WriteLine($"Events captured: {events.Count}");
        foreach (string entry in events)
        {
            Console.WriteLine(entry);
        }

        return 0;
    }

    private static LinuxInputDeviceDescriptor? ResolveDevice(string[] args, IReadOnlyList<LinuxInputDeviceDescriptor> devices)
    {
        if (devices.Count == 0)
        {
            return null;
        }

        if (args.Length < 2)
        {
            return devices[0];
        }

        string token = args[1];
        foreach (LinuxInputDeviceDescriptor device in devices)
        {
            if (string.Equals(device.DeviceNode, token, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(device.StableId, token, StringComparison.OrdinalIgnoreCase))
            {
                return device;
            }
        }

        return null;
    }

    private static int ProbeAxes(string[] args)
    {
        LinuxTrackpadEnumerator enumerator = new();
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = enumerator.EnumerateDevices();
        LinuxInputDeviceDescriptor? device = ResolveDevice(args, devices);
        if (device == null)
        {
            Console.Error.WriteLine("No matching device found.");
            return 1;
        }

        LinuxEvdevReader reader = new();
        LinuxTrackpadAxisProfile profile = reader.GetAxisProfile(device.DeviceNode);

        Console.WriteLine(device.DisplayName);
        Console.WriteLine($"  Node: {device.DeviceNode}");
        Console.WriteLine($"  StableId: {device.StableId}");
        Console.WriteLine("  InputContract: authoritative ABS_MT slot stream");
        PrintAxis("Slot", profile.Slot);
        PrintAxis("X", profile.X);
        PrintAxis("Y", profile.Y);
        PrintAxis("Pressure", profile.Pressure);
        Console.WriteLine($"  MinX: {profile.MinX}");
        Console.WriteLine($"  MinY: {profile.MinY}");
        Console.WriteLine($"  SlotCount: {profile.SlotCount}");
        Console.WriteLine($"  MaxX: {profile.MaxX}");
        Console.WriteLine($"  MaxY: {profile.MaxY}");
        return 0;
    }

    private static void PrintFrame(LinuxEvdevFrameSnapshot snapshot)
    {
        Console.WriteLine($"Frame {snapshot.FrameSequence}: contacts={snapshot.Frame.ContactCount}, button={snapshot.Frame.IsButtonPressed}, min=({snapshot.MinX},{snapshot.MinY}), max=({snapshot.MaxX},{snapshot.MaxY}), report=0x{snapshot.Frame.ReportId:x2}");
        int count = snapshot.Frame.GetClampedContactCount();
        for (int index = 0; index < count; index++)
        {
            ContactFrame contact = snapshot.Frame.GetContact(index);
            Console.WriteLine($"  [{index}] id={contact.Id} x={contact.X} y={contact.Y} pressure={contact.Pressure} flags=0x{contact.Flags:x2}");
        }
    }

    private static void PrintAxis(string label, LinuxInputAxisInfo? axis)
    {
        if (axis == null)
        {
            Console.WriteLine($"  {label}: unavailable");
            return;
        }

        Console.WriteLine($"  {label}: min={axis.Minimum} max={axis.Maximum} value={axis.Value} res={axis.Resolution}");
    }

    private static int ProbeUinput()
    {
        LinuxUinputPermissionProbe probe = new();
        LinuxUinputAccessStatus status = probe.Probe();

        Console.WriteLine("uinput probe");
        Console.WriteLine($"  Node: {status.DeviceNode}");
        Console.WriteLine($"  Present: {status.DevicePresent}");
        Console.WriteLine($"  ReadWriteAccess: {status.CanOpenReadWrite}");
        Console.WriteLine($"  Access: {status.AccessError}");
        Console.WriteLine($"  Guidance: {status.Guidance}");
        return status.IsReady ? 0 : 1;
    }

    private static int PulseHaptics(string[] args)
    {
        string target = args.Length >= 2 ? args[1] : "right";
        int count = args.Length >= 3 && int.TryParse(args[2], out int parsedCount)
            ? Math.Clamp(parsedCount, 1, 64)
            : 1;

        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadConfiguration(LinuxRuntimePolicy.HeadlessPureKeyboard);
        string? hint = ResolveHapticHint(target, configuration);
        if (string.IsNullOrWhiteSpace(hint))
        {
            Console.Error.WriteLine($"No matching haptics target found for '{target}'.");
            return 1;
        }

        int amplitude = TypingTuningCatalog.GetHapticsAmplitude(configuration.SharedProfile);
        uint strength = configuration.SharedProfile.HapticsStrength;
        if (amplitude <= 0)
        {
            strength = 0x00026C15u;
        }

        if (!LinuxMagicTrackpadActuatorHaptics.TryPulse(hint, strength, count, TimeSpan.FromMilliseconds(150), out string message))
        {
            Console.Error.WriteLine(message);
            return 1;
        }

        Console.WriteLine(message);
        return 0;
    }

    private static string? ResolveHapticHint(string target, LinuxRuntimeConfiguration configuration)
    {
        if (string.Equals(target, "left", StringComparison.OrdinalIgnoreCase))
        {
            for (int index = 0; index < configuration.Bindings.Count; index++)
            {
                LinuxTrackpadBinding binding = configuration.Bindings[index];
                if (binding.Side == TrackpadSide.Left)
                {
                    return binding.Device.DeviceNode;
                }
            }

            return null;
        }

        if (string.Equals(target, "right", StringComparison.OrdinalIgnoreCase))
        {
            for (int index = 0; index < configuration.Bindings.Count; index++)
            {
                LinuxTrackpadBinding binding = configuration.Bindings[index];
                if (binding.Side == TrackpadSide.Right)
                {
                    return binding.Device.DeviceNode;
                }
            }

            return null;
        }

        for (int index = 0; index < configuration.Bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = configuration.Bindings[index];
            if (string.Equals(binding.Device.DeviceNode, target, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(binding.Device.StableId, target, StringComparison.OrdinalIgnoreCase))
            {
                return binding.Device.DeviceNode;
            }
        }

        return target;
    }

    private static int RunDoctor()
    {
        LinuxDoctorResult result = LinuxDoctorRunner.Run();
        Console.Write(result.Report);
        return result.Success ? 0 : 1;
    }

    private static bool TryHandOffHeadlessRuntimeToGui(out string? message, out bool success)
    {
        message = null;
        success = false;

        LinuxSystemdServiceController serviceController = new();
        LinuxBackgroundRuntimeController backgroundController = new();
        LinuxGuiHostController trayController = new();

        IReadOnlyList<LinuxSystemdServiceStatus> runningServices = serviceController.Query()
            .Where(static status => status.IsRunning)
            .ToArray();
        LinuxBackgroundRuntimeStatus backgroundStatus = backgroundController.Query();
        LinuxGuiHostStatus trayStatus = trayController.Query();

        if (runningServices.Count == 0 && !backgroundStatus.IsRunning)
        {
            return false;
        }

        if (!StopHeadlessRuntimeForGui(serviceController, backgroundController, runningServices, backgroundStatus, out string stopError))
        {
            message = stopError;
            success = false;
            return true;
        }

        if (!LinuxGuiLauncher.TryShowConfig())
        {
            message = "Stopped the headless runtime, but could not launch the GlassToKey tray host.";
            success = false;
            return true;
        }

        message = trayStatus.IsRunning
            ? "Stopped the headless runtime and opening the existing GlassToKey tray host."
            : "Stopped the headless runtime and launching the GlassToKey tray host.";
        success = true;
        return true;
    }

    private static bool StopHeadlessRuntimeForGui(
        LinuxSystemdServiceController serviceController,
        LinuxBackgroundRuntimeController backgroundController,
        IReadOnlyList<LinuxSystemdServiceStatus> runningServices,
        LinuxBackgroundRuntimeStatus backgroundStatus,
        out string error)
    {
        error = string.Empty;

        if (runningServices.Count > 0)
        {
            IReadOnlyList<LinuxSystemdServiceStatus> serviceStatuses = serviceController.StopAsync().GetAwaiter().GetResult();
            LinuxSystemdServiceStatus? stillRunning = serviceStatuses.FirstOrDefault(static status => status.IsRunning);
            if (stillRunning != null)
            {
                error = stillRunning.Message;
                return false;
            }
        }

        if (backgroundStatus.IsRunning)
        {
            LinuxBackgroundRuntimeStatus stoppedBackground = backgroundController.StopAsync().GetAwaiter().GetResult();
            if (stoppedBackground.IsRunning)
            {
                error = stoppedBackground.Message;
                return false;
            }
        }

        return true;
    }

    private static int InitConfig()
    {
        LinuxAppRuntime appRuntime = new();
        string path = appRuntime.InitializeSettings();
        Console.WriteLine($"Initialized Linux host settings at {path}");
        return 0;
    }

    private static int PrintKeymap()
    {
        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadConfiguration();

        Console.WriteLine("GlassToKey Linux Configuration");
        Console.WriteLine();
        Console.WriteLine("Runtime");
        Console.WriteLine($"  SettingsPath: {configuration.SettingsPath}");
        Console.WriteLine($"  LayoutPreset: {configuration.LayoutPreset.Name}");
        Console.WriteLine($"  KeymapPath: {configuration.Settings.KeymapPath ?? "(bundled default)"}");
        Console.WriteLine($"  KeymapRevision: {configuration.Settings.KeymapRevision}");
        Console.WriteLine();

        Console.WriteLine("Device Bindings");
        Console.WriteLine($"  SavedLeftStableId: {configuration.Settings.LeftTrackpadStableId ?? "(none)"}");
        Console.WriteLine($"  SavedRightStableId: {configuration.Settings.RightTrackpadStableId ?? "(none)"}");
        Console.WriteLine($"  ResolvedLeft: {FormatResolvedBinding(configuration.Bindings, TrackpadSide.Left)}");
        Console.WriteLine($"  ResolvedRight: {FormatResolvedBinding(configuration.Bindings, TrackpadSide.Right)}");

        if (configuration.Warnings.Count > 0)
        {
            Console.WriteLine();
            Console.WriteLine("Warnings");
            for (int index = 0; index < configuration.Warnings.Count; index++)
            {
                Console.WriteLine($"  - {configuration.Warnings[index]}");
            }
        }

        Console.WriteLine();
        Console.WriteLine("Keymap");
        Console.WriteLine("  Layer 0");
        PrintLayoutAscii(configuration, TrackpadSide.Left);
        PrintLayoutAscii(configuration, TrackpadSide.Right);
        PrintCustomButtons(configuration, TrackpadSide.Left);
        PrintCustomButtons(configuration, TrackpadSide.Right);
        return 0;
    }

    private static string FormatResolvedBinding(IReadOnlyList<LinuxTrackpadBinding> bindings, TrackpadSide side)
    {
        LinuxTrackpadBinding? binding = bindings.FirstOrDefault(candidate => candidate.Side == side);
        if (binding == null)
        {
            return "(none)";
        }

        return $"{binding.Device.DisplayName} [{binding.Device.StableId}] @ {binding.Device.DeviceNode}";
    }

    private static void PrintLayoutAscii(LinuxRuntimeConfiguration configuration, TrackpadSide side)
    {
        const int layer = 0;
        ColumnLayoutSettings[] columns = RuntimeConfigurationFactory.BuildColumnSettingsForPreset(configuration.SharedProfile, configuration.LayoutPreset);
        RuntimeConfigurationFactory.BuildLayouts(
            configuration.SharedProfile,
            configuration.Keymap,
            configuration.LayoutPreset,
            columns,
            out KeyLayout leftLayout,
            out KeyLayout rightLayout);

        KeyLayout layout = side == TrackpadSide.Left ? leftLayout : rightLayout;
        Console.WriteLine($"  {side}");
        string rendered = RenderLayoutAscii(layout, configuration.Keymap, side, layer);
        string[] lines = rendered.Split(Environment.NewLine, StringSplitOptions.None);
        for (int index = 0; index < lines.Length; index++)
        {
            Console.WriteLine($"    {lines[index]}");
        }
    }

    private static void PrintCustomButtons(LinuxRuntimeConfiguration configuration, TrackpadSide side)
    {
        const int layer = 0;
        IReadOnlyList<CustomButton> buttons = configuration.Keymap.ResolveCustomButtons(layer, side);
        if (buttons.Count == 0)
        {
            return;
        }

        Console.WriteLine($"  {side} Custom Buttons");
        for (int index = 0; index < buttons.Count; index++)
        {
            CustomButton button = buttons[index];
            string label = string.IsNullOrWhiteSpace(button.Primary?.Label) ? "None" : button.Primary.Label.Trim();
            Console.WriteLine($"    - {label} [{button.Id}]");
        }
    }

    private static string RenderLayoutAscii(KeyLayout layout, KeymapStore keymap, TrackpadSide side, int layer)
    {
        if (layout.Labels.Length == 0)
        {
            return "(no keys)";
        }

        int cellWidth = DetermineCellWidth(layout, keymap, side, layer);
        StringBuilder builder = new();
        for (int row = 0; row < layout.Labels.Length; row++)
        {
            string[] rowLabels = layout.Labels[row];
            string border = BuildAsciiBorder(rowLabels.Length, cellWidth);
            builder.AppendLine(border);
            builder.Append('|');
            for (int col = 0; col < rowLabels.Length; col++)
            {
                string storageKey = GridKeyPosition.StorageKey(side, row, col);
                KeyMapping mapping = keymap.ResolveMapping(layer, storageKey, rowLabels[col]);
                string label = NormalizeCellLabel(mapping.Primary?.Label, rowLabels[col]);
                builder.Append(' ');
                builder.Append(label.PadRight(cellWidth));
                builder.Append(" |");
            }

            builder.AppendLine();
        }

        builder.Append(BuildAsciiBorder(layout.Labels[^1].Length, cellWidth));
        return builder.ToString();
    }

    private static int DetermineCellWidth(KeyLayout layout, KeymapStore keymap, TrackpadSide side, int layer)
    {
        int maxWidth = 4;
        for (int row = 0; row < layout.Labels.Length; row++)
        {
            string[] rowLabels = layout.Labels[row];
            for (int col = 0; col < rowLabels.Length; col++)
            {
                string storageKey = GridKeyPosition.StorageKey(side, row, col);
                KeyMapping mapping = keymap.ResolveMapping(layer, storageKey, rowLabels[col]);
                string label = NormalizeCellLabel(mapping.Primary?.Label, rowLabels[col]);
                maxWidth = Math.Max(maxWidth, label.Length);
            }
        }

        return Math.Clamp(maxWidth, 4, 12);
    }

    private static string BuildAsciiBorder(int columnCount, int cellWidth)
    {
        StringBuilder builder = new();
        for (int col = 0; col < columnCount; col++)
        {
            builder.Append('+');
            builder.Append(new string('-', cellWidth + 2));
        }

        builder.Append('+');
        return builder.ToString();
    }

    private static string NormalizeCellLabel(string? label, string fallback)
    {
        string text = string.IsNullOrWhiteSpace(label) ? fallback : label.Trim();
        text = text.Replace('\r', ' ').Replace('\n', ' ');
        if (text.Length <= 12)
        {
            return text;
        }

        return $"{text[..9]}...";
    }

    private static int BindTrackpad(string[] args, TrackpadSide side)
    {
        if (args.Length < 2 || string.IsNullOrWhiteSpace(args[1]))
        {
            Console.Error.WriteLine($"Usage: {CliName} {(side == TrackpadSide.Left ? "bind-left" : "bind-right")} [device-node-or-stable-id]");
            return 1;
        }

        LinuxAppRuntime appRuntime = new();
        if (!appRuntime.TryBindTrackpad(side, args[1], out string message))
        {
            Console.Error.WriteLine(message);
            return 1;
        }

        Console.WriteLine(message);
        return 0;
    }

    private static int SwapSides()
    {
        LinuxAppRuntime appRuntime = new();
        string path = appRuntime.SwapTrackpadBindings();
        Console.WriteLine($"Swapped left/right trackpad bindings in {path}");
        return 0;
    }

    private static int PrintUdevRules()
    {
        LinuxTrackpadEnumerator enumerator = new();
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = enumerator.EnumerateDevices();
        Console.Write(LinuxUdevRuleTemplate.BuildRules(devices));
        return 0;
    }

    private static int LoadKeymap(string[] args)
    {
        if (args.Length < 2 || string.IsNullOrWhiteSpace(args[1]))
        {
            Console.Error.WriteLine($"Usage: {CliName} load-keymap [path-to-keymap.json]");
            return 1;
        }

        LinuxAppRuntime appRuntime = new();
        if (!appRuntime.TryLoadKeymap(args[1], out string message))
        {
            Console.Error.WriteLine(message);
            return 1;
        }

        Console.WriteLine(message);
        return 0;
    }

    private static int RunSelfTest()
    {
        LinuxSelfTestResult result = LinuxSelfTestRunner.Run();
        if (result.Success)
        {
            Console.WriteLine(result.Message);
            return 0;
        }

        Console.Error.WriteLine(result.Message);
        return 1;
    }

    private static async Task<int> CaptureAtpCapAsync(string[] args)
    {
        string outputPath = args.Length >= 2 && !string.IsNullOrWhiteSpace(args[1])
            ? Path.GetFullPath(args[1])
            : Path.GetFullPath($"capture-{DateTime.UtcNow:yyyyMMdd-HHmmss}.atpcap");
        double seconds = args.Length >= 3 && double.TryParse(args[2], out double parsedSeconds)
            ? parsedSeconds
            : 10.0;
        if (seconds <= 0)
        {
            Console.Error.WriteLine("Duration must be positive.");
            return 1;
        }

        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadConfiguration();
        if (configuration.Bindings.Count == 0)
        {
            Console.Error.WriteLine("No trackpads available for capture.");
            return 1;
        }

        List<LinuxTrackpadBinding> bindings = [.. configuration.Bindings];
        using CancellationTokenSource cts = new(TimeSpan.FromSeconds(seconds));
        using LinuxAtpCapCaptureWriter writer = new(outputPath);
        LinuxInputRuntimeService runtime = new();
        LinuxInputRuntimeOptions options = new()
        {
            Observer = new ConsoleRuntimeObserver()
        };

        Console.WriteLine($"Capturing .atpcap for {seconds:0.##}s to {outputPath}");
        for (int index = 0; index < bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = bindings[index];
            Console.WriteLine($"  {binding.Side}: {binding.Device.DisplayName} [{binding.Device.DeviceNode}]");
        }

        CaptureFrameSink sink = new(writer);
        await runtime.RunAsync(bindings, sink, options, cts.Token).ConfigureAwait(false);
        Console.WriteLine($"Capture written: {outputPath}");
        return 0;
    }

    private static int ReplayAtpCap(string[] args)
    {
        if (args.Length < 2 || string.IsNullOrWhiteSpace(args[1]))
        {
            Console.Error.WriteLine($"Usage: {CliName} replay-atpcap [capture-path] [trace-output]");
            return 1;
        }

        string capturePath = Path.GetFullPath(args[1]);
        string? traceOutputPath = args.Length >= 3 && !string.IsNullOrWhiteSpace(args[2])
            ? Path.GetFullPath(args[2])
            : null;

        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadReplayConfiguration();
        LinuxAtpCapReplayResult result = LinuxAtpCapReplayRunner.Replay(capturePath, configuration, traceOutputPath);
        if (result.Success)
        {
            Console.WriteLine(result.Summary);
            if (!string.IsNullOrWhiteSpace(traceOutputPath))
            {
                Console.WriteLine($"Replay trace written: {traceOutputPath}");
            }

            return 0;
        }

        Console.Error.WriteLine(result.Summary);
        return 1;
    }

    private static int SummarizeAtpCap(string[] args)
    {
        if (args.Length < 2 || string.IsNullOrWhiteSpace(args[1]))
        {
            Console.Error.WriteLine($"Usage: {CliName} summarize-atpcap [capture-path]");
            return 1;
        }

        LinuxAtpCapSummaryResult result = LinuxAtpCapReplayRunner.Summarize(args[1]);
        if (result.Success)
        {
            Console.WriteLine(result.Summary);
            return 0;
        }

        Console.Error.WriteLine(result.Summary);
        return 1;
    }

    private static int WriteAtpCapFixture(string[] args)
    {
        if (args.Length < 2 || string.IsNullOrWhiteSpace(args[1]))
        {
            Console.Error.WriteLine($"Usage: {CliName} write-atpcap-fixture [capture-path] [fixture-path]");
            return 1;
        }

        string capturePath = Path.GetFullPath(args[1]);
        string fixturePath = args.Length >= 3 && !string.IsNullOrWhiteSpace(args[2])
            ? Path.GetFullPath(args[2])
            : Path.ChangeExtension(capturePath, ".fixture.json");

        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadReplayConfiguration();
        LinuxAtpCapFixtureWriteResult result = LinuxAtpCapFixtureRunner.WriteFixture(capturePath, fixturePath, configuration);
        if (result.Success)
        {
            Console.WriteLine(result.Summary);
            return 0;
        }

        Console.Error.WriteLine(result.Summary);
        return 1;
    }

    private static int CheckAtpCapFixture(string[] args)
    {
        if (args.Length < 3 || string.IsNullOrWhiteSpace(args[1]) || string.IsNullOrWhiteSpace(args[2]))
        {
            Console.Error.WriteLine($"Usage: {CliName} check-atpcap-fixture [capture-path] [fixture-path] [trace-output]");
            return 1;
        }

        string capturePath = Path.GetFullPath(args[1]);
        string fixturePath = Path.GetFullPath(args[2]);
        string? traceOutputPath = args.Length >= 4 && !string.IsNullOrWhiteSpace(args[3])
            ? Path.GetFullPath(args[3])
            : null;

        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadReplayConfiguration();
        LinuxAtpCapFixtureCheckResult result = LinuxAtpCapFixtureRunner.CheckFixture(capturePath, fixturePath, configuration, traceOutputPath);
        if (result.Success)
        {
            Console.WriteLine(result.Summary);
            if (!string.IsNullOrWhiteSpace(traceOutputPath))
            {
                Console.WriteLine($"Replay trace written: {traceOutputPath}");
            }

            return 0;
        }

        Console.Error.WriteLine(result.Summary);
        return 1;
    }

    private static int SmokeUinput(string[] args)
    {
        string[] tokens = args.Length >= 2 ? args[1..] : ["A"];
        using LinuxUinputDispatcher dispatcher = new();
        for (int index = 0; index < tokens.Length; index++)
        {
            string token = tokens[index];
            if (!TryResolveSmokeKey(token, out ushort virtualKey, out DispatchSemanticCode semanticCode, out string description))
            {
                Console.Error.WriteLine($"Unsupported smoke token '{token}'.");
                Console.Error.WriteLine("Supported examples: A, Enter, Space, Backspace, Left, Right, Up, Down, 0x41");
                return 1;
            }

            DispatchEvent dispatchEvent = new(
                TimestampTicks: Stopwatch.GetTimestamp(),
                Kind: DispatchEventKind.KeyTap,
                VirtualKey: virtualKey,
                MouseButton: DispatchMouseButton.None,
                RepeatToken: 0,
                Flags: DispatchEventFlags.None,
                Side: TrackpadSide.Left,
                DispatchLabel: description,
                SemanticAction: new DispatchSemanticAction(DispatchSemanticKind.Key, description, semanticCode));
            dispatcher.Dispatch(in dispatchEvent);
            dispatcher.Tick(Stopwatch.GetTimestamp());
            Thread.Sleep(index == tokens.Length - 1 ? 120 : 60);
            Console.WriteLine($"Injected '{description}' through uinput.");
        }

        return 0;
    }

    private static bool TryResolveSmokeKey(
        string token,
        out ushort virtualKey,
        out DispatchSemanticCode semanticCode,
        out string description)
    {
        virtualKey = 0;
        semanticCode = DispatchSemanticCode.None;
        description = string.Empty;
        if (string.IsNullOrWhiteSpace(token))
        {
            return false;
        }

        string trimmed = token.Trim();
        if (trimmed.Length == 1)
        {
            char ch = trimmed[0];
            if (ch >= 'a' && ch <= 'z')
            {
                virtualKey = (ushort)(ch - 'a' + 0x41);
                semanticCode = (DispatchSemanticCode)((int)DispatchSemanticCode.A + (ch - 'a'));
                description = ch.ToString().ToUpperInvariant();
                return true;
            }

            if (ch >= 'A' && ch <= 'Z')
            {
                virtualKey = (ushort)(ch - 'A' + 0x41);
                semanticCode = (DispatchSemanticCode)((int)DispatchSemanticCode.A + (ch - 'A'));
                description = ch.ToString();
                return true;
            }

            if (ch >= '0' && ch <= '9')
            {
                virtualKey = (ushort)(ch - '0' + 0x30);
                semanticCode = (DispatchSemanticCode)((int)DispatchSemanticCode.Digit0 + (ch - '0'));
                description = ch.ToString();
                return true;
            }
        }

        if ((trimmed.StartsWith("0x", StringComparison.OrdinalIgnoreCase) &&
             ushort.TryParse(trimmed.AsSpan(2), System.Globalization.NumberStyles.HexNumber, null, out virtualKey)) ||
            ushort.TryParse(trimmed, out virtualKey))
        {
            description = $"0x{virtualKey:x}";
            return true;
        }

        switch (trimmed.ToUpperInvariant())
        {
            case "SPACE":
                virtualKey = 0x20;
                semanticCode = DispatchSemanticCode.Space;
                description = "Space";
                return true;
            case "ENTER":
            case "RET":
                virtualKey = 0x0D;
                semanticCode = DispatchSemanticCode.Enter;
                description = "Enter";
                return true;
            case "TAB":
                virtualKey = 0x09;
                semanticCode = DispatchSemanticCode.Tab;
                description = "Tab";
                return true;
            case "ESC":
            case "ESCAPE":
                virtualKey = 0x1B;
                semanticCode = DispatchSemanticCode.Escape;
                description = "Escape";
                return true;
            case "BACK":
            case "BACKSPACE":
                virtualKey = 0x08;
                semanticCode = DispatchSemanticCode.Backspace;
                description = "Backspace";
                return true;
            case "LEFT":
                virtualKey = 0x25;
                semanticCode = DispatchSemanticCode.Left;
                description = "Left";
                return true;
            case "UP":
                virtualKey = 0x26;
                semanticCode = DispatchSemanticCode.Up;
                description = "Up";
                return true;
            case "RIGHT":
                virtualKey = 0x27;
                semanticCode = DispatchSemanticCode.Right;
                description = "Right";
                return true;
            case "DOWN":
                virtualKey = 0x28;
                semanticCode = DispatchSemanticCode.Down;
                description = "Down";
                return true;
            default:
                return false;
        }
    }

    private static async Task<int> WatchRuntimeAsync(string[] args)
    {
        double seconds = args.Length >= 2 && double.TryParse(args[1], out double parsedSeconds)
            ? parsedSeconds
            : 10.0;
        if (seconds <= 0)
        {
            Console.Error.WriteLine("Duration must be positive.");
            return 1;
        }

        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadConfiguration();
        if (configuration.Bindings.Count == 0)
        {
            Console.Error.WriteLine("No trackpads available for runtime watch.");
            return 1;
        }

        List<LinuxTrackpadBinding> bindings = [.. configuration.Bindings];

        using CancellationTokenSource cts = new(TimeSpan.FromSeconds(seconds));
        using PosixSignalRegistration sigTermRegistration = RegisterShutdownSignal(PosixSignal.SIGTERM, cts);
        using PosixSignalRegistration sigIntRegistration = RegisterShutdownSignal(PosixSignal.SIGINT, cts);
        LinuxInputRuntimeService runtime = new();
        Console.WriteLine($"Watching runtime for {seconds:0.##}s on {bindings.Count} trackpad(s).");
        Console.WriteLine($"  Settings: {configuration.SettingsPath}");
        for (int index = 0; index < bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = bindings[index];
            Console.WriteLine($"  {binding.Side}: {binding.Device.DisplayName} [{binding.Device.DeviceNode}]");
        }

        for (int index = 0; index < configuration.Warnings.Count; index++)
        {
            Console.WriteLine($"  Warning: {configuration.Warnings[index]}");
        }

        ConsoleTrackpadFrameTarget target = new();
        LinuxInputRuntimeOptions options = new()
        {
            Observer = new ConsoleRuntimeObserver()
        };
        await runtime.RunAsync(bindings, target, options, cts.Token).ConfigureAwait(false);
        return 0;
    }

    private static async Task<int> RunEngineAsync(string[] args)
    {
        bool disableExclusiveGrab = HasFlag(args, "--no-grab");
        TimeSpan? duration = null;
        string? durationToken = GetFirstPositionalArgument(args, startIndex: 1);
        if (!string.IsNullOrWhiteSpace(durationToken))
        {
            if (!double.TryParse(durationToken, out double parsedSeconds) || parsedSeconds <= 0)
            {
                Console.Error.WriteLine("Duration must be positive.");
                return 1;
            }

            duration = TimeSpan.FromSeconds(parsedSeconds);
        }

        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadConfiguration();
        using CancellationTokenSource cts = duration.HasValue
            ? new CancellationTokenSource(duration.Value)
            : new CancellationTokenSource();
        using PosixSignalRegistration sigTermRegistration = RegisterShutdownSignal(PosixSignal.SIGTERM, cts);
        using PosixSignalRegistration sigIntRegistration = RegisterShutdownSignal(PosixSignal.SIGINT, cts);
        LinuxRuntimeOwner runtimeOwner = new(
            appRuntime: appRuntime,
            policy: LinuxRuntimePolicy.HeadlessPureKeyboard,
            disableExclusiveGrab: disableExclusiveGrab);

        Console.WriteLine(duration.HasValue
            ? $"Running engine for {duration.Value.TotalSeconds:0.##}s."
            : "Running engine until interrupted.");
        Console.WriteLine($"  Settings: {configuration.SettingsPath}");
        Console.WriteLine($"  LayoutPreset: {configuration.LayoutPreset.Name}");
        Console.WriteLine($"  KeymapPath: {configuration.Settings.KeymapPath ?? "(bundled default)"}");
        for (int index = 0; index < configuration.Bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = configuration.Bindings[index];
            Console.WriteLine($"  {binding.Side}: {binding.Device.DisplayName} [{binding.Device.DeviceNode}]");
        }

        for (int index = 0; index < configuration.Warnings.Count; index++)
        {
            Console.WriteLine($"  Warning: {configuration.Warnings[index]}");
        }

        await runtimeOwner.RunAsync(new ConsoleRuntimeObserver(), Console.WriteLine, cts.Token).ConfigureAwait(false);
        return 0;
    }

    private static async Task<int> StartBackgroundRuntimeAsync(string[] args)
    {
        bool disableExclusiveGrab = HasFlag(args, "--no-grab");
        LinuxSystemdServiceController serviceController = new();
        IReadOnlyList<LinuxSystemdServiceStatus> runningServices = serviceController.Query()
            .Where(static serviceStatus => serviceStatus.IsRunning)
            .ToArray();
        if (runningServices.Count > 0)
        {
            Console.WriteLine("GlassToKey is already running through a user service.");
            foreach (LinuxSystemdServiceStatus serviceStatus in runningServices)
            {
                Console.WriteLine($"  Service: {serviceStatus.UnitName}{FormatProcessId(serviceStatus.ProcessId)}");
            }

            return 0;
        }

        LinuxGuiHostController trayController = new();
        LinuxGuiHostStatus trayStatus = trayController.Query();
        if (trayStatus.IsRunning && trayStatus.OwnsRuntime)
        {
            Console.WriteLine("GlassToKey is already running in the tray.");
            if (trayStatus.ProcessId.HasValue)
            {
                Console.WriteLine($"  Tray PID: {trayStatus.ProcessId.Value}");
            }

            return 0;
        }

        LinuxBackgroundRuntimeController controller = new();
        LinuxBackgroundRuntimeStatus status = await controller.StartAsync(disableExclusiveGrab).ConfigureAwait(false);
        Console.WriteLine(status.Message);
        if (status.IsRunning)
        {
            Console.WriteLine($"  MarkerPath: {status.MarkerPath}");
        }

        return status.IsRunning ? 0 : 1;
    }

    private static async Task<int> StopBackgroundRuntimeAsync()
    {
        LinuxSystemdServiceController serviceController = new();
        LinuxBackgroundRuntimeController backgroundController = new();
        LinuxGuiHostController trayController = new();

        IReadOnlyList<LinuxSystemdServiceStatus> currentServices = serviceController.Query()
            .Where(static serviceStatus => serviceStatus.IsRunning)
            .ToArray();
        LinuxBackgroundRuntimeStatus currentBackground = backgroundController.Query();
        LinuxGuiHostStatus currentTray = trayController.Query();
        if (currentServices.Count == 0 && !currentBackground.IsRunning && !currentTray.IsRunning)
        {
            Console.WriteLine("GlassToKey is not running.");
            return 0;
        }

        bool success = true;

        if (currentServices.Count > 0)
        {
            IReadOnlyList<LinuxSystemdServiceStatus> serviceStatuses = await serviceController.StopAsync().ConfigureAwait(false);
            foreach (LinuxSystemdServiceStatus status in serviceStatuses)
            {
                Console.WriteLine(status.Message);
                if (status.IsRunning)
                {
                    success = false;
                }
            }
        }
        else
        {
            Console.WriteLine("No GlassToKey user service is running.");
        }

        if (currentBackground.IsRunning)
        {
            LinuxBackgroundRuntimeStatus backgroundStatus = await backgroundController.StopAsync().ConfigureAwait(false);
            Console.WriteLine(backgroundStatus.Message);
            if (backgroundStatus.IsRunning)
            {
                success = false;
            }
        }
        else
        {
            Console.WriteLine("The background runtime is not running.");
        }

        if (currentTray.IsRunning)
        {
            LinuxGuiHostStatus trayStatus = await trayController.StopAsync().ConfigureAwait(false);
            Console.WriteLine(trayStatus.Message);
            if (trayStatus.IsRunning)
            {
                success = false;
            }
        }
        else
        {
            Console.WriteLine("The tray host is not running.");
        }

        return success ? 0 : 1;
    }

    private static async Task<int> RunBackgroundAsync(string[] args)
    {
        bool disableExclusiveGrab = HasFlag(args, "--no-grab");
        LinuxBackgroundRuntimeController controller = new();
        LinuxRuntimeOwner runtimeOwner = new(
            policy: LinuxRuntimePolicy.HeadlessPureKeyboard,
            disableExclusiveGrab: disableExclusiveGrab);
        return await controller.RunBackgroundAsync(runtimeOwner).ConfigureAwait(false);
    }

    private static bool HasFlag(string[] args, string flag)
    {
        for (int index = 1; index < args.Length; index++)
        {
            if (string.Equals(args[index], flag, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static string? GetFirstPositionalArgument(string[] args, int startIndex)
    {
        for (int index = startIndex; index < args.Length; index++)
        {
            if (!args[index].StartsWith("-", StringComparison.Ordinal))
            {
                return args[index];
            }
        }

        return null;
    }

    private static PosixSignalRegistration RegisterShutdownSignal(PosixSignal signal, CancellationTokenSource cts)
    {
        return PosixSignalRegistration.Create(signal, context =>
        {
            context.Cancel = true;
            if (!cts.IsCancellationRequested)
            {
                cts.Cancel();
            }
        });
    }

    private static string FormatProcessId(int? processId)
    {
        return processId.HasValue ? $" (PID {processId.Value})" : string.Empty;
    }

    private sealed class ConsoleTrackpadFrameTarget : ITrackpadFrameTarget
    {
        public bool Post(in TrackpadFrameEnvelope frame)
        {
            Console.WriteLine(
                $"{frame.Side}: contacts={frame.Frame.ContactCount} button={frame.Frame.IsButtonPressed} max=({frame.MaxX},{frame.MaxY}) ts={frame.TimestampTicks}");
            return true;
        }
    }

    private sealed class CaptureFrameSink : ILinuxInputFrameSink
    {
        private readonly LinuxAtpCapCaptureWriter _writer;

        public CaptureFrameSink(LinuxAtpCapCaptureWriter writer)
        {
            _writer = writer;
        }

        public ValueTask OnFrameAsync(LinuxRuntimeFrame frame, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _writer.WriteFrame(in frame);
            return ValueTask.CompletedTask;
        }
    }

    private sealed class ConsoleRuntimeObserver : ILinuxRuntimeObserver
    {
        public void OnBindingStateChanged(LinuxRuntimeBindingState state)
        {
            Console.WriteLine($"[{state.Side}] {state.Status}: {state.StableId} ({state.DeviceNode ?? "no-node"}) - {state.Message}");
        }
    }
}
