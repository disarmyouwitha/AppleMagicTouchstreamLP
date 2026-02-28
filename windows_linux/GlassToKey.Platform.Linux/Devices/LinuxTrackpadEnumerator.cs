using System.Globalization;
using GlassToKey.Platform.Linux.Contracts;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux.Devices;

public sealed class LinuxTrackpadEnumerator : ILinuxTrackpadBackend
{
    private const int BitsPerWord = sizeof(ulong) * 8;
    private const int EventTypeKey = 0x01;
    private const int EventTypeAbs = 0x03;
    private const int InputPropPointer = 0x00;
    private const int InputPropButtonPad = 0x02;
    private const int ButtonLeft = 0x110;
    private const int AbsMtSlot = 0x2f;
    private const int AbsMtPositionX = 0x35;
    private const int AbsMtPositionY = 0x36;
    private const int AbsMtTrackingId = 0x39;
    private const int AbsMtPressure = 0x3a;

    public IReadOnlyList<LinuxInputDeviceDescriptor> EnumerateDevices()
    {
        Dictionary<string, string> stableIdsByDeviceNode = BuildStableIdsByDeviceNode();
        List<LinuxInputDeviceDescriptor> devices = [];

        foreach (string eventPath in Directory.EnumerateDirectories("/sys/class/input", "event*"))
        {
            string eventName = Path.GetFileName(eventPath);
            string sysfsDevicePath = Path.Combine(eventPath, "device");
            string deviceNode = Path.Combine("/dev/input", eventName);

            string displayName = ReadTrimmed(Path.Combine(sysfsDevicePath, "name"));
            string capabilitiesEv = ReadTrimmed(Path.Combine(sysfsDevicePath, "capabilities", "ev"));
            string capabilitiesAbs = ReadTrimmed(Path.Combine(sysfsDevicePath, "capabilities", "abs"));
            string capabilitiesKey = ReadTrimmed(Path.Combine(sysfsDevicePath, "capabilities", "key"));
            string properties = ReadTrimmed(Path.Combine(sysfsDevicePath, "properties"));

            bool supportsMultitouch =
                HasBit(capabilitiesEv, EventTypeAbs) &&
                HasBit(capabilitiesAbs, AbsMtSlot) &&
                HasBit(capabilitiesAbs, AbsMtTrackingId) &&
                HasBit(capabilitiesAbs, AbsMtPositionX) &&
                HasBit(capabilitiesAbs, AbsMtPositionY);
            bool supportsPressure = HasBit(capabilitiesAbs, AbsMtPressure);
            bool supportsButtonClick =
                HasBit(capabilitiesEv, EventTypeKey) &&
                HasBit(capabilitiesKey, ButtonLeft);
            bool pointerLike =
                HasBit(properties, InputPropPointer) ||
                HasBit(properties, InputPropButtonPad) ||
                displayName.Contains("trackpad", StringComparison.OrdinalIgnoreCase);

            if (!supportsMultitouch || !pointerLike)
            {
                continue;
            }

            string stableId = ResolveStableId(deviceNode, stableIdsByDeviceNode, sysfsDevicePath, displayName);
            (bool canOpenEventStream, string accessError) = ProbeEventAccess(deviceNode);
            devices.Add(new LinuxInputDeviceDescriptor(
                DeviceNode: deviceNode,
                StableId: stableId,
                DisplayName: displayName,
                VendorId: ReadHexUShort(Path.Combine(sysfsDevicePath, "id", "vendor")),
                ProductId: ReadHexUShort(Path.Combine(sysfsDevicePath, "id", "product")),
                SupportsMultitouch: supportsMultitouch,
                SupportsPressure: supportsPressure,
                SupportsButtonClick: supportsButtonClick,
                CanOpenEventStream: canOpenEventStream,
                AccessError: accessError));
        }

        devices.Sort(static (left, right) =>
        {
            int byName = string.Compare(left.DisplayName, right.DisplayName, StringComparison.OrdinalIgnoreCase);
            if (byName != 0)
            {
                return byName;
            }

            return string.Compare(left.DeviceNode, right.DeviceNode, StringComparison.OrdinalIgnoreCase);
        });

        return devices;
    }

    private static Dictionary<string, string> BuildStableIdsByDeviceNode()
    {
        Dictionary<string, string> result = new(StringComparer.OrdinalIgnoreCase);
        const string byIdRoot = "/dev/input/by-id";
        if (!Directory.Exists(byIdRoot))
        {
            return result;
        }

        foreach (string symlinkPath in Directory.EnumerateFileSystemEntries(byIdRoot, "*event*"))
        {
            FileInfo symlinkInfo = new(symlinkPath);
            FileSystemInfo? targetInfo = symlinkInfo.ResolveLinkTarget(returnFinalTarget: true);
            string? targetPath = targetInfo?.FullName;
            if (string.IsNullOrWhiteSpace(targetPath))
            {
                continue;
            }

            result[targetPath] = symlinkPath;
        }

        return result;
    }

    private static string ResolveStableId(
        string deviceNode,
        IReadOnlyDictionary<string, string> stableIdsByDeviceNode,
        string sysfsDevicePath,
        string displayName)
    {
        if (stableIdsByDeviceNode.TryGetValue(deviceNode, out string? stableId))
        {
            return stableId;
        }

        string uniq = ReadTrimmed(Path.Combine(sysfsDevicePath, "uniq"));
        if (!string.IsNullOrWhiteSpace(uniq))
        {
            return uniq;
        }

        string phys = ReadTrimmed(Path.Combine(sysfsDevicePath, "phys"));
        if (!string.IsNullOrWhiteSpace(phys))
        {
            return phys;
        }

        return displayName;
    }

    private static (bool CanOpenEventStream, string AccessError) ProbeEventAccess(string deviceNode)
    {
        try
        {
            using var handle = File.OpenHandle(deviceNode, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            return (true, "ok");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
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

    private static bool HasBit(string rawBitmap, int bitIndex)
    {
        if (string.IsNullOrWhiteSpace(rawBitmap) || bitIndex < 0)
        {
            return false;
        }

        string[] words = rawBitmap.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        int wordIndex = bitIndex / BitsPerWord;
        int reversedIndex = words.Length - 1 - wordIndex;
        if ((uint)reversedIndex >= (uint)words.Length)
        {
            return false;
        }

        if (!ulong.TryParse(words[reversedIndex], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out ulong wordValue))
        {
            return false;
        }

        int bitOffset = bitIndex % BitsPerWord;
        return (wordValue & (1UL << bitOffset)) != 0;
    }
}
