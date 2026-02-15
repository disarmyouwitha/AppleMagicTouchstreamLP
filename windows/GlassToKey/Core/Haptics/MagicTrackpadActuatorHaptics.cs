using Microsoft.Win32.SafeHandles;
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace GlassToKey;

internal static class MagicTrackpadActuatorHaptics
{
    // Known-good AMT2 actuator output report ("vibrate now") for at least some firmwares.
    // Report ID: 0x53
    // Format: [0]=rid, [1]=0x01, [2..5]=strength (LE uint32), [6..13]=tail constants, rest zero padding to output report length (64).
    private const byte ReportId = 0x53;
    private const byte ReportCmd = 0x01;

    private const int InitUninitialized = 0;
    private const int InitInProgress = 1;
    private const int InitReady = 2;
    private const int InitFailed = -1;

    private static readonly object Gate = new();
    private static int _initState;
    private static SafeFileHandle? _handle;
    private static int _outputReportBytes;
    private static byte[]? _payload;

    private static bool _enabled;
    private static uint _strength;
    private static long _minIntervalTicks;
    private static long _lastVibrateTicks;

    public static void Configure(bool enabled, uint strength, int minIntervalMs)
    {
        _enabled = enabled;
        _strength = strength;

        int clampedMs = Math.Clamp(minIntervalMs, 0, 500);
        long ticks = clampedMs <= 0 ? 0 : (long)((double)Stopwatch.Frequency * clampedMs / 1000.0);
        Interlocked.Exchange(ref _minIntervalTicks, ticks);
    }

    public static void WarmupAsync()
    {
        if (!Volatile.Read(ref _enabled))
        {
            return;
        }

        if (Volatile.Read(ref _initState) != InitUninitialized)
        {
            return;
        }

        // Ensure enumeration/opening doesn't happen on the engine/dispatch hot path.
        _ = ThreadPool.QueueUserWorkItem(static _ => TryEnsureInitialized());
    }

    public static bool TryVibrate()
    {
        if (!Volatile.Read(ref _enabled))
        {
            return false;
        }

        long minInterval = Volatile.Read(ref _minIntervalTicks);
        if (minInterval > 0)
        {
            long now = Stopwatch.GetTimestamp();
            long last = Volatile.Read(ref _lastVibrateTicks);
            if (now - last < minInterval)
            {
                return false;
            }

            // Avoid a lock on the common path when haptics are spammed.
            if (Interlocked.CompareExchange(ref _lastVibrateTicks, now, last) != last)
            {
                return false;
            }
        }

        if (!TryEnsureInitialized())
        {
            return false;
        }

        SafeFileHandle? handle = _handle;
        byte[]? payload = _payload;
        if (handle == null || handle.IsInvalid || payload == null)
        {
            return false;
        }

        lock (Gate)
        {
            // Strength is set at bytes [2..5] (LE uint32).
            uint strength = Volatile.Read(ref _strength);
            payload[2] = (byte)(strength & 0xFF);
            payload[3] = (byte)((strength >> 8) & 0xFF);
            payload[4] = (byte)((strength >> 16) & 0xFF);
            payload[5] = (byte)((strength >> 24) & 0xFF);

            return HidD_SetOutputReport(handle, payload, payload.Length);
        }
    }

    public static void Dispose()
    {
        lock (Gate)
        {
            _handle?.Dispose();
            _handle = null;
            _payload = null;
            _outputReportBytes = 0;
            Volatile.Write(ref _initState, InitUninitialized);
        }
    }

    private static bool TryEnsureInitialized()
    {
        int state = Volatile.Read(ref _initState);
        if (state == InitReady)
        {
            return true;
        }
        if (state == InitFailed)
        {
            return false;
        }

        if (Interlocked.CompareExchange(ref _initState, InitInProgress, InitUninitialized) != InitUninitialized)
        {
            // Another thread is doing initialization; don't block the caller.
            return false;
        }

        try
        {
            if (!TryOpenActuator(out SafeFileHandle? handle, out int outputReportBytes))
            {
                Volatile.Write(ref _initState, InitFailed);
                return false;
            }

            byte[] payload = new byte[Math.Max(outputReportBytes, 14)];
            payload[0] = ReportId;
            payload[1] = ReportCmd;
            // [2..5] strength set dynamically.
            payload[6] = 0x21;
            payload[7] = 0x2B;
            payload[8] = 0x06;
            payload[9] = 0x01;
            payload[10] = 0x00;
            payload[11] = 0x16;
            payload[12] = 0x41;
            payload[13] = 0x13;

            lock (Gate)
            {
                _handle?.Dispose();
                _handle = handle;
                _outputReportBytes = outputReportBytes;
                _payload = payload;
            }

            Volatile.Write(ref _initState, InitReady);
            return true;
        }
        catch
        {
            Volatile.Write(ref _initState, InitFailed);
            return false;
        }
    }

    private static bool TryOpenActuator(out SafeFileHandle? handle, out int outputReportBytes)
    {
        handle = null;
        outputReportBytes = 0;

        HidD_GetHidGuid(out Guid hidGuid);
        IntPtr devInfo = SetupDiGetClassDevsW(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DigcfPresent | DigcfDeviceInterface);
        if (devInfo == IntPtr.Zero || devInfo == new IntPtr(-1))
        {
            return false;
        }

        try
        {
            int bestScore = int.MinValue;
            SafeFileHandle? bestHandle = null;
            int bestOutBytes = 0;

            uint index = 0;
            while (true)
            {
                SP_DEVICE_INTERFACE_DATA iface = new()
                {
                    cbSize = Marshal.SizeOf<SP_DEVICE_INTERFACE_DATA>()
                };

                if (!SetupDiEnumDeviceInterfaces(devInfo, IntPtr.Zero, ref hidGuid, index, ref iface))
                {
                    int err = Marshal.GetLastWin32Error();
                    if (err == ErrorNoMoreItems)
                    {
                        break;
                    }
                    break;
                }

                index++;
                if (!TryGetInterfacePath(devInfo, ref iface, out string? path) || string.IsNullOrWhiteSpace(path))
                {
                    continue;
                }

                // Fast pre-filter: most non-Apple HID devices don't matter.
                if (path.IndexOf("vid_05ac&pid_0324", StringComparison.OrdinalIgnoreCase) < 0 &&
                    path.IndexOf("vid_004c&pid_0324", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    continue;
                }

                if (!TryOpenHidPath(path, out SafeFileHandle? candidate))
                {
                    continue;
                }

                if (candidate == null || candidate.IsInvalid)
                {
                    continue;
                }

                int score = ScoreIfActuator(candidate, out int outBytes);
                if (score > bestScore && outBytes > 0)
                {
                    bestHandle?.Dispose();
                    bestHandle = candidate;
                    bestScore = score;
                    bestOutBytes = outBytes;
                }
                else
                {
                    candidate.Dispose();
                }
            }

            if (bestHandle == null || bestHandle.IsInvalid || bestOutBytes <= 0)
            {
                bestHandle?.Dispose();
                return false;
            }

            handle = bestHandle;
            outputReportBytes = bestOutBytes;
            return true;
        }
        finally
        {
            _ = SetupDiDestroyDeviceInfoList(devInfo);
        }
    }

    private static int ScoreIfActuator(SafeFileHandle handle, out int outputReportBytes)
    {
        outputReportBytes = 0;

        if (!HidD_GetAttributes(handle, out HIDD_ATTRIBUTES attrs))
        {
            return int.MinValue;
        }

        // We prefer the "native" USB VID for Apple devices (0x05AC) if present.
        int score = 0;
        if (attrs.VendorID == 0x05AC)
        {
            score += 10;
        }

        string product = TryGetProductString(handle);
        if (product.IndexOf("Actuator", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            score += 50;
        }

        if (!HidD_GetPreparsedData(handle, out IntPtr preparsed))
        {
            return int.MinValue;
        }

        try
        {
            if (HidP_GetCaps(preparsed, out HIDP_CAPS caps) != HidpStatusSuccess)
            {
                return int.MinValue;
            }

            // Observed actuator caps:
            // UsagePage=0xFF00, Usage=0x000D, OutputReportByteLength=64.
            bool looksLikeActuator = caps.UsagePage == 0xFF00 && caps.Usage == 0x000D && caps.OutputReportByteLength >= 14;
            if (looksLikeActuator)
            {
                score += 100;
            }

            outputReportBytes = caps.OutputReportByteLength;
            if (outputReportBytes >= 64)
            {
                score += 5;
            }

            return score;
        }
        finally
        {
            _ = HidD_FreePreparsedData(preparsed);
        }
    }

    private static string TryGetProductString(SafeFileHandle handle)
    {
        // HID strings are UTF-16, typically <= 126 WCHAR.
        byte[] buffer = new byte[256];
        if (!HidD_GetProductString(handle, buffer, buffer.Length))
        {
            return string.Empty;
        }

        string s = Encoding.Unicode.GetString(buffer);
        int nul = s.IndexOf('\0');
        return nul >= 0 ? s.Substring(0, nul) : s;
    }

    private static bool TryOpenHidPath(string path, out SafeFileHandle? handle)
    {
        handle = CreateFileW(
            path,
            GenericRead | GenericWrite,
            FileShareRead | FileShareWrite,
            IntPtr.Zero,
            OpenExisting,
            0,
            IntPtr.Zero);
        return handle != null && !handle.IsInvalid;
    }

    private static bool TryGetInterfacePath(IntPtr devInfo, ref SP_DEVICE_INTERFACE_DATA iface, out string? devicePath)
    {
        devicePath = null;

        // First call to get required size.
        _ = SetupDiGetDeviceInterfaceDetailW(devInfo, ref iface, IntPtr.Zero, 0, out uint required, IntPtr.Zero);
        int err = Marshal.GetLastWin32Error();
        if (err != ErrorInsufficientBuffer || required == 0)
        {
            return false;
        }

        IntPtr detail = Marshal.AllocHGlobal((int)required);
        try
        {
            // cbSize is 8 on x64, 6 on x86 (WCHAR alignment). Use pointer size to pick.
            int cbSize = IntPtr.Size == 8 ? 8 : 6;
            Marshal.WriteInt32(detail, cbSize);

            if (!SetupDiGetDeviceInterfaceDetailW(devInfo, ref iface, detail, required, out _, IntPtr.Zero))
            {
                return false;
            }

            IntPtr pathPtr = detail + 4; // cbSize (DWORD) then string starts; for x64, still correct with cbSize=8.
            devicePath = Marshal.PtrToStringUni(pathPtr);
            return !string.IsNullOrWhiteSpace(devicePath);
        }
        finally
        {
            Marshal.FreeHGlobal(detail);
        }
    }

    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const uint DigcfPresent = 0x00000002;
    private const uint DigcfDeviceInterface = 0x00000010;
    private const int ErrorNoMoreItems = 259;
    private const int ErrorInsufficientBuffer = 122;
    private const int HidpStatusSuccess = 0x00110000;

    [StructLayout(LayoutKind.Sequential)]
    private struct SP_DEVICE_INTERFACE_DATA
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HIDD_ATTRIBUTES
    {
        public int Size;
        public ushort VendorID;
        public ushort ProductID;
        public ushort VersionNumber;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HIDP_CAPS
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

    [DllImport("hid.dll", SetLastError = true)]
    private static extern void HidD_GetHidGuid(out Guid hidGuid);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetAttributes(SafeFileHandle hidDeviceObject, out HIDD_ATTRIBUTES attributes);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetPreparsedData(SafeFileHandle hidDeviceObject, out IntPtr preparsedData);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_FreePreparsedData(IntPtr preparsedData);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern uint HidP_GetCaps(IntPtr preparsedData, out HIDP_CAPS capabilities);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_GetProductString(SafeFileHandle hidDeviceObject, byte[] buffer, int bufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    private static extern bool HidD_SetOutputReport(SafeFileHandle hidDeviceObject, byte[] reportBuffer, int reportBufferLength);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevsW(ref Guid classGuid, IntPtr enumerator, IntPtr hwndParent, uint flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInterfaces(IntPtr deviceInfoSet, IntPtr deviceInfoData, ref Guid interfaceClassGuid, uint memberIndex, ref SP_DEVICE_INTERFACE_DATA deviceInterfaceData);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr deviceInfoSet, ref SP_DEVICE_INTERFACE_DATA deviceInterfaceData, IntPtr deviceInterfaceDetailData, uint deviceInterfaceDetailDataSize, out uint requiredSize, IntPtr deviceInfoData);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);
}
