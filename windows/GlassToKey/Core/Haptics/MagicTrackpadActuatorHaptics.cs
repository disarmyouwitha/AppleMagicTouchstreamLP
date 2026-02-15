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
    // Format: [0]=rid, [1]=0x01, [2..5]=strength (LE uint32), [6..13]=tail constants, rest zero padding to output report length (usually 64).
    private const byte ReportId = 0x53;
    private const byte ReportCmd = 0x01;

    private const int InitUninitialized = 0;
    private const int InitInProgress = 1;
    private const int InitReady = 2;
    private const int InitFailed = -1;

    private sealed class ActuatorDevice
    {
        public SafeFileHandle Handle = new(IntPtr.Zero, ownsHandle: true);
        public int OutputReportBytes;
        public byte[] Payload = Array.Empty<byte>();
        public long LastVibrateTicks;
        public Guid ContainerId;
    }

    private static readonly object Gate = new();
    private static int _initState;
    private static Guid? _leftContainerId;
    private static Guid? _rightContainerId;
    private static ActuatorDevice? _left;
    private static ActuatorDevice? _right;

    private static bool _enabled;
    private static uint _strength;
    private static long _minIntervalTicks;

    public static void Configure(bool enabled, uint strength, int minIntervalMs)
    {
        lock (Gate)
        {
            _enabled = enabled;
            _strength = strength;

            if (_left != null)
            {
                _left.Payload = BuildPayload(_left.OutputReportBytes, strength);
            }
            if (_right != null && !ReferenceEquals(_right, _left))
            {
                _right.Payload = BuildPayload(_right.OutputReportBytes, strength);
            }
        }

        int clampedMs = Math.Clamp(minIntervalMs, 0, 500);
        long ticks = clampedMs <= 0 ? 0 : (long)((double)Stopwatch.Frequency * clampedMs / 1000.0);
        Interlocked.Exchange(ref _minIntervalTicks, ticks);
    }

    // left/right are the *touch* collection HID paths from Raw Input selection (settings.json).
    // We route to the correct actuator by matching the Windows device ContainerId.
    public static void SetRoutes(string? leftTouchHidPath, string? rightTouchHidPath)
    {
        Guid? left = TryResolveContainerId(leftTouchHidPath);
        Guid? right = TryResolveContainerId(rightTouchHidPath);

        lock (Gate)
        {
            if (_leftContainerId == left && _rightContainerId == right)
            {
                return;
            }

            _leftContainerId = left;
            _rightContainerId = right;
            DisposeDevices_NoLock();
            Volatile.Write(ref _initState, InitUninitialized);
        }
    }

    public static void WarmupAsync()
    {
        lock (Gate)
        {
            if (!_enabled)
            {
                return;
            }
        }

        if (Volatile.Read(ref _initState) != InitUninitialized)
        {
            return;
        }

        // Ensure enumeration/opening doesn't happen on the engine/dispatch hot path.
        _ = ThreadPool.QueueUserWorkItem(static _ => TryEnsureInitialized());
    }

    public static bool TryVibrate(TrackpadSide side)
    {
        if (!_enabled)
        {
            return false;
        }

        if (Volatile.Read(ref _initState) != InitReady)
        {
            WarmupAsync();
            return false;
        }

        ActuatorDevice? device = side == TrackpadSide.Right ? _right : _left;
        if (device == null)
        {
            device = side == TrackpadSide.Right ? _left : _right;
        }
        if (device == null)
        {
            return false;
        }

        long minInterval = Volatile.Read(ref _minIntervalTicks);
        if (minInterval > 0)
        {
            long now = Stopwatch.GetTimestamp();
            long last = Volatile.Read(ref device.LastVibrateTicks);
            if (now - last < minInterval)
            {
                return false;
            }

            if (Interlocked.CompareExchange(ref device.LastVibrateTicks, now, last) != last)
            {
                return false;
            }
        }

        SafeFileHandle handle = device.Handle;
        if (handle.IsInvalid)
        {
            return false;
        }

        byte[] payload = device.Payload;
        if (payload.Length == 0)
        {
            return false;
        }

        return HidD_SetOutputReport(handle, payload, payload.Length);
    }

    public static void Dispose()
    {
        lock (Gate)
        {
            DisposeDevices_NoLock();
            Volatile.Write(ref _initState, InitUninitialized);
        }
    }

    private static void DisposeDevices_NoLock()
    {
        _left?.Handle.Dispose();
        if (_right != null && !ReferenceEquals(_right, _left))
        {
            _right.Handle.Dispose();
        }
        _left = null;
        _right = null;
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
            return false;
        }

        try
        {
            Guid? leftTarget;
            Guid? rightTarget;
            uint strength;
            lock (Gate)
            {
                leftTarget = _leftContainerId;
                rightTarget = _rightContainerId;
                strength = _strength;
            }

            if (!TryOpenActuators(leftTarget, rightTarget, out ActuatorDevice? left, out ActuatorDevice? right))
            {
                Volatile.Write(ref _initState, InitFailed);
                return false;
            }

            if (left != null)
            {
                left.Payload = BuildPayload(left.OutputReportBytes, strength);
            }
            if (right != null && !ReferenceEquals(right, left))
            {
                right.Payload = BuildPayload(right.OutputReportBytes, strength);
            }

            lock (Gate)
            {
                DisposeDevices_NoLock();

                _left = left;
                _right = right;
                if (_left == null && _right != null)
                {
                    _left = _right;
                }
                else if (_right == null && _left != null)
                {
                    _right = _left;
                }
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

    private static bool TryOpenActuators(Guid? leftTarget, Guid? rightTarget, out ActuatorDevice? left, out ActuatorDevice? right)
    {
        left = null;
        right = null;

        HidD_GetHidGuid(out Guid hidGuid);
        IntPtr devInfo = SetupDiGetClassDevsW(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DigcfPresent | DigcfDeviceInterface);
        if (devInfo == IntPtr.Zero || devInfo == new IntPtr(-1))
        {
            return false;
        }

        try
        {
            int bestLeftScore = int.MinValue;
            int bestRightScore = int.MinValue;
            int bestAnyScore = int.MinValue;
            Candidate bestLeft = default;
            Candidate bestRight = default;
            Candidate bestAny = default;

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
                if (!TryGetInterfaceDetail(devInfo, ref iface, out string? path, out SP_DEVINFO_DATA devInfoData) || string.IsNullOrWhiteSpace(path))
                {
                    continue;
                }

                // Fast pre-filter: most non-Apple HID devices don't matter.
                if (path.IndexOf("vid_05ac&pid_0324", StringComparison.OrdinalIgnoreCase) < 0 &&
                    path.IndexOf("vid_004c&pid_0324", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    continue;
                }

                if (!TryOpenHidPath(path, out SafeFileHandle? handle) || handle == null || handle.IsInvalid)
                {
                    continue;
                }

                int score = ScoreIfActuator(handle, out int outBytes);
                if (score == int.MinValue || outBytes <= 0)
                {
                    handle.Dispose();
                    continue;
                }

                Guid containerId = Guid.Empty;
                _ = TryGetContainerId(devInfo, ref devInfoData, out containerId);

                // We only needed the handle to read attributes/caps. Close it now to avoid holding extra opens.
                handle.Dispose();

                Candidate candidate = new(path, containerId, outBytes);
                int anyScore = score;
                if (anyScore > bestAnyScore)
                {
                    bestAny = candidate;
                    bestAnyScore = anyScore;
                }

                if (leftTarget.HasValue && containerId != Guid.Empty && containerId == leftTarget.Value)
                {
                    int leftScore = score + 1000;
                    if (leftScore > bestLeftScore)
                    {
                        bestLeft = candidate;
                        bestLeftScore = leftScore;
                    }
                }

                if (rightTarget.HasValue && containerId != Guid.Empty && containerId == rightTarget.Value)
                {
                    int rightScore = score + 1000;
                    if (rightScore > bestRightScore)
                    {
                        bestRight = candidate;
                        bestRightScore = rightScore;
                    }
                }
            }

            // Fallback: if we couldn't match container IDs, use the "best any" actuator.
            Candidate selectedLeft = string.IsNullOrWhiteSpace(bestLeft.Path) ? bestAny : bestLeft;
            Candidate selectedRight = string.IsNullOrWhiteSpace(bestRight.Path) ? bestAny : bestRight;
            if (selectedLeft.Path == null && selectedRight.Path == null)
            {
                return false;
            }

            // Open final selected handles.
            if (selectedLeft.Path != null)
            {
                if (!TryOpenHidPath(selectedLeft.Path, out SafeFileHandle? leftHandle) || leftHandle == null || leftHandle.IsInvalid)
                {
                    return false;
                }
                left = new ActuatorDevice { Handle = leftHandle, OutputReportBytes = selectedLeft.OutputReportBytes, ContainerId = selectedLeft.ContainerId };
            }

            if (selectedRight.Path != null)
            {
                if (selectedLeft.Path != null &&
                    selectedRight.Path.Equals(selectedLeft.Path, StringComparison.OrdinalIgnoreCase) &&
                    left != null)
                {
                    right = left;
                }
                else
                {
                    if (!TryOpenHidPath(selectedRight.Path, out SafeFileHandle? rightHandle) || rightHandle == null || rightHandle.IsInvalid)
                    {
                        left?.Handle.Dispose();
                        left = null;
                        return false;
                    }
                    right = new ActuatorDevice { Handle = rightHandle, OutputReportBytes = selectedRight.OutputReportBytes, ContainerId = selectedRight.ContainerId };
                }
            }

            return true;
        }
        finally
        {
            _ = SetupDiDestroyDeviceInfoList(devInfo);
        }
    }

    private readonly record struct Candidate(string? Path, Guid ContainerId, int OutputReportBytes);

    private static byte[] BuildPayload(int outputReportBytes, uint strength)
    {
        byte[] payload = new byte[Math.Max(outputReportBytes, 14)];
        payload[0] = ReportId;
        payload[1] = ReportCmd;
        payload[2] = (byte)(strength & 0xFF);
        payload[3] = (byte)((strength >> 8) & 0xFF);
        payload[4] = (byte)((strength >> 16) & 0xFF);
        payload[5] = (byte)((strength >> 24) & 0xFF);
        payload[6] = 0x21;
        payload[7] = 0x2B;
        payload[8] = 0x06;
        payload[9] = 0x01;
        payload[10] = 0x00;
        payload[11] = 0x16;
        payload[12] = 0x41;
        payload[13] = 0x13;
        return payload;
    }

    private static Guid? TryResolveContainerId(string? hidPath)
    {
        if (string.IsNullOrWhiteSpace(hidPath))
        {
            return null;
        }

        HidD_GetHidGuid(out Guid hidGuid);
        IntPtr devInfo = SetupDiGetClassDevsW(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DigcfPresent | DigcfDeviceInterface);
        if (devInfo == IntPtr.Zero || devInfo == new IntPtr(-1))
        {
            return null;
        }

        try
        {
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
                        return null;
                    }
                    return null;
                }

                index++;
                if (!TryGetInterfaceDetail(devInfo, ref iface, out string? path, out SP_DEVINFO_DATA devInfoData) || string.IsNullOrWhiteSpace(path))
                {
                    continue;
                }

                if (!path.Equals(hidPath, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (TryGetContainerId(devInfo, ref devInfoData, out Guid container))
                {
                    return container;
                }

                return null;
            }
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

            bool looksLikeActuator = caps.UsagePage == 0xFF00 && caps.Usage == 0x000D && caps.OutputReportByteLength >= 14;
            if (!looksLikeActuator)
            {
                return int.MinValue;
            }

            score += 100;
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

    private static bool TryGetInterfaceDetail(IntPtr devInfo, ref SP_DEVICE_INTERFACE_DATA iface, out string? devicePath, out SP_DEVINFO_DATA devInfoData)
    {
        devicePath = null;
        devInfoData = new SP_DEVINFO_DATA { cbSize = Marshal.SizeOf<SP_DEVINFO_DATA>() };

        _ = SetupDiGetDeviceInterfaceDetailW(devInfo, ref iface, IntPtr.Zero, 0, out uint required, IntPtr.Zero);
        int err = Marshal.GetLastWin32Error();
        if (err != ErrorInsufficientBuffer || required == 0)
        {
            return false;
        }

        IntPtr detail = Marshal.AllocHGlobal((int)required);
        try
        {
            int cbSize = IntPtr.Size == 8 ? 8 : 6;
            Marshal.WriteInt32(detail, cbSize);

            if (!SetupDiGetDeviceInterfaceDetailW(devInfo, ref iface, detail, required, out _, ref devInfoData))
            {
                return false;
            }

            IntPtr pathPtr = detail + 4;
            devicePath = Marshal.PtrToStringUni(pathPtr);
            return !string.IsNullOrWhiteSpace(devicePath);
        }
        finally
        {
            Marshal.FreeHGlobal(detail);
        }
    }

    private static bool TryGetContainerId(IntPtr devInfo, ref SP_DEVINFO_DATA devInfoData, out Guid containerId)
    {
        containerId = Guid.Empty;

        DEVPROPKEY key = DevpkeyDeviceContainerId;
        byte[] buffer = new byte[16];
        if (!SetupDiGetDevicePropertyW(devInfo, ref devInfoData, ref key, out _, buffer, (uint)buffer.Length, out uint required, 0))
        {
            return false;
        }

        if (required != 16)
        {
            return false;
        }

        containerId = new Guid(buffer);
        return containerId != Guid.Empty;
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

    private static readonly DEVPROPKEY DevpkeyDeviceContainerId = new(
        new Guid(0x8c7ed206, 0x3f8a, 0x4827, 0xb3, 0xab, 0xae, 0x9e, 0x1f, 0xae, 0xfc, 0x6c),
        2);

    [StructLayout(LayoutKind.Sequential)]
    private struct SP_DEVICE_INTERFACE_DATA
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SP_DEVINFO_DATA
    {
        public int cbSize;
        public Guid ClassGuid;
        public int DevInst;
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

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct DEVPROPKEY
    {
        public readonly Guid fmtid;
        public readonly uint pid;

        public DEVPROPKEY(Guid fmtid, uint pid)
        {
            this.fmtid = fmtid;
            this.pid = pid;
        }
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

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr deviceInfoSet, ref SP_DEVICE_INTERFACE_DATA deviceInterfaceData, IntPtr deviceInterfaceDetailData, uint deviceInterfaceDetailDataSize, out uint requiredSize, ref SP_DEVINFO_DATA deviceInfoData);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetupDiGetDevicePropertyW(
        IntPtr deviceInfoSet,
        ref SP_DEVINFO_DATA deviceInfoData,
        ref DEVPROPKEY propertyKey,
        out uint propertyType,
        [Out] byte[] propertyBuffer,
        uint propertyBufferSize,
        out uint requiredSize,
        uint flags);

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
