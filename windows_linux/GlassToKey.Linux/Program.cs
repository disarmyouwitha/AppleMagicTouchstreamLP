using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Evdev;
using GlassToKey.Platform.Linux.Models;
using GlassToKey.Platform.Linux.Contracts;
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

        if (string.Equals(args[0], "watch-runtime", StringComparison.OrdinalIgnoreCase))
        {
            return WatchRuntimeAsync(args).GetAwaiter().GetResult();
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
        Console.WriteLine("  GlassToKey.Linux watch-runtime [seconds]");
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

        LinuxTrackpadEnumerator enumerator = new();
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = enumerator.EnumerateDevices();
        if (devices.Count == 0)
        {
            Console.Error.WriteLine("No trackpads available for runtime watch.");
            return 1;
        }

        List<LinuxTrackpadBinding> bindings = [];
        if (devices.Count >= 1)
        {
            bindings.Add(new LinuxTrackpadBinding(TrackpadSide.Left, devices[0]));
        }

        if (devices.Count >= 2)
        {
            bindings.Add(new LinuxTrackpadBinding(TrackpadSide.Right, devices[1]));
        }

        using CancellationTokenSource cts = new(TimeSpan.FromSeconds(seconds));
        LinuxInputRuntimeService runtime = new();
        ConsoleRuntimeFrameSink sink = new();
        Console.WriteLine($"Watching runtime for {seconds:0.##}s on {bindings.Count} trackpad(s).");
        await runtime.RunAsync(bindings, sink, cts.Token).ConfigureAwait(false);
        return 0;
    }

    private sealed class ConsoleRuntimeFrameSink : ILinuxInputFrameSink
    {
        public ValueTask OnFrameAsync(LinuxRuntimeFrame frame, CancellationToken cancellationToken)
        {
            Console.WriteLine($"{frame.Binding.Side}: {frame.Binding.Device.DeviceNode} frame={frame.Snapshot.FrameSequence} contacts={frame.Snapshot.Frame.ContactCount} button={frame.Snapshot.Frame.IsButtonPressed}");
            return ValueTask.CompletedTask;
        }
    }
}
