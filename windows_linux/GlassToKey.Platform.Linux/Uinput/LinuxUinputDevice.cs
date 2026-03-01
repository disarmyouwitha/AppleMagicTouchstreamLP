using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace GlassToKey.Platform.Linux.Uinput;

internal sealed class LinuxUinputDevice : IDisposable
{
    private const string DefaultDeviceNode = "/dev/uinput";
    private const int BusUsb = 0x03;
    private const uint IoctlTypeUinput = (uint)'U';
    private const uint IoctlDirNone = 0;
    private const uint IoctlDirWrite = 1;
    private const int DeviceReadyDelayMs = 150;
    private static readonly uint UiDevCreate = ComputeIo(1);
    private static readonly uint UiDevDestroy = ComputeIo(2);
    private static readonly uint UiDevSetup = ComputeIoWrite(3, Marshal.SizeOf<UinputSetup>());
    private static readonly uint UiSetEvBit = ComputeIoWrite(100, sizeof(int));
    private static readonly uint UiSetKeyBit = ComputeIoWrite(101, sizeof(int));
    private static readonly uint UiSetRelBit = ComputeIoWrite(102, sizeof(int));

    private readonly SafeFileHandle _handle;
    private readonly FileStream _stream;
    private bool _disposed;

    public LinuxUinputDevice(string deviceName = "GlassToKey Virtual Input", string deviceNode = DefaultDeviceNode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceName);
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceNode);

        _handle = File.OpenHandle(deviceNode, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite);
        _stream = new FileStream(_handle, FileAccess.Write, bufferSize: 1);
        try
        {
            ConfigureCapabilities();
            SetupDevice(deviceName);
            InvokeIoctl(UiDevCreate, 0);
            Thread.Sleep(DeviceReadyDelayMs);
        }
        catch
        {
            _stream.Dispose();
            _handle.Dispose();
            throw;
        }
    }

    public void EmitKey(ushort keyCode, bool isDown)
    {
        Emit(LinuxEvdevCodes.EventKey, keyCode, isDown ? 1 : 0);
        Sync();
    }

    public void EmitClick(ushort buttonCode)
    {
        Emit(LinuxEvdevCodes.EventKey, buttonCode, 1);
        Emit(LinuxEvdevCodes.EventSync, LinuxEvdevCodes.SyncReport, 0);
        Emit(LinuxEvdevCodes.EventKey, buttonCode, 0);
        Sync();
    }

    public void Sync()
    {
        Emit(LinuxEvdevCodes.EventSync, LinuxEvdevCodes.SyncReport, 0);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        try
        {
            InvokeIoctl(UiDevDestroy, 0);
        }
        catch
        {
            // Best-effort cleanup.
        }

        _stream.Dispose();
    }

    private void ConfigureCapabilities()
    {
        InvokeIoctl(UiSetEvBit, LinuxEvdevCodes.EventKey);
        InvokeIoctl(UiSetEvBit, LinuxEvdevCodes.EventRelative);
        InvokeIoctl(UiSetRelBit, LinuxEvdevCodes.RelativeX);
        InvokeIoctl(UiSetRelBit, LinuxEvdevCodes.RelativeY);

        for (int keyCode = LinuxEvdevCodes.KeyEsc; keyCode <= 255; keyCode++)
        {
            InvokeIoctl(UiSetKeyBit, keyCode);
        }

        InvokeIoctl(UiSetKeyBit, LinuxEvdevCodes.KeyBrightnessDown);
        InvokeIoctl(UiSetKeyBit, LinuxEvdevCodes.KeyBrightnessUp);
        InvokeIoctl(UiSetKeyBit, LinuxEvdevCodes.ButtonLeft);
        InvokeIoctl(UiSetKeyBit, LinuxEvdevCodes.ButtonRight);
        InvokeIoctl(UiSetKeyBit, LinuxEvdevCodes.ButtonMiddle);
    }

    private void SetupDevice(string deviceName)
    {
        UinputSetup setup = new()
        {
            Id = new InputId
            {
                BusType = BusUsb,
                Vendor = 0x1D6B,
                Product = 0x1050,
                Version = 1
            },
            Name = deviceName,
            ForceFeedbackEffectsMax = 0
        };

        int result = ioctl(_handle, UiDevSetup, ref setup);
        if (result < 0)
        {
            throw new IOException($"UI_DEV_SETUP failed: {new Win32Exception(Marshal.GetLastWin32Error()).Message}");
        }
    }

    private void Emit(ushort eventType, ushort code, int value)
    {
        InputEvent inputEvent = new()
        {
            Type = eventType,
            Code = code,
            Value = value
        };

        ReadOnlySpan<InputEvent> span = MemoryMarshal.CreateReadOnlySpan(ref inputEvent, 1);
        ReadOnlySpan<byte> bytes = MemoryMarshal.AsBytes(span);
        _stream.Write(bytes);
    }

    private void InvokeIoctl(uint request, int value)
    {
        int result = ioctl(_handle, request, value);
        if (result < 0)
        {
            throw new IOException($"ioctl(0x{request:x}) failed: {new Win32Exception(Marshal.GetLastWin32Error()).Message}");
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct InputId
    {
        public ushort BusType;
        public ushort Vendor;
        public ushort Product;
        public ushort Version;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct UinputSetup
    {
        public InputId Id;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string Name;

        public uint ForceFeedbackEffectsMax;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct InputEvent
    {
        public long Seconds;
        public long Microseconds;
        public ushort Type;
        public ushort Code;
        public int Value;
    }

    [DllImport("libc", SetLastError = true)]
    private static extern int ioctl(SafeFileHandle fd, uint request, int value);

    [DllImport("libc", SetLastError = true)]
    private static extern int ioctl(SafeFileHandle fd, uint request, ref UinputSetup setup);

    private static uint ComputeIo(byte number)
    {
        return ComputeIoctl(IoctlDirNone, number, 0);
    }

    private static uint ComputeIoWrite(byte number, int size)
    {
        return ComputeIoctl(IoctlDirWrite, number, size);
    }

    private static uint ComputeIoctl(uint direction, byte number, int size)
    {
        return (direction << 30) |
               ((uint)size << 16) |
               (IoctlTypeUinput << 8) |
               number;
    }
}
