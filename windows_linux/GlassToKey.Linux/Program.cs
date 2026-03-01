using System.Diagnostics;
using System.Threading;
using GlassToKey.Linux.Runtime;
using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Evdev;
using GlassToKey.Platform.Linux.Models;
using GlassToKey.Platform.Linux.Contracts;
using GlassToKey.Platform.Linux.Uinput;
using GlassToKey.Platform.Linux;

namespace GlassToKey.Linux;

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length == 0 || string.Equals(args[0], "list-devices", StringComparison.OrdinalIgnoreCase))
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

        if (string.Equals(args[0], "doctor", StringComparison.OrdinalIgnoreCase))
        {
            return RunDoctor();
        }

        if (string.Equals(args[0], "show-config", StringComparison.OrdinalIgnoreCase))
        {
            return ShowConfig();
        }

        if (string.Equals(args[0], "init-config", StringComparison.OrdinalIgnoreCase))
        {
            return InitConfig();
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
            Console.WriteLine("No multitouch trackpad candidates found.");
            return 0;
        }

        foreach (LinuxInputDeviceDescriptor device in devices)
        {
            Console.WriteLine(device.DisplayName);
            Console.WriteLine($"  Node: {device.DeviceNode}");
            Console.WriteLine($"  StableId: {device.StableId}");
            Console.WriteLine($"  Vendor/Product: 0x{device.VendorId:x4}/0x{device.ProductId:x4}");
            Console.WriteLine($"  Multitouch: {device.SupportsMultitouch}");
            Console.WriteLine($"  Pressure: {device.SupportsPressure}");
            Console.WriteLine($"  ButtonClick: {device.SupportsButtonClick}");
            Console.WriteLine($"  EventAccess: {(device.CanOpenEventStream ? "ok" : device.AccessError)}");
            Console.WriteLine();
        }

        return 0;
    }

    private static void PrintUsage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  GlassToKey.Linux list-devices");
        Console.WriteLine("  GlassToKey.Linux read-frames [device-node-or-stable-id] [seconds] [max-frames]");
        Console.WriteLine("  GlassToKey.Linux read-events [device-node-or-stable-id] [seconds] [max-events]");
        Console.WriteLine("  GlassToKey.Linux probe-axes [device-node-or-stable-id]");
        Console.WriteLine("  GlassToKey.Linux probe-uinput");
        Console.WriteLine("  GlassToKey.Linux doctor");
        Console.WriteLine("  GlassToKey.Linux show-config");
        Console.WriteLine("  GlassToKey.Linux init-config");
        Console.WriteLine("  GlassToKey.Linux bind-left [device-node-or-stable-id]");
        Console.WriteLine("  GlassToKey.Linux bind-right [device-node-or-stable-id]");
        Console.WriteLine("  GlassToKey.Linux swap-sides");
        Console.WriteLine("  GlassToKey.Linux print-udev-rules");
        Console.WriteLine("  GlassToKey.Linux selftest");
        Console.WriteLine("  GlassToKey.Linux capture-atpcap [output-path] [seconds]");
        Console.WriteLine("  GlassToKey.Linux replay-atpcap [capture-path] [trace-output]");
        Console.WriteLine("  GlassToKey.Linux summarize-atpcap [capture-path]");
        Console.WriteLine("  GlassToKey.Linux write-atpcap-fixture [capture-path] [fixture-path]");
        Console.WriteLine("  GlassToKey.Linux check-atpcap-fixture [capture-path] [fixture-path] [trace-output]");
        Console.WriteLine("  GlassToKey.Linux uinput-smoke [token]");
        Console.WriteLine("  GlassToKey.Linux watch-runtime [seconds]");
        Console.WriteLine("  GlassToKey.Linux run-engine [seconds]");
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
        Console.WriteLine($"  UsesMtPositionAxes: {profile.UsesMtPositionAxes}");
        Console.WriteLine($"  UsesLegacyPositionAxes: {profile.UsesLegacyPositionAxes}");
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

    private static int RunDoctor()
    {
        LinuxDoctorResult result = LinuxDoctorRunner.Run();
        Console.Write(result.Report);
        return result.Success ? 0 : 1;
    }

    private static int ShowConfig()
    {
        LinuxAppRuntime appRuntime = new();
        LinuxRuntimeConfiguration configuration = appRuntime.LoadConfiguration();

        Console.WriteLine("Linux host config");
        Console.WriteLine($"  SettingsPath: {configuration.SettingsPath}");
        Console.WriteLine($"  LayoutPreset: {configuration.LayoutPreset.Name}");
        Console.WriteLine($"  KeymapPath: {configuration.Settings.KeymapPath ?? "(bundled default)"}");
        Console.WriteLine($"  LeftTrackpadStableId: {configuration.Settings.LeftTrackpadStableId ?? "(auto)"}");
        Console.WriteLine($"  RightTrackpadStableId: {configuration.Settings.RightTrackpadStableId ?? "(auto)"}");
        Console.WriteLine($"  DevicesDetected: {configuration.Devices.Count}");
        Console.WriteLine($"  BindingsResolved: {configuration.Bindings.Count}");
        for (int index = 0; index < configuration.Bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = configuration.Bindings[index];
            Console.WriteLine($"    {binding.Side}: {binding.Device.DisplayName} [{binding.Device.DeviceNode}] stable={binding.Device.StableId}");
        }

        for (int index = 0; index < configuration.Warnings.Count; index++)
        {
            Console.WriteLine($"  Warning: {configuration.Warnings[index]}");
        }

        return 0;
    }

    private static int InitConfig()
    {
        LinuxAppRuntime appRuntime = new();
        string path = appRuntime.InitializeSettings();
        Console.WriteLine($"Initialized Linux host settings at {path}");
        return 0;
    }

    private static int BindTrackpad(string[] args, TrackpadSide side)
    {
        if (args.Length < 2 || string.IsNullOrWhiteSpace(args[1]))
        {
            Console.Error.WriteLine($"Usage: GlassToKey.Linux {(side == TrackpadSide.Left ? "bind-left" : "bind-right")} [device-node-or-stable-id]");
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

        Console.WriteLine($"Capturing .atpcap for {seconds:0.##}s to {outputPath}");
        for (int index = 0; index < bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = bindings[index];
            Console.WriteLine($"  {binding.Side}: {binding.Device.DisplayName} [{binding.Device.DeviceNode}]");
        }

        CaptureFrameSink sink = new(writer);
        await runtime.RunAsync(bindings, sink, cts.Token).ConfigureAwait(false);
        Console.WriteLine($"Capture written: {outputPath}");
        return 0;
    }

    private static int ReplayAtpCap(string[] args)
    {
        if (args.Length < 2 || string.IsNullOrWhiteSpace(args[1]))
        {
            Console.Error.WriteLine("Usage: GlassToKey.Linux replay-atpcap [capture-path] [trace-output]");
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
            Console.Error.WriteLine("Usage: GlassToKey.Linux summarize-atpcap [capture-path]");
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
            Console.Error.WriteLine("Usage: GlassToKey.Linux write-atpcap-fixture [capture-path] [fixture-path]");
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
            Console.Error.WriteLine("Usage: GlassToKey.Linux check-atpcap-fixture [capture-path] [fixture-path] [trace-output]");
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
        await runtime.RunAsync(bindings, target, cts.Token).ConfigureAwait(false);
        return 0;
    }

    private static async Task<int> RunEngineAsync(string[] args)
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
            Console.Error.WriteLine("No trackpads available for engine run.");
            return 1;
        }

        List<LinuxTrackpadBinding> bindings = [.. configuration.Bindings];
        using CancellationTokenSource cts = new(TimeSpan.FromSeconds(seconds));
        using LinuxUinputDispatcher dispatcher = new();
        using TouchProcessorRuntimeHost engine = new(dispatcher, configuration.Keymap, configuration.LayoutPreset);
        LinuxInputRuntimeService runtime = new();

        Console.WriteLine($"Running engine for {seconds:0.##}s on {bindings.Count} trackpad(s).");
        Console.WriteLine($"  Settings: {configuration.SettingsPath}");
        Console.WriteLine($"  LayoutPreset: {configuration.LayoutPreset.Name}");
        Console.WriteLine($"  KeymapPath: {configuration.Settings.KeymapPath ?? "(bundled default)"}");
        for (int index = 0; index < bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = bindings[index];
            Console.WriteLine($"  {binding.Side}: {binding.Device.DisplayName} [{binding.Device.DeviceNode}]");
        }

        for (int index = 0; index < configuration.Warnings.Count; index++)
        {
            Console.WriteLine($"  Warning: {configuration.Warnings[index]}");
        }

        await runtime.RunAsync(bindings, engine, cts.Token).ConfigureAwait(false);
        return 0;
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
}
