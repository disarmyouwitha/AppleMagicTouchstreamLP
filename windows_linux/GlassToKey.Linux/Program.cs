using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Models;

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
    }
}
