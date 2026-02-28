using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using GlassToKey;
using GlassToKey.Platform.Linux.Models;
using Microsoft.Win32.SafeHandles;

namespace GlassToKey.Platform.Linux.Evdev;

public sealed class LinuxEvdevReader
{
    private const int OpenReadOnly = 0x0000;
    private const int OpenNonBlocking = 0x0800;
    private const int ErrnoTryAgain = 11;
    private const ushort EventTypeSync = 0x00;
    private const ushort EventTypeKey = 0x01;
    private const ushort EventTypeAbsolute = 0x03;
    private const ushort SyncReport = 0x00;
    private const ushort ButtonLeft = 0x110;
    private const ushort AbsMtSlot = 0x2f;
    private const ushort AbsMtPositionX = 0x35;
    private const ushort AbsMtPositionY = 0x36;
    private const ushort AbsMtTrackingId = 0x39;
    private const ushort AbsMtPressure = 0x3a;
    private const ushort AbsMtOrientation = 0x34;

    public LinuxInputAxisInfo GetAxisInfo(string deviceNode, ushort axisCode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceNode);

        using var handle = File.OpenHandle(deviceNode, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        return GetAxisInfo(handle, axisCode);
    }

    public async Task<IReadOnlyList<string>> ReadRawEventsAsync(
        string deviceNode,
        TimeSpan duration,
        int maxEvents,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceNode);
        if (duration <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(duration));
        }

        if (maxEvents <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxEvents));
        }

        using SafeFileHandle handle = OpenNonBlockingHandle(deviceNode);
        List<string> events = [];
        byte[] buffer = new byte[InputEvent.Size];
        long deadlineTimestamp = Stopwatch.GetTimestamp() + (long)(duration.TotalSeconds * Stopwatch.Frequency);

        while (events.Count < maxEvents && !cancellationToken.IsCancellationRequested && Stopwatch.GetTimestamp() < deadlineTimestamp)
        {
            nint bytesRead = read(handle, buffer, (nuint)buffer.Length);
            if (bytesRead < 0)
            {
                int error = Marshal.GetLastWin32Error();
                if (error == ErrnoTryAgain)
                {
                    await Task.Delay(8, cancellationToken).ConfigureAwait(false);
                    continue;
                }

                throw new IOException($"read() failed for '{deviceNode}': {new Win32Exception(error).Message}");
            }

            if (bytesRead == 0)
            {
                await Task.Delay(8, cancellationToken).ConfigureAwait(false);
                continue;
            }

            if (bytesRead != InputEvent.Size)
            {
                throw new IOException($"Expected {InputEvent.Size} bytes from evdev but read {bytesRead}.");
            }

            InputEvent inputEvent = MemoryMarshal.Read<InputEvent>(buffer);
            events.Add(FormatRawEvent(inputEvent));
        }

        return events;
    }

    public async Task<IReadOnlyList<LinuxEvdevFrameSnapshot>> ReadFramesAsync(
        string deviceNode,
        TimeSpan duration,
        int maxFrames,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceNode);
        if (duration <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(duration));
        }

        if (maxFrames <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxFrames));
        }

        using SafeFileHandle handle = OpenNonBlockingHandle(deviceNode);
        int slotCount = 16;
        ushort maxX = ushort.MaxValue;
        ushort maxY = ushort.MaxValue;

        TryGetAxisMaximum(handle, AbsMtSlot, out LinuxInputAxisInfo? slotAxis);
        TryGetAxisMaximum(handle, AbsMtPositionX, out LinuxInputAxisInfo? xAxis);
        TryGetAxisMaximum(handle, AbsMtPositionY, out LinuxInputAxisInfo? yAxis);

        if (slotAxis != null)
        {
            slotCount = Math.Max(1, slotAxis.Maximum - slotAxis.Minimum + 1);
        }

        if (xAxis != null)
        {
            maxX = ClampAxisMaximum(xAxis.Maximum);
        }

        if (yAxis != null)
        {
            maxY = ClampAxisMaximum(yAxis.Maximum);
        }

        LinuxMtFrameAssembler assembler = new(slotCount, maxX, maxY);

        List<LinuxEvdevFrameSnapshot> frames = [];
        byte[] buffer = new byte[InputEvent.Size];
        long deadlineTimestamp = Stopwatch.GetTimestamp() + (long)(duration.TotalSeconds * Stopwatch.Frequency);

        while (frames.Count < maxFrames && !cancellationToken.IsCancellationRequested && Stopwatch.GetTimestamp() < deadlineTimestamp)
        {
            nint bytesRead;
            try
            {
                bytesRead = read(handle, buffer, (nuint)buffer.Length);
            }
            catch
            {
                break;
            }

            if (bytesRead < 0)
            {
                int error = Marshal.GetLastWin32Error();
                if (error == ErrnoTryAgain)
                {
                    await Task.Delay(8, cancellationToken).ConfigureAwait(false);
                    continue;
                }

                throw new IOException($"read() failed for '{deviceNode}': {new Win32Exception(error).Message}");
            }

            if (bytesRead == 0)
            {
                await Task.Delay(8, cancellationToken).ConfigureAwait(false);
                continue;
            }

            if (bytesRead != InputEvent.Size)
            {
                throw new IOException($"Expected {InputEvent.Size} bytes from evdev but read {bytesRead}.");
            }

            InputEvent inputEvent = MemoryMarshal.Read<InputEvent>(buffer);
            if (ApplyEvent(assembler, in inputEvent))
            {
                frames.Add(new LinuxEvdevFrameSnapshot(
                    DeviceNode: deviceNode,
                    MaxX: maxX,
                    MaxY: maxY,
                    FrameSequence: assembler.FrameSequence,
                    Frame: assembler.CommitFrame(ToStopwatchTicks(inputEvent))));
            }
        }

        return frames;
    }

    private static bool ApplyEvent(LinuxMtFrameAssembler assembler, in InputEvent inputEvent)
    {
        switch (inputEvent.Type)
        {
            case EventTypeAbsolute:
                ApplyAbsoluteEvent(assembler, inputEvent.Code, inputEvent.Value);
                return false;
            case EventTypeKey:
                if (inputEvent.Code == ButtonLeft)
                {
                    assembler.SetButtonPressed(inputEvent.Value != 0);
                }

                return false;
            case EventTypeSync:
                return inputEvent.Code == SyncReport;
            default:
                return false;
        }
    }

    private static void ApplyAbsoluteEvent(LinuxMtFrameAssembler assembler, ushort code, int value)
    {
        switch (code)
        {
            case AbsMtSlot:
                assembler.SelectSlot(value);
                break;
            case AbsMtTrackingId:
                assembler.SetTrackingId(value);
                break;
            case AbsMtPositionX:
                assembler.SetPositionX(value);
                break;
            case AbsMtPositionY:
                assembler.SetPositionY(value);
                break;
            case AbsMtPressure:
                assembler.SetPressure(value);
                break;
            case AbsMtOrientation:
                assembler.SetOrientation(value);
                break;
        }
    }

    private static LinuxInputAxisInfo GetAxisInfo(SafeFileHandle handle, ushort axisCode)
    {
        InputAbsInfo absInfo = default;
        int result = ioctl(handle, ComputeEviocgabs(axisCode), ref absInfo);
        if (result < 0)
        {
            throw new IOException($"EVIOCGABS(0x{axisCode:x2}) failed: {new Win32Exception(Marshal.GetLastWin32Error()).Message}");
        }

        return new LinuxInputAxisInfo(absInfo.Value, absInfo.Minimum, absInfo.Maximum, absInfo.Fuzz, absInfo.Flat, absInfo.Resolution);
    }

    private static bool TryGetAxisMaximum(SafeFileHandle handle, ushort axisCode, out LinuxInputAxisInfo? axisInfo)
    {
        try
        {
            axisInfo = GetAxisInfo(handle, axisCode);
            return true;
        }
        catch
        {
            axisInfo = null;
            return false;
        }
    }

    private static SafeFileHandle OpenNonBlockingHandle(string deviceNode)
    {
        int fd = open(deviceNode, OpenReadOnly | OpenNonBlocking);
        if (fd < 0)
        {
            throw new IOException($"open() failed for '{deviceNode}': {new Win32Exception(Marshal.GetLastWin32Error()).Message}");
        }

        return new SafeFileHandle((IntPtr)fd, ownsHandle: true);
    }

    private static ushort ClampAxisMaximum(int maximum)
    {
        if (maximum <= 0)
        {
            return ushort.MaxValue;
        }

        return (ushort)Math.Min(maximum, ushort.MaxValue);
    }

    private static long ToStopwatchTicks(InputEvent inputEvent)
    {
        long microseconds = checked((inputEvent.Seconds * 1_000_000L) + inputEvent.Microseconds);
        return (microseconds * Stopwatch.Frequency) / 1_000_000L;
    }

    private static string FormatRawEvent(InputEvent inputEvent)
    {
        return $"{inputEvent.Seconds}.{inputEvent.Microseconds:D6} type=0x{inputEvent.Type:x2} code=0x{inputEvent.Code:x2} value={inputEvent.Value}";
    }

    private static ulong ComputeEviocgabs(int axisCode)
    {
        const int iocRead = 2;
        const int iocNrShift = 0;
        const int iocTypeShift = 8;
        const int iocSizeShift = 16;
        const int iocDirShift = 30;
        int requestNumber = 0x40 + axisCode;
        int size = Marshal.SizeOf<InputAbsInfo>();
        return ((ulong)iocRead << iocDirShift) |
               ((ulong)'E' << iocTypeShift) |
               ((ulong)requestNumber << iocNrShift) |
               ((ulong)size << iocSizeShift);
    }

    [DllImport("libc", SetLastError = true)]
    private static extern int ioctl(SafeFileHandle fd, ulong request, ref InputAbsInfo value);

    [DllImport("libc", SetLastError = true)]
    private static extern int open(string pathname, int flags);

    [DllImport("libc", SetLastError = true)]
    private static extern nint read(SafeFileHandle fd, byte[] buffer, nuint count);

    [StructLayout(LayoutKind.Sequential)]
    private struct InputAbsInfo
    {
        public int Value;
        public int Minimum;
        public int Maximum;
        public int Fuzz;
        public int Flat;
        public int Resolution;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct InputEvent
    {
        public const int Size = 24;

        public readonly long Seconds;
        public readonly long Microseconds;
        public readonly ushort Type;
        public readonly ushort Code;
        public readonly int Value;
    }
}
