using Microsoft.Win32.SafeHandles;
using System.Globalization;
using System.Runtime.InteropServices;
using GlassToKey.Platform.Linux.Devices;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux.Haptics;

public sealed record LinuxMagicTrackpadActuatorProbeResult(
    string TouchHint,
    string? TouchDeviceNode,
    string? HidrawDeviceNode,
    string? InterfaceName,
    bool Supported,
    int OutputReportBytes,
    bool CanOpenWrite,
    string Status);

public static class LinuxMagicTrackpadActuatorProbe
{
    private const byte HapticOutputReportId = 0x53;
    private const string PreferredInterfaceName = "Actuator";

    public static LinuxMagicTrackpadActuatorProbeResult Probe(string? touchDeviceHint)
    {
        string hint = touchDeviceHint ?? string.Empty;
        if (string.IsNullOrWhiteSpace(hint))
        {
            return new LinuxMagicTrackpadActuatorProbeResult(
                TouchHint: hint,
                TouchDeviceNode: null,
                HidrawDeviceNode: null,
                InterfaceName: null,
                Supported: false,
                OutputReportBytes: 0,
                CanOpenWrite: false,
                Status: "No trackpad route is configured.");
        }

        try
        {
            string? touchDeviceNode = ResolveTouchDeviceNode(hint);
            if (string.IsNullOrWhiteSpace(touchDeviceNode))
            {
                return new LinuxMagicTrackpadActuatorProbeResult(
                    TouchHint: hint,
                    TouchDeviceNode: null,
                    HidrawDeviceNode: null,
                    InterfaceName: null,
                    Supported: false,
                    OutputReportBytes: 0,
                    CanOpenWrite: false,
                    Status: "The touch event node could not be resolved from the current Linux bindings.");
            }

            string? inputDevicePath = ResolveInputDevicePath(touchDeviceNode);
            if (string.IsNullOrWhiteSpace(inputDevicePath))
            {
                return new LinuxMagicTrackpadActuatorProbeResult(
                    TouchHint: hint,
                    TouchDeviceNode: touchDeviceNode,
                    HidrawDeviceNode: null,
                    InterfaceName: null,
                    Supported: false,
                    OutputReportBytes: 0,
                    CanOpenWrite: false,
                    Status: "The touch event node is not present in /sys/class/input.");
            }

            string? hidDevicePath = TryResolveExistingPath(Path.Combine(inputDevicePath, "device")) ??
                FindAncestorContainingFile(inputDevicePath, "report_descriptor");
            if (string.IsNullOrWhiteSpace(hidDevicePath))
            {
                return new LinuxMagicTrackpadActuatorProbeResult(
                    TouchHint: hint,
                    TouchDeviceNode: touchDeviceNode,
                    HidrawDeviceNode: null,
                    InterfaceName: null,
                    Supported: false,
                    OutputReportBytes: 0,
                    CanOpenWrite: false,
                    Status: "The touch event node did not resolve to a HID device path.");
            }

            string? interfacePath = Directory.GetParent(hidDevicePath)?.FullName;
            if (string.IsNullOrWhiteSpace(interfacePath))
            {
                return new LinuxMagicTrackpadActuatorProbeResult(
                    TouchHint: hint,
                    TouchDeviceNode: touchDeviceNode,
                    HidrawDeviceNode: null,
                    InterfaceName: null,
                    Supported: false,
                    OutputReportBytes: 0,
                    CanOpenWrite: false,
                    Status: "The touch HID interface path did not resolve to a USB interface node.");
            }

            string? transportPath = Directory.GetParent(interfacePath)?.FullName;
            if (string.IsNullOrWhiteSpace(transportPath))
            {
                return new LinuxMagicTrackpadActuatorProbeResult(
                    TouchHint: hint,
                    TouchDeviceNode: touchDeviceNode,
                    HidrawDeviceNode: null,
                    InterfaceName: null,
                    Supported: false,
                    OutputReportBytes: 0,
                    CanOpenWrite: false,
                    Status: "The touch USB interface path did not resolve to a physical device node.");
            }

            foreach (string siblingInterfacePath in EnumerateSiblingUsbInterfacePaths(interfacePath, transportPath))
            {
                string interfaceName = ReadTrimmed(Path.Combine(siblingInterfacePath, "interface"));
                if (!string.Equals(interfaceName, PreferredInterfaceName, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                return CreateProbeResultFromInterface(hint, touchDeviceNode, siblingInterfacePath, interfaceName);
            }

            if (TryCreateProbeResult(
                    hint,
                    touchDeviceNode,
                    hidDevicePath,
                    ResolveInterfaceName(hidDevicePath),
                    out LinuxMagicTrackpadActuatorProbeResult currentInterfaceResult))
            {
                return currentInterfaceResult;
            }

            return new LinuxMagicTrackpadActuatorProbeResult(
                TouchHint: hint,
                TouchDeviceNode: touchDeviceNode,
                HidrawDeviceNode: null,
                InterfaceName: null,
                Supported: false,
                OutputReportBytes: 0,
                CanOpenWrite: false,
                Status: "No matching actuator HID interface was found for this trackpad on Linux.");
        }
        catch (Exception ex)
        {
            return new LinuxMagicTrackpadActuatorProbeResult(
                TouchHint: hint,
                TouchDeviceNode: null,
                HidrawDeviceNode: null,
                InterfaceName: null,
                Supported: false,
                OutputReportBytes: 0,
                CanOpenWrite: false,
                Status: $"{ex.GetType().Name}: {ex.Message}");
        }
    }

    private static IEnumerable<string> EnumerateSiblingUsbInterfacePaths(string interfacePath, string transportPath)
    {
        _ = interfacePath;
        string transportNodeName = Path.GetFileName(transportPath);
        string prefix = transportNodeName + ":";
        foreach (string path in Directory.EnumerateDirectories(transportPath))
        {
            string fileName = Path.GetFileName(path);
            if (!fileName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            yield return path;
        }
    }

    private static IEnumerable<string> EnumerateChildHidDevicePaths(string interfacePath)
    {
        foreach (string path in Directory.EnumerateDirectories(interfacePath))
        {
            if (File.Exists(Path.Combine(path, "report_descriptor")))
            {
                yield return path;
            }
        }
    }

    private static LinuxMagicTrackpadActuatorProbeResult CreateProbeResultFromInterface(
        string touchHint,
        string touchDeviceNode,
        string interfacePath,
        string interfaceName)
    {
        foreach (string candidateHidPath in EnumerateChildHidDevicePaths(interfacePath))
        {
            int outputReportBytes = 64;
            try
            {
                byte[] descriptor = File.ReadAllBytes(Path.Combine(candidateHidPath, "report_descriptor"));
                if (!TryParseActuatorOutputReportLength(descriptor, out outputReportBytes))
                {
                    outputReportBytes = 64;
                }
            }
            catch
            {
                outputReportBytes = 64;
            }

            string? hidrawDeviceNode = ResolveHidrawDeviceNode(candidateHidPath);
            if (string.IsNullOrWhiteSpace(hidrawDeviceNode))
            {
                continue;
            }

            (bool canOpenWrite, string accessError) = ProbeWriteAccess(hidrawDeviceNode);
            return new LinuxMagicTrackpadActuatorProbeResult(
                TouchHint: touchHint,
                TouchDeviceNode: touchDeviceNode,
                HidrawDeviceNode: hidrawDeviceNode,
                InterfaceName: interfaceName,
                Supported: true,
                OutputReportBytes: outputReportBytes,
                CanOpenWrite: canOpenWrite,
                Status: canOpenWrite ? "ok" : accessError);
        }

        return new LinuxMagicTrackpadActuatorProbeResult(
            TouchHint: touchHint,
            TouchDeviceNode: touchDeviceNode,
            HidrawDeviceNode: null,
            InterfaceName: interfaceName,
            Supported: false,
            OutputReportBytes: 0,
            CanOpenWrite: false,
            Status: "The actuator USB interface exists, but no writable hidraw node was resolved for it.");
    }

    public static bool TryParseActuatorOutputReportLength(ReadOnlySpan<byte> reportDescriptor, out int outputReportBytes)
    {
        outputReportBytes = 0;
        if (reportDescriptor.IsEmpty)
        {
            return false;
        }

        ushort usagePage = 0;
        uint lastUsage = 0;
        byte reportId = 0;
        int reportSizeBits = 0;
        int reportCount = 0;
        bool localActuatorUsage = false;
        bool currentActuatorCollection = false;
        bool[] collectionStack = new bool[16];
        int collectionDepth = 0;

        for (int index = 0; index < reportDescriptor.Length;)
        {
            byte prefix = reportDescriptor[index++];
            if (prefix == 0xFE)
            {
                if (index + 1 >= reportDescriptor.Length)
                {
                    return false;
                }

                int longDataSize = reportDescriptor[index];
                index += 2 + longDataSize;
                continue;
            }

            int sizeCode = prefix & 0x03;
            int dataSize = sizeCode == 3 ? 4 : sizeCode;
            if (index + dataSize > reportDescriptor.Length)
            {
                return false;
            }

            int itemType = (prefix >> 2) & 0x03;
            int itemTag = (prefix >> 4) & 0x0F;
            uint data = ReadUnsigned(reportDescriptor.Slice(index, dataSize));
            index += dataSize;

            switch (itemType)
            {
                case 0x00:
                    switch (itemTag)
                    {
                        case 0x08:
                        case 0x0B:
                            localActuatorUsage = false;
                            break;
                        case 0x09:
                            if (currentActuatorCollection &&
                                reportId == HapticOutputReportId &&
                                reportSizeBits > 0 &&
                                reportCount > 0)
                            {
                                outputReportBytes = 1 + ((reportSizeBits * reportCount + 7) / 8);
                                return outputReportBytes > 1;
                            }

                            localActuatorUsage = false;
                            break;
                        case 0x0A:
                            if (collectionDepth >= collectionStack.Length)
                            {
                                return false;
                            }

                            collectionStack[collectionDepth++] = currentActuatorCollection;
                            currentActuatorCollection = currentActuatorCollection ||
                                (usagePage == 0xFF00 && (localActuatorUsage || lastUsage == 0x0D));
                            localActuatorUsage = false;
                            break;
                        case 0x0C:
                            if (collectionDepth == 0)
                            {
                                return false;
                            }

                            currentActuatorCollection = collectionStack[--collectionDepth];
                            localActuatorUsage = false;
                            break;
                    }
                    break;
                case 0x01:
                    switch (itemTag)
                    {
                        case 0x00:
                            usagePage = (ushort)data;
                            break;
                        case 0x07:
                            reportSizeBits = (int)data;
                            break;
                        case 0x08:
                            reportId = (byte)data;
                            break;
                        case 0x09:
                            reportCount = (int)data;
                            break;
                    }
                    break;
                case 0x02:
                    if (itemTag == 0x00)
                    {
                        lastUsage = data;
                        if (usagePage == 0xFF00 && data == 0x0D)
                        {
                            localActuatorUsage = true;
                        }
                    }
                    break;
            }
        }

        return false;
    }

    private static string? ResolveTouchDeviceNode(string hint)
    {
        if (File.Exists(hint))
        {
            return TryResolveExistingPath(hint);
        }

        LinuxTrackpadEnumerator enumerator = new();
        IReadOnlyList<LinuxInputDeviceDescriptor> devices = enumerator.EnumerateDevices();
        for (int index = 0; index < devices.Count; index++)
        {
            LinuxInputDeviceDescriptor device = devices[index];
            if (string.Equals(device.StableId, hint, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(device.DeviceNode, hint, StringComparison.OrdinalIgnoreCase))
            {
                return device.DeviceNode;
            }
        }

        return null;
    }

    private static string? ResolveInputDevicePath(string touchDeviceNode)
    {
        string sysfsPath = Path.Combine("/sys/class/input", Path.GetFileName(touchDeviceNode), "device");
        return TryResolveExistingPath(sysfsPath);
    }

    private static IEnumerable<string> EnumerateActuatorHidDevicePaths()
    {
        if (!Directory.Exists("/sys/class/hidraw"))
        {
            yield break;
        }

        foreach (string hidrawPath in Directory.EnumerateFileSystemEntries("/sys/class/hidraw", "hidraw*"))
        {
            string? hidDevicePath = TryResolveExistingPath(Path.Combine(hidrawPath, "device"));
            if (!string.IsNullOrWhiteSpace(hidDevicePath))
            {
                yield return hidDevicePath;
            }
        }
    }

    private static bool TryReadHidIdentity(
        string hidDevicePath,
        out ushort vendorId,
        out ushort productId,
        out string uniqueId,
        out string physicalPath)
    {
        vendorId = 0;
        productId = 0;
        uniqueId = string.Empty;
        physicalPath = string.Empty;

        string uevent = ReadTrimmed(Path.Combine(hidDevicePath, "uevent"));
        if (string.IsNullOrWhiteSpace(uevent))
        {
            return false;
        }

        string[] lines = uevent.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        for (int index = 0; index < lines.Length; index++)
        {
            string line = lines[index];
            if (line.StartsWith("HID_ID=", StringComparison.Ordinal))
            {
                string[] parts = line["HID_ID=".Length..].Split(':', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                if (parts.Length >= 3)
                {
                    ushort.TryParse(parts[1], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out vendorId);
                    ushort.TryParse(parts[2], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out productId);
                }
            }
            else if (line.StartsWith("HID_UNIQ=", StringComparison.Ordinal))
            {
                uniqueId = line["HID_UNIQ=".Length..];
            }
            else if (line.StartsWith("HID_PHYS=", StringComparison.Ordinal))
            {
                physicalPath = line["HID_PHYS=".Length..];
            }
        }

        return vendorId != 0 || productId != 0 || !string.IsNullOrWhiteSpace(uniqueId) || !string.IsNullOrWhiteSpace(physicalPath);
    }

    private static bool MatchesTouchIdentity(
        ushort touchVendorId,
        ushort touchProductId,
        string touchUniqueId,
        string touchPhysicalPath,
        ushort candidateVendorId,
        ushort candidateProductId,
        string candidateUniqueId,
        string candidatePhysicalPath)
    {
        if (touchVendorId != candidateVendorId || touchProductId != candidateProductId)
        {
            return false;
        }

        if (!string.IsNullOrWhiteSpace(touchUniqueId) &&
            !string.IsNullOrWhiteSpace(candidateUniqueId))
        {
            return string.Equals(touchUniqueId, candidateUniqueId, StringComparison.OrdinalIgnoreCase);
        }

        if (!string.IsNullOrWhiteSpace(touchPhysicalPath) &&
            !string.IsNullOrWhiteSpace(candidatePhysicalPath))
        {
            return string.Equals(touchPhysicalPath, candidatePhysicalPath, StringComparison.OrdinalIgnoreCase);
        }

        return true;
    }

    private static string NormalizePhysicalPath(string physicalPath)
    {
        if (string.IsNullOrWhiteSpace(physicalPath))
        {
            return string.Empty;
        }

        int suffixIndex = physicalPath.LastIndexOf("/input", StringComparison.OrdinalIgnoreCase);
        if (suffixIndex > 0)
        {
            return physicalPath[..suffixIndex];
        }

        return physicalPath;
    }

    private static bool TryCreateProbeResult(
        string touchHint,
        string touchDeviceNode,
        string hidDevicePath,
        string? interfaceName,
        out LinuxMagicTrackpadActuatorProbeResult result)
    {
        result = new LinuxMagicTrackpadActuatorProbeResult(
            TouchHint: touchHint,
            TouchDeviceNode: touchDeviceNode,
            HidrawDeviceNode: null,
            InterfaceName: interfaceName,
            Supported: false,
            OutputReportBytes: 0,
            CanOpenWrite: false,
            Status: "No actuator HID interface found.");

        byte[] descriptor;
        try
        {
            descriptor = File.ReadAllBytes(Path.Combine(hidDevicePath, "report_descriptor"));
        }
        catch
        {
            return false;
        }

        bool descriptorMatched = TryParseActuatorOutputReportLength(descriptor, out int outputReportBytes);
        if (!descriptorMatched &&
            string.Equals(interfaceName, PreferredInterfaceName, StringComparison.OrdinalIgnoreCase))
        {
            outputReportBytes = 64;
            descriptorMatched = true;
        }

        if (!descriptorMatched)
        {
            return false;
        }

        string? hidrawDeviceNode = ResolveHidrawDeviceNode(hidDevicePath);
        if (string.IsNullOrWhiteSpace(hidrawDeviceNode))
        {
            result = result with
            {
                Supported = false,
                OutputReportBytes = outputReportBytes,
                Status = "The actuator HID interface exists, but its /dev/hidraw node is missing."
            };
            return true;
        }

        (bool canOpenWrite, string accessError) = ProbeWriteAccess(hidrawDeviceNode);
        result = new LinuxMagicTrackpadActuatorProbeResult(
            TouchHint: touchHint,
            TouchDeviceNode: touchDeviceNode,
            HidrawDeviceNode: hidrawDeviceNode,
            InterfaceName: interfaceName,
            Supported: true,
            OutputReportBytes: outputReportBytes,
            CanOpenWrite: canOpenWrite,
            Status: canOpenWrite ? "ok" : accessError);
        return true;
    }

    private static string? ResolveHidrawDeviceNode(string hidDevicePath)
    {
        string hidrawDirectory = Path.Combine(hidDevicePath, "hidraw");
        if (!Directory.Exists(hidrawDirectory))
        {
            return null;
        }

        foreach (string path in Directory.EnumerateFileSystemEntries(hidrawDirectory, "hidraw*"))
        {
            return Path.Combine("/dev", Path.GetFileName(path));
        }

        return null;
    }

    private static string? ResolveInterfaceName(string hidDevicePath)
    {
        DirectoryInfo? parent = Directory.GetParent(hidDevicePath);
        while (parent != null)
        {
            string interfaceName = ReadTrimmed(Path.Combine(parent.FullName, "interface"));
            if (!string.IsNullOrWhiteSpace(interfaceName))
            {
                return interfaceName;
            }

            parent = parent.Parent;
        }

        return null;
    }

    private static string? FindAncestorContainingFile(string startPath, string fileName)
    {
        DirectoryInfo? current = new(startPath);
        while (current != null)
        {
            if (File.Exists(Path.Combine(current.FullName, fileName)))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        return null;
    }

    private static (bool CanOpenWrite, string AccessError) ProbeWriteAccess(string hidrawDeviceNode)
    {
        try
        {
            using SafeFileHandle handle = File.OpenHandle(hidrawDeviceNode, FileMode.Open, FileAccess.Write, FileShare.ReadWrite);
            return (true, "ok");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    private static string? TryResolveExistingPath(string path)
    {
        try
        {
            string? realPath = TryGetRealPath(path);
            if (!string.IsNullOrWhiteSpace(realPath))
            {
                return realPath;
            }

            bool isDirectory = Directory.Exists(path);
            bool isFile = File.Exists(path);
            if (!isDirectory && !isFile)
            {
                return null;
            }

            FileSystemInfo info = isDirectory
                ? new DirectoryInfo(path)
                : new FileInfo(path);
            if (!info.Exists)
            {
                return null;
            }

            if (info.LinkTarget != null)
            {
                FileSystemInfo? target = info.ResolveLinkTarget(returnFinalTarget: true);
                if (target != null)
                {
                    return target.FullName;
                }

                string linkTarget = info.LinkTarget;
                if (!Path.IsPathRooted(linkTarget))
                {
                    string? directory = Path.GetDirectoryName(info.FullName);
                    if (!string.IsNullOrWhiteSpace(directory))
                    {
                        string baseDirectory = directory;
                        string? resolvedDirectory = TryResolveExistingPath(directory);
                        if (!string.IsNullOrWhiteSpace(resolvedDirectory))
                        {
                            baseDirectory = resolvedDirectory;
                        }

                        string combined = Path.GetFullPath(Path.Combine(baseDirectory, linkTarget));
                        if (File.Exists(combined) || Directory.Exists(combined))
                        {
                            return combined;
                        }
                    }
                }
            }

            return info.FullName;
        }
        catch
        {
            return null;
        }
    }

    private static string? TryGetRealPath(string path)
    {
        IntPtr resolved = NativeMethods.RealPath(path, IntPtr.Zero);
        if (resolved == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            return Marshal.PtrToStringUTF8(resolved);
        }
        finally
        {
            NativeMethods.Free(resolved);
        }
    }

    private static ushort ReadHexUShort(string path)
    {
        string text = ReadTrimmed(path);
        if (ushort.TryParse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out ushort value))
        {
            return value;
        }

        return 0;
    }

    private static string ReadTrimmed(string path)
    {
        try
        {
            return File.ReadAllText(path).Trim();
        }
        catch
        {
            return string.Empty;
        }
    }

    private static uint ReadUnsigned(ReadOnlySpan<byte> data)
    {
        uint value = 0;
        for (int index = 0; index < data.Length; index++)
        {
            value |= (uint)data[index] << (8 * index);
        }

        return value;
    }

    private static class NativeMethods
    {
        [DllImport("libc", EntryPoint = "realpath", SetLastError = true)]
        public static extern IntPtr RealPath(string path, IntPtr resolvedPath);

        [DllImport("libc", EntryPoint = "free")]
        public static extern void Free(IntPtr pointer);
    }
}
