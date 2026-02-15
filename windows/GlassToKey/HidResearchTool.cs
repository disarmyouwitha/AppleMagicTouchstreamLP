using Microsoft.Win32.SafeHandles;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace GlassToKey;

internal static class HidResearchTool
{
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const uint HidpStatusSuccess = 0x00110000;
    private const uint DigcfPresent = 0x00000002;
    private const uint DigcfDeviceInterface = 0x00000010;
    private const int ErrorNoMoreItems = 259;
    private static readonly IntPtr InvalidDeviceInfoSet = new(-1);

    public static int Run(ReaderOptions options)
    {
        List<CandidateHidInterface> devices = EnumerateCandidateInterfaces();
        if (devices.Count == 0)
        {
            Console.Error.WriteLine("No trackpads detected.");
            return 20;
        }

        Console.WriteLine("Detected trackpad interfaces:");
        for (int i = 0; i < devices.Count; i++)
        {
            CandidateHidInterface device = devices[i];
            string access = DescribeOpenability(device.Path);
            Console.WriteLine($"[{i}] {device.DisplayName} [{access}] :: {device.Path}");
        }

        if (options.HidDeviceIndex >= devices.Count)
        {
            Console.Error.WriteLine($"--hid-index {options.HidDeviceIndex} is out of range (0..{devices.Count - 1}).");
            return 21;
        }

        int selectedIndex = options.HidDeviceIndex;
        if (!options.HidIndexSpecified)
        {
            int autoIndex = FindFirstOpenableIndex(devices, options.RequiresHidWriteAccess);
            if (autoIndex >= 0)
            {
                selectedIndex = autoIndex;
            }
        }

        CandidateHidInterface target = devices[selectedIndex];
        if (string.IsNullOrWhiteSpace(target.Path))
        {
            Console.Error.WriteLine("Selected device path is empty.");
            return 22;
        }

        Console.WriteLine();
        Console.WriteLine($"Using index {selectedIndex}: {target.DisplayName}");

        bool requireWriteAccess = options.RequiresHidWriteAccess;
        if (!TryOpenDevice(target.Path, requireWriteAccess, out SafeFileHandle? handle, out string? openError))
        {
            Console.Error.WriteLine(openError);
            return 23;
        }
        if (handle == null)
        {
            Console.Error.WriteLine("CreateFile returned a null handle.");
            return 23;
        }

        using (handle)
        {
            if (!TryReadProbe(handle, out HidProbeResult probe, out string? probeError))
            {
                Console.Error.WriteLine(probeError ?? "Failed to read HID capabilities.");
                return 24;
            }

            PrintProbe(target.Path, probe);

            bool hasCommandPayload =
                !string.IsNullOrWhiteSpace(options.HidFeaturePayloadHex) ||
                !string.IsNullOrWhiteSpace(options.HidOutputPayloadHex) ||
                !string.IsNullOrWhiteSpace(options.HidWritePayloadHex);
            if (!hasCommandPayload)
            {
                return 0;
            }

            byte[]? featurePayload;
            byte[]? outputPayload;
            byte[]? writePayload;
            string? featureError = null;
            string? outputError = null;
            string? writeError = null;
            if (!TryParsePayload(options.HidFeaturePayloadHex, "--hid-feature", out featurePayload, out featureError) ||
                !TryParsePayload(options.HidOutputPayloadHex, "--hid-output", out outputPayload, out outputError) ||
                !TryParsePayload(options.HidWritePayloadHex, "--hid-write", out writePayload, out writeError))
            {
                string message = featureError ?? outputError ?? writeError ?? "Invalid payload.";
                Console.Error.WriteLine(message);
                return 25;
            }

            for (int i = 0; i < options.HidRepeat; i++)
            {
                int frame = i + 1;
                if (featurePayload != null && !SendFeature(handle, featurePayload, frame))
                {
                    return 26;
                }
                if (outputPayload != null && !SendOutput(handle, outputPayload, frame))
                {
                    return 27;
                }
                if (writePayload != null && !SendWrite(handle, writePayload, frame))
                {
                    return 28;
                }

                if (options.HidIntervalMs > 0 && frame < options.HidRepeat)
                {
                    Thread.Sleep(options.HidIntervalMs);
                }
            }
        }

        return 0;
    }

    private static int FindFirstOpenableIndex(List<CandidateHidInterface> devices, bool requireWriteAccess)
    {
        for (int i = 0; i < devices.Count; i++)
        {
            CandidateHidInterface device = devices[i];
            if (!TryOpenDevice(device.Path, requireWriteAccess, out SafeFileHandle? handle, out _))
            {
                continue;
            }

            handle?.Dispose();
            return i;
        }

        return -1;
    }

    private static List<CandidateHidInterface> EnumerateCandidateInterfaces()
    {
        Dictionary<string, CandidateHidInterface> result = new(StringComparer.OrdinalIgnoreCase);

        foreach (string path in EnumerateSetupDiHidPaths())
        {
            if (!RawInputInterop.TryParseVidPid(path, out uint vid, out uint pid) || !RawInputInterop.IsTargetVidPid(vid, pid))
            {
                continue;
            }

            result[path] = new CandidateHidInterface(path, BuildDisplayName(path, vid, pid));
        }

        HidDeviceInfo[] rawInputDevices = RawInputInterop.EnumerateTrackpads();
        for (int i = 0; i < rawInputDevices.Length; i++)
        {
            HidDeviceInfo device = rawInputDevices[i];
            if (string.IsNullOrWhiteSpace(device.Path))
            {
                continue;
            }

            if (!result.ContainsKey(device.Path))
            {
                result[device.Path] = new CandidateHidInterface(device.Path, $"{device.DisplayName} (RawInput)");
            }
        }

        List<CandidateHidInterface> output = new(result.Values);
        output.Sort(static (a, b) => string.Compare(a.Path, b.Path, StringComparison.OrdinalIgnoreCase));
        return output;
    }

    private static IEnumerable<string> EnumerateSetupDiHidPaths()
    {
        HidD_GetHidGuid(out Guid hidGuid);
        IntPtr deviceInfoSet = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DigcfPresent | DigcfDeviceInterface);
        if (deviceInfoSet == IntPtr.Zero || deviceInfoSet == InvalidDeviceInfoSet)
        {
            yield break;
        }

        try
        {
            uint index = 0;
            while (true)
            {
                SpDeviceInterfaceData interfaceData = new()
                {
                    cbSize = Marshal.SizeOf<SpDeviceInterfaceData>()
                };

                bool ok = SetupDiEnumDeviceInterfaces(deviceInfoSet, IntPtr.Zero, ref hidGuid, index, ref interfaceData);
                if (!ok)
                {
                    int err = Marshal.GetLastWin32Error();
                    if (err == ErrorNoMoreItems)
                    {
                        break;
                    }

                    break;
                }

                if (TryGetDevicePath(deviceInfoSet, interfaceData, out string? path) && !string.IsNullOrWhiteSpace(path))
                {
                    yield return path;
                }

                index++;
            }
        }
        finally
        {
            _ = SetupDiDestroyDeviceInfoList(deviceInfoSet);
        }
    }

    private static bool TryGetDevicePath(IntPtr deviceInfoSet, SpDeviceInterfaceData interfaceData, out string? path)
    {
        path = null;

        _ = SetupDiGetDeviceInterfaceDetail(deviceInfoSet, ref interfaceData, IntPtr.Zero, 0, out uint requiredSize, IntPtr.Zero);
        if (requiredSize == 0)
        {
            return false;
        }

        IntPtr detailDataBuffer = Marshal.AllocHGlobal((int)requiredSize);
        try
        {
            int cbSize = IntPtr.Size == 8 ? 8 : 6;
            Marshal.WriteInt32(detailDataBuffer, cbSize);

            bool ok = SetupDiGetDeviceInterfaceDetail(
                deviceInfoSet,
                ref interfaceData,
                detailDataBuffer,
                requiredSize,
                out _,
                IntPtr.Zero);
            if (!ok)
            {
                return false;
            }

            IntPtr pDevicePathName = IntPtr.Add(detailDataBuffer, 4);
            path = Marshal.PtrToStringUni(pDevicePathName);
            return !string.IsNullOrWhiteSpace(path);
        }
        finally
        {
            Marshal.FreeHGlobal(detailDataBuffer);
        }
    }

    private static string BuildDisplayName(string path, uint vid, uint pid)
    {
        string upper = path.ToUpperInvariant();
        string collection = "COL??";
        int colIndex = upper.IndexOf("COL", StringComparison.Ordinal);
        if (colIndex >= 0 && colIndex + 5 <= upper.Length)
        {
            collection = upper.Substring(colIndex, 5);
        }

        return $"Magic Trackpad 2 [{vid:X4}:{pid:X4} {collection}]";
    }

    private static bool TryOpenDevice(string path, bool requireWriteAccess, out SafeFileHandle? handle, out string? error)
    {
        uint desiredAccess = GenericRead | (requireWriteAccess ? GenericWrite : 0);
        handle = CreateFile(path, desiredAccess, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (!handle.IsInvalid)
        {
            error = null;
            return true;
        }

        int lastError = Marshal.GetLastWin32Error();
        handle.Dispose();

        if (requireWriteAccess)
        {
            error = $"CreateFile failed for device path '{path}' with read/write access (Win32=0x{lastError:X}).";
            handle = null;
            return false;
        }

        handle = CreateFile(path, GenericRead, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (!handle.IsInvalid)
        {
            error = null;
            return true;
        }

        int readOnlyError = Marshal.GetLastWin32Error();
        handle.Dispose();
        handle = null;
        error = $"CreateFile failed for device path '{path}' (read/write Win32=0x{lastError:X}, read Win32=0x{readOnlyError:X}).";
        return false;
    }

    private static string DescribeOpenability(string path)
    {
        SafeFileHandle rw = CreateFile(path, GenericRead | GenericWrite, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (!rw.IsInvalid)
        {
            rw.Dispose();
            return "rw";
        }

        int rwError = Marshal.GetLastWin32Error();
        rw.Dispose();

        SafeFileHandle r = CreateFile(path, GenericRead, FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (!r.IsInvalid)
        {
            r.Dispose();
            return $"r (rw 0x{rwError:X})";
        }

        int rError = Marshal.GetLastWin32Error();
        r.Dispose();
        return $"locked (rw 0x{rwError:X}, r 0x{rError:X})";
    }

    private static bool TryReadProbe(SafeFileHandle handle, out HidProbeResult probe, out string? error)
    {
        probe = default;

        HiddAttributes attributes = new() { Size = Marshal.SizeOf<HiddAttributes>() };
        if (!HidD_GetAttributes(handle, ref attributes))
        {
            error = $"HidD_GetAttributes failed (Win32=0x{Marshal.GetLastWin32Error():X}).";
            return false;
        }

        IntPtr preparsedData = IntPtr.Zero;
        if (!HidD_GetPreparsedData(handle, out preparsedData) || preparsedData == IntPtr.Zero)
        {
            error = $"HidD_GetPreparsedData failed (Win32=0x{Marshal.GetLastWin32Error():X}).";
            return false;
        }

        try
        {
            uint capsStatus = (uint)HidP_GetCaps(preparsedData, out HidpCaps caps);
            if (capsStatus != HidpStatusSuccess)
            {
                error = $"HidP_GetCaps failed (NTSTATUS=0x{capsStatus:X8}).";
                return false;
            }

            probe = new HidProbeResult(
                attributes.VendorID,
                attributes.ProductID,
                attributes.VersionNumber,
                caps.UsagePage,
                caps.Usage,
                caps.InputReportByteLength,
                caps.OutputReportByteLength,
                caps.FeatureReportByteLength,
                GetUnicodeHidString(handle, HidD_GetManufacturerString),
                GetUnicodeHidString(handle, HidD_GetProductString),
                GetUnicodeHidString(handle, HidD_GetSerialNumberString));
            error = null;
            return true;
        }
        finally
        {
            _ = HidD_FreePreparsedData(preparsedData);
        }
    }

    private static void PrintProbe(string path, in HidProbeResult probe)
    {
        Console.WriteLine();
        Console.WriteLine($"Selected HID path: {path}");
        Console.WriteLine($"VID:PID {probe.VendorId:X4}:{probe.ProductId:X4} (version 0x{probe.VersionNumber:X4})");
        Console.WriteLine($"UsagePage/Usage: 0x{probe.UsagePage:X4}/0x{probe.Usage:X4}");
        Console.WriteLine($"Report lengths: input={probe.InputReportBytes} output={probe.OutputReportBytes} feature={probe.FeatureReportBytes}");
        if (!string.IsNullOrWhiteSpace(probe.Manufacturer))
        {
            Console.WriteLine($"Manufacturer: {probe.Manufacturer}");
        }
        if (!string.IsNullOrWhiteSpace(probe.Product))
        {
            Console.WriteLine($"Product: {probe.Product}");
        }
        if (!string.IsNullOrWhiteSpace(probe.SerialNumber))
        {
            Console.WriteLine($"Serial: {probe.SerialNumber}");
        }
    }

    private static bool SendFeature(SafeFileHandle handle, byte[] payload, int frame)
    {
        bool ok = HidD_SetFeature(handle, payload, payload.Length);
        if (!ok)
        {
            Console.Error.WriteLine($"[{frame}] HidD_SetFeature failed (Win32=0x{Marshal.GetLastWin32Error():X}) payload={FormatHex(payload)}");
            return false;
        }

        Console.WriteLine($"[{frame}] HidD_SetFeature OK payload={FormatHex(payload)}");
        return true;
    }

    private static bool SendOutput(SafeFileHandle handle, byte[] payload, int frame)
    {
        bool ok = HidD_SetOutputReport(handle, payload, payload.Length);
        if (!ok)
        {
            Console.Error.WriteLine($"[{frame}] HidD_SetOutputReport failed (Win32=0x{Marshal.GetLastWin32Error():X}) payload={FormatHex(payload)}");
            return false;
        }

        Console.WriteLine($"[{frame}] HidD_SetOutputReport OK payload={FormatHex(payload)}");
        return true;
    }

    private static bool SendWrite(SafeFileHandle handle, byte[] payload, int frame)
    {
        bool ok = WriteFile(handle, payload, (uint)payload.Length, out uint written, IntPtr.Zero);
        if (!ok)
        {
            Console.Error.WriteLine($"[{frame}] WriteFile failed (Win32=0x{Marshal.GetLastWin32Error():X}) payload={FormatHex(payload)}");
            return false;
        }

        Console.WriteLine($"[{frame}] WriteFile OK bytes={written}/{payload.Length} payload={FormatHex(payload)}");
        return written == payload.Length;
    }

    private static string FormatHex(byte[] bytes)
    {
        if (bytes.Length == 0)
        {
            return "<empty>";
        }

        StringBuilder sb = new(bytes.Length * 3);
        for (int i = 0; i < bytes.Length; i++)
        {
            if (i > 0)
            {
                _ = sb.Append(' ');
            }
            _ = sb.Append(bytes[i].ToString("X2"));
        }
        return sb.ToString();
    }

    private static bool TryParsePayload(string? payloadText, string optionName, out byte[]? payload, out string? error)
    {
        payload = null;
        error = null;
        if (string.IsNullOrWhiteSpace(payloadText))
        {
            return true;
        }

        if (!TryParseHexBytes(payloadText, out byte[] bytes))
        {
            error = $"{optionName} must be hex bytes like \"01 02 A0\" or \"0102A0\".";
            return false;
        }

        if (bytes.Length == 0)
        {
            error = $"{optionName} payload cannot be empty.";
            return false;
        }

        payload = bytes;
        return true;
    }

    private static bool TryParseHexBytes(string text, out byte[] bytes)
    {
        bytes = Array.Empty<byte>();
        string normalized = text
            .Replace(",", " ", StringComparison.Ordinal)
            .Replace(";", " ", StringComparison.Ordinal)
            .Replace("|", " ", StringComparison.Ordinal)
            .Trim();
        if (normalized.Length == 0)
        {
            return false;
        }

        string[] tokens = normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        List<byte> output = new();

        if (tokens.Length == 1 && IsContiguousHex(tokens[0]))
        {
            string token = StripHexPrefix(tokens[0]);
            if ((token.Length & 1) != 0)
            {
                return false;
            }

            for (int i = 0; i < token.Length; i += 2)
            {
                if (!byte.TryParse(token.AsSpan(i, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out byte value))
                {
                    return false;
                }
                output.Add(value);
            }

            bytes = output.ToArray();
            return true;
        }

        foreach (string raw in tokens)
        {
            string token = StripHexPrefix(raw);
            if (token.Length == 0 || token.Length > 2)
            {
                return false;
            }
            if (!byte.TryParse(token, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out byte value))
            {
                return false;
            }
            output.Add(value);
        }

        bytes = output.ToArray();
        return output.Count > 0;
    }

    private static bool IsContiguousHex(string token)
    {
        string trimmed = StripHexPrefix(token);
        if (trimmed.Length == 0)
        {
            return false;
        }

        for (int i = 0; i < trimmed.Length; i++)
        {
            char ch = trimmed[i];
            bool isHex =
                (ch >= '0' && ch <= '9') ||
                (ch >= 'a' && ch <= 'f') ||
                (ch >= 'A' && ch <= 'F');
            if (!isHex)
            {
                return false;
            }
        }
        return true;
    }

    private static string StripHexPrefix(string token)
    {
        if (token.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            return token.Substring(2);
        }

        return token;
    }

    private static string? GetUnicodeHidString(SafeFileHandle handle, HidStringReader reader)
    {
        byte[] buffer = new byte[256];
        if (!reader(handle, buffer, buffer.Length))
        {
            return null;
        }

        string value = Encoding.Unicode.GetString(buffer).TrimEnd('\0', ' ');
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    private readonly record struct HidProbeResult(
        ushort VendorId,
        ushort ProductId,
        ushort VersionNumber,
        ushort UsagePage,
        ushort Usage,
        ushort InputReportBytes,
        ushort OutputReportBytes,
        ushort FeatureReportBytes,
        string? Manufacturer,
        string? Product,
        string? SerialNumber);

    private readonly record struct CandidateHidInterface(string Path, string DisplayName);

    [StructLayout(LayoutKind.Sequential)]
    private struct HiddAttributes
    {
        public int Size;
        public ushort VendorID;
        public ushort ProductID;
        public ushort VersionNumber;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HidpCaps
    {
        public ushort Usage;
        public ushort UsagePage;
        public ushort InputReportByteLength;
        public ushort OutputReportByteLength;
        public ushort FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
        public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps;
        public ushort NumberInputValueCaps;
        public ushort NumberInputDataIndices;
        public ushort NumberOutputButtonCaps;
        public ushort NumberOutputValueCaps;
        public ushort NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps;
        public ushort NumberFeatureValueCaps;
        public ushort NumberFeatureDataIndices;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SpDeviceInterfaceData
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    private delegate bool HidStringReader(SafeFileHandle handle, byte[] buffer, int bufferLength);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteFile(
        SafeFileHandle hFile,
        byte[] lpBuffer,
        uint nNumberOfBytesToWrite,
        out uint lpNumberOfBytesWritten,
        IntPtr lpOverlapped);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetAttributes(SafeFileHandle hidDeviceObject, ref HiddAttributes attributes);

    [DllImport("hid.dll")]
    private static extern void HidD_GetHidGuid(out Guid hidGuid);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetPreparsedData(SafeFileHandle hidDeviceObject, out IntPtr preparsedData);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_FreePreparsedData(IntPtr preparsedData);

    [DllImport("hid.dll")]
    private static extern int HidP_GetCaps(IntPtr preparsedData, out HidpCaps capabilities);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_SetFeature(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_SetOutputReport(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetManufacturerString(SafeFileHandle hidDeviceObject, byte[] buffer, int bufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetProductString(SafeFileHandle hidDeviceObject, byte[] buffer, int bufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetSerialNumberString(SafeFileHandle hidDeviceObject, byte[] buffer, int bufferLength);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevs(
        ref Guid classGuid,
        IntPtr enumerator,
        IntPtr hwndParent,
        uint flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInterfaces(
        IntPtr deviceInfoSet,
        IntPtr deviceInfoData,
        ref Guid interfaceClassGuid,
        uint memberIndex,
        ref SpDeviceInterfaceData deviceInterfaceData);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(
        IntPtr deviceInfoSet,
        ref SpDeviceInterfaceData deviceInterfaceData,
        IntPtr deviceInterfaceDetailData,
        uint deviceInterfaceDetailDataSize,
        out uint requiredSize,
        IntPtr deviceInfoData);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);
}
