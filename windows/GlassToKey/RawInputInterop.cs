using System;
using System.Buffers;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace GlassToKey;

internal static class RawInputInterop
{
    public const byte ReportIdMultitouch = 0x05;
    public const ushort VendorId = 0x8910;
    public const ushort ProductIdMt2 = 0x0265;
    public const ushort ProductIdMt2UsbC = 0x0324;
    public const ushort UsagePageDigitizer = 0x0D;
    public const ushort UsageTouchpad = 0x05;
    public const int WM_INPUT = 0x00FF;

    private const uint RID_INPUT = 0x10000003;
    private const uint RIDI_DEVICENAME = 0x20000007;
    private const uint RIDI_DEVICEINFO = 0x2000000b;
    private const int RIM_TYPEHID = 2;
    private const uint RIDEV_INPUTSINK = 0x00000100;
    [ThreadStatic] private static byte[]? t_rawInputScratch;

    public static HidDeviceInfo[] EnumerateTrackpads()
    {
        List<RawInputCandidate> candidates = new();
        foreach (RAWINPUTDEVICELIST raw in GetRawInputDevices())
        {
            if (raw.dwType != RIM_TYPEHID)
            {
                continue;
            }

            if (!TryGetDeviceName(raw.hDevice, out string deviceName))
            {
                continue;
            }

            if (!IsPreferredInterfaceName(deviceName))
            {
                continue;
            }

            RawInputDeviceInfo info = default;
            bool hasInfo = TryGetDeviceInfo(raw.hDevice, out info);
            if (!hasInfo || info.VendorId == 0 || info.ProductId == 0)
            {
                if (TryParseVidPid(deviceName, out uint vid, out uint pid))
                {
                    info = new RawInputDeviceInfo(vid, pid, info.UsagePage, info.Usage);
                    hasInfo = true;
                }
            }

            if (!hasInfo || !IsTargetDevice(info))
            {
                continue;
            }

            if (IsUsageFilterAvailable(info) && !IsUsageTouchpad(info))
            {
                continue;
            }

            bool hasTokens = HasVidPidTokens(deviceName);
            candidates.Add(new RawInputCandidate(deviceName, info.VendorId, info.ProductId, hasTokens));
        }

        List<RawInputCandidate> filtered = FilterByVidPidTokens(candidates);
        List<HidDeviceInfo> devices = new();
        for (int i = 0; i < filtered.Count; i++)
        {
            RawInputCandidate c = filtered[i];
            uint hash = HashDeviceName(c.DeviceName);
            string tag = FormatTag(new RawInputDeviceTag(i, hash));
            string displayName = $"Magic Trackpad 2 {tag}";
            devices.Add(new HidDeviceInfo(displayName, c.DeviceName, i, hash));
        }

        return devices.ToArray();
    }

    public static bool RegisterForTouchpadRawInput(IntPtr hwnd, out string? error)
    {
        RAWINPUTDEVICE[] devices =
        {
            new RAWINPUTDEVICE
            {
                usUsagePage = UsagePageDigitizer,
                usUsage = UsageTouchpad,
                dwFlags = RIDEV_INPUTSINK,
                hwndTarget = hwnd
            }
        };

        if (!RegisterRawInputDevices(devices, (uint)devices.Length, Marshal.SizeOf<RAWINPUTDEVICE>()))
        {
            error = $"0x{Marshal.GetLastWin32Error():X}";
            return false;
        }

        error = null;
        return true;
    }

    public static bool TryGetRawInputPacket(IntPtr lParam, out RawInputPacket packet)
    {
        packet = default;
        uint headerSize = (uint)Marshal.SizeOf<RAWINPUTHEADER>();
        uint size = 0;
        if (GetRawInputData(lParam, RID_INPUT, IntPtr.Zero, ref size, headerSize) != 0 || size == 0)
        {
            return false;
        }

        byte[] buffer = EnsureScratchBuffer((int)size);
        if (GetRawInputData(lParam, RID_INPUT, buffer, ref size, headerSize) != size)
        {
            return false;
        }

        if (buffer.Length < Marshal.SizeOf<RAWINPUTHEADER>())
        {
            return false;
        }

        RAWINPUTHEADER header = MemoryMarshal.Read<RAWINPUTHEADER>(buffer);
        if (header.dwType != RIM_TYPEHID)
        {
            return false;
        }

        int headerBytes = Marshal.SizeOf<RAWINPUTHEADER>();
        if (buffer.Length < headerBytes + 8)
        {
            return false;
        }

        uint reportSize = BinaryPrimitives.ReadUInt32LittleEndian(buffer.AsSpan(headerBytes, 4));
        uint reportCount = BinaryPrimitives.ReadUInt32LittleEndian(buffer.AsSpan(headerBytes + 4, 4));
        if (reportSize == 0 || reportCount == 0)
        {
            return false;
        }

        int dataOffset = headerBytes + 8;
        long totalBytes = (long)reportSize * reportCount;
        if ((long)size < dataOffset + totalBytes)
        {
            return false;
        }

        packet = new RawInputPacket(header.hDevice, reportSize, reportCount, buffer, dataOffset, (int)size);
        return true;
    }

    private static byte[] EnsureScratchBuffer(int requiredSize)
    {
        byte[]? scratch = t_rawInputScratch;
        if (scratch != null && scratch.Length >= requiredSize)
        {
            return scratch;
        }

        byte[] next = ArrayPool<byte>.Shared.Rent(requiredSize);
        if (scratch != null)
        {
            ArrayPool<byte>.Shared.Return(scratch);
        }

        t_rawInputScratch = next;
        return next;
    }

    public static bool TryGetDeviceName(IntPtr device, out string name)
    {
        name = string.Empty;
        uint size = 0;
        if (GetRawInputDeviceInfo(device, RIDI_DEVICENAME, IntPtr.Zero, ref size) == uint.MaxValue || size == 0)
        {
            return false;
        }

        StringBuilder sb = new StringBuilder((int)size);
        if (GetRawInputDeviceInfo(device, RIDI_DEVICENAME, sb, ref size) == uint.MaxValue)
        {
            return false;
        }

        name = sb.ToString();
        return !string.IsNullOrWhiteSpace(name);
    }

    public static bool TryGetDeviceInfo(IntPtr device, out RawInputDeviceInfo info)
    {
        info = default;
        uint size = (uint)Marshal.SizeOf<RID_DEVICE_INFO>();
        RID_DEVICE_INFO raw = new RID_DEVICE_INFO { cbSize = size };
        if (GetRawInputDeviceInfo(device, RIDI_DEVICEINFO, ref raw, ref size) == uint.MaxValue)
        {
            return false;
        }

        if (raw.dwType != RIM_TYPEHID)
        {
            return false;
        }

        info = new RawInputDeviceInfo(raw.hid.dwVendorId, raw.hid.dwProductId, raw.hid.usUsagePage, raw.hid.usUsage);
        return true;
    }

    public static bool IsTargetDevice(RawInputDeviceInfo info)
    {
        return IsTargetVidPid(info.VendorId, info.ProductId);
    }

    public static bool IsTargetVidPid(uint vid, uint pid)
    {
        ushort vid16 = (ushort)vid;
        ushort pid16 = (ushort)pid;
        bool vendorMatch = vid16 == VendorId || vid16 == 0x05AC || vid16 == 0x004C;
        if (!vendorMatch)
        {
            return false;
        }

        return pid16 == ProductIdMt2 || pid16 == ProductIdMt2UsbC;
    }

    public static bool IsPreferredInterfaceName(string deviceName)
    {
        if (string.IsNullOrWhiteSpace(deviceName))
        {
            return false;
        }

        string upper = deviceName.ToUpperInvariant();
        int miIndex = upper.IndexOf("MI_", StringComparison.Ordinal);
        if (miIndex < 0)
        {
            return true;
        }

        return upper.Contains("MI_01", StringComparison.Ordinal);
    }

    public static bool TryParseVidPid(string deviceName, out uint vid, out uint pid)
    {
        vid = 0;
        pid = 0;
        if (string.IsNullOrWhiteSpace(deviceName))
        {
            return false;
        }

        string upper = deviceName.ToUpperInvariant();
        int vidIndex = upper.IndexOf("VID_", StringComparison.Ordinal);
        int pidIndex = upper.IndexOf("PID_", StringComparison.Ordinal);
        int vidTokenLength = 4;
        int pidTokenLength = 4;

        if (vidIndex < 0)
        {
            vidIndex = upper.IndexOf("VID&", StringComparison.Ordinal);
            vidTokenLength = 5;
        }
        if (pidIndex < 0)
        {
            pidIndex = upper.IndexOf("PID&", StringComparison.Ordinal);
            pidTokenLength = 5;
        }

        if (vidIndex < 0 || pidIndex < 0)
        {
            return false;
        }

        if (!TryParseHexToken(upper, vidIndex + vidTokenLength, out vid))
        {
            return false;
        }
        if (!TryParseHexToken(upper, pidIndex + pidTokenLength, out pid))
        {
            return false;
        }

        return true;
    }

    private static bool TryParseHexToken(string text, int startIndex, out uint value)
    {
        value = 0;
        if (startIndex < 0 || startIndex >= text.Length)
        {
            return false;
        }

        int end = startIndex;
        while (end < text.Length && IsHex(text[end]))
        {
            end++;
        }

        if (end == startIndex)
        {
            return false;
        }

        string token = text.Substring(startIndex, end - startIndex);
        return uint.TryParse(token, System.Globalization.NumberStyles.HexNumber, null, out value);
    }

    private static bool IsHex(char ch)
    {
        return (ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'F');
    }

    private static bool IsUsageFilterAvailable(RawInputDeviceInfo info)
    {
        return info.UsagePage != 0 || info.Usage != 0;
    }

    private static bool IsUsageTouchpad(RawInputDeviceInfo info)
    {
        return info.UsagePage == UsagePageDigitizer && info.Usage == UsageTouchpad;
    }

    private static bool HasVidPidTokens(string deviceName)
    {
        string upper = deviceName.ToUpperInvariant();
        bool hasVid = upper.Contains("VID_", StringComparison.Ordinal) || upper.Contains("VID&", StringComparison.Ordinal);
        bool hasPid = upper.Contains("PID_", StringComparison.Ordinal) || upper.Contains("PID&", StringComparison.Ordinal);
        return hasVid && hasPid;
    }

    private static List<RawInputCandidate> FilterByVidPidTokens(List<RawInputCandidate> candidates)
    {
        Dictionary<(ushort, ushort), bool> hasTokensById = new();
        Dictionary<(ushort, ushort), bool> hasNonLocalMfgById = new();
        Dictionary<(ushort, ushort), bool> hasCol01ById = new();
        foreach (RawInputCandidate candidate in candidates)
        {
            (ushort vid, ushort pid) = NormalizeVidPid(candidate.Vid, candidate.Pid);
            if (candidate.HasVidPidTokens)
            {
                hasTokensById[(vid, pid)] = true;
            }
            if (!IsLocalMfg(candidate.DeviceName))
            {
                hasNonLocalMfgById[(vid, pid)] = true;
            }
            if (HasCol01(candidate.DeviceName))
            {
                hasCol01ById[(vid, pid)] = true;
            }
        }

        List<RawInputCandidate> filtered = new();
        foreach (RawInputCandidate candidate in candidates)
        {
            (ushort vid, ushort pid) = NormalizeVidPid(candidate.Vid, candidate.Pid);
            if (hasTokensById.TryGetValue((vid, pid), out bool hasTokens) && hasTokens && !candidate.HasVidPidTokens)
            {
                continue;
            }
            if (hasNonLocalMfgById.TryGetValue((vid, pid), out bool hasNonLocalMfg) && hasNonLocalMfg && IsLocalMfg(candidate.DeviceName))
            {
                continue;
            }
            if (hasCol01ById.TryGetValue((vid, pid), out bool hasCol01) && hasCol01 && HasColToken(candidate.DeviceName) && !HasCol01(candidate.DeviceName))
            {
                continue;
            }
            filtered.Add(candidate);
        }

        return filtered;
    }

    private static (ushort Vid, ushort Pid) NormalizeVidPid(uint vid, uint pid)
    {
        return ((ushort)vid, (ushort)pid);
    }

    private static bool IsLocalMfg(string deviceName)
    {
        return deviceName.Contains("LOCALMFG", StringComparison.OrdinalIgnoreCase);
    }

    private static bool HasColToken(string deviceName)
    {
        return deviceName.Contains("COL", StringComparison.OrdinalIgnoreCase);
    }

    private static bool HasCol01(string deviceName)
    {
        return deviceName.Contains("COL01", StringComparison.OrdinalIgnoreCase);
    }

    public static uint HashDeviceName(string name)
    {
        uint hash = 2166136261u;
        foreach (char ch in name)
        {
            ushort v = ch;
            hash ^= (byte)(v & 0xFF);
            hash *= 16777619u;
            hash ^= (byte)((v >> 8) & 0xFF);
            hash *= 16777619u;
        }
        return hash;
    }

    public static string FormatTag(RawInputDeviceTag tag)
    {
        return tag.Hash != 0 ? $"[dev {tag.Index} {tag.Hash:X8}]" : $"[dev {tag.Index}]";
    }

    private static IEnumerable<RAWINPUTDEVICELIST> GetRawInputDevices()
    {
        uint deviceCount = 0;
        uint size = (uint)Marshal.SizeOf<RAWINPUTDEVICELIST>();
        if (GetRawInputDeviceList(IntPtr.Zero, ref deviceCount, size) != 0 || deviceCount == 0)
        {
            yield break;
        }

        RAWINPUTDEVICELIST[] devices = new RAWINPUTDEVICELIST[deviceCount];
        if (GetRawInputDeviceList(devices, ref deviceCount, size) == uint.MaxValue)
        {
            yield break;
        }

        for (int i = 0; i < deviceCount; i++)
        {
            yield return devices[i];
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWINPUTDEVICELIST
    {
        public IntPtr hDevice;
        public uint dwType;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWINPUTDEVICE
    {
        public ushort usUsagePage;
        public ushort usUsage;
        public uint dwFlags;
        public IntPtr hwndTarget;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWINPUTHEADER
    {
        public uint dwType;
        public uint dwSize;
        public IntPtr hDevice;
        public IntPtr wParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RID_DEVICE_INFO_HID
    {
        public uint dwVendorId;
        public uint dwProductId;
        public uint dwVersionNumber;
        public ushort usUsagePage;
        public ushort usUsage;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct RID_DEVICE_INFO
    {
        [FieldOffset(0)] public uint cbSize;
        [FieldOffset(4)] public uint dwType;
        [FieldOffset(8)] public RID_DEVICE_INFO_HID hid;
    }

    private readonly record struct RawInputCandidate(string DeviceName, uint Vid, uint Pid, bool HasVidPidTokens);


    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetRawInputDeviceList(
        [Out] RAWINPUTDEVICELIST[] pRawInputDeviceList,
        ref uint puiNumDevices,
        uint cbSize);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetRawInputDeviceList(
        IntPtr pRawInputDeviceList,
        ref uint puiNumDevices,
        uint cbSize);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetRawInputData(
        IntPtr hRawInput,
        uint uiCommand,
        IntPtr pData,
        ref uint pcbSize,
        uint cbSizeHeader);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetRawInputData(
        IntPtr hRawInput,
        uint uiCommand,
        [Out] byte[] pData,
        ref uint pcbSize,
        uint cbSizeHeader);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetRawInputDeviceInfo(
        IntPtr hDevice,
        uint uiCommand,
        IntPtr pData,
        ref uint pcbSize);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern uint GetRawInputDeviceInfo(
        IntPtr hDevice,
        uint uiCommand,
        StringBuilder pData,
        ref uint pcbSize);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetRawInputDeviceInfo(
        IntPtr hDevice,
        uint uiCommand,
        ref RID_DEVICE_INFO pData,
        ref uint pcbSize);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterRawInputDevices(
        RAWINPUTDEVICE[] pRawInputDevices,
        uint uiNumDevices,
        int cbSize);
}

internal readonly record struct RawInputDeviceInfo(uint VendorId, uint ProductId, ushort UsagePage, ushort Usage);

internal readonly record struct RawInputDeviceTag(int Index, uint Hash);

internal readonly record struct RawInputDeviceSnapshot(string DeviceName, RawInputDeviceInfo Info, RawInputDeviceTag Tag);

internal readonly record struct RawInputPacket(IntPtr DeviceHandle, uint ReportSize, uint ReportCount, byte[] Buffer, int DataOffset, int ValidLength);

internal sealed class RawInputContext
{
    private readonly Dictionary<IntPtr, RawInputDeviceSnapshot> _snapshots = new();
    private readonly Dictionary<string, RawInputDeviceTag> _tagsByName = new(StringComparer.OrdinalIgnoreCase);
    private int _nextIndex;

    public void SeedTags(IEnumerable<HidDeviceInfo> devices)
    {
        _tagsByName.Clear();
        _snapshots.Clear();
        _nextIndex = 0;

        foreach (HidDeviceInfo device in devices)
        {
            if (device.IsNone || string.IsNullOrWhiteSpace(device.Path))
            {
                continue;
            }

            if (device.DeviceIndex >= 0 && device.DeviceHash != 0)
            {
                RawInputDeviceTag tag = new(device.DeviceIndex, device.DeviceHash);
                _tagsByName[device.Path] = tag;
                if (device.DeviceIndex >= _nextIndex)
                {
                    _nextIndex = device.DeviceIndex + 1;
                }
            }
        }
    }

    public bool TryGetSnapshot(IntPtr deviceHandle, out RawInputDeviceSnapshot snapshot)
    {
        if (_snapshots.TryGetValue(deviceHandle, out snapshot))
        {
            return true;
        }

        if (!RawInputInterop.TryGetDeviceName(deviceHandle, out string deviceName))
        {
            snapshot = default;
            return false;
        }

        RawInputDeviceInfo info = default;
        bool hasInfo = RawInputInterop.TryGetDeviceInfo(deviceHandle, out info);
        if (!hasInfo || info.VendorId == 0 || info.ProductId == 0)
        {
            if (RawInputInterop.TryParseVidPid(deviceName, out uint vid, out uint pid))
            {
                info = new RawInputDeviceInfo(vid, pid, info.UsagePage, info.Usage);
                hasInfo = true;
            }
        }
        if (!hasInfo)
        {
            snapshot = default;
            return false;
        }

        RawInputDeviceTag tag = GetOrCreateTag(deviceName);
        snapshot = new RawInputDeviceSnapshot(deviceName, info, tag);
        _snapshots[deviceHandle] = snapshot;
        return true;
    }

    private RawInputDeviceTag GetOrCreateTag(string deviceName)
    {
        if (_tagsByName.TryGetValue(deviceName, out RawInputDeviceTag tag))
        {
            return tag;
        }

        tag = new RawInputDeviceTag(_nextIndex++, RawInputInterop.HashDeviceName(deviceName));
        _tagsByName[deviceName] = tag;
        return tag;
    }
}
