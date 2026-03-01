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
    private const ushort ButtonToolFinger = 0x145;
    private const ushort ButtonTouch = 0x14a;
    private const ushort AbsX = 0x00;
    private const ushort AbsY = 0x01;
    private const ushort AbsPressure = 0x18;
    private const ushort AbsMtTouchMajor = 0x30;
    private const ushort AbsMtTouchMinor = 0x31;
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

    public LinuxTrackpadAxisProfile GetAxisProfile(string deviceNode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceNode);

        using var handle = File.OpenHandle(deviceNode, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        return GetAxisProfile(handle);
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

        List<LinuxEvdevFrameSnapshot> frames = [];
        long deadlineTimestamp = Stopwatch.GetTimestamp() + (long)(duration.TotalSeconds * Stopwatch.Frequency);
        await StreamFramesAsync(
            deviceNode,
            snapshot =>
            {
                if (frames.Count >= maxFrames || Stopwatch.GetTimestamp() >= deadlineTimestamp)
                {
                    return ValueTask.FromResult(false);
                }

                frames.Add(snapshot);
                return ValueTask.FromResult(frames.Count < maxFrames && Stopwatch.GetTimestamp() < deadlineTimestamp);
            },
            cancellationToken).ConfigureAwait(false);

        return frames;
    }

    public async Task StreamFramesAsync(
        string deviceNode,
        Func<LinuxEvdevFrameSnapshot, ValueTask<bool>> onFrame,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceNode);
        ArgumentNullException.ThrowIfNull(onFrame);

        using SafeFileHandle handle = OpenNonBlockingHandle(deviceNode);
        LinuxTrackpadAxisProfile axisProfile = GetAxisProfile(handle);
        LinuxMtFrameAssembler assembler = new(axisProfile.SlotCount, axisProfile.MaxX, axisProfile.MaxY);
        byte[] buffer = new byte[InputEvent.Size];

        while (!cancellationToken.IsCancellationRequested)
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
                    try
                    {
                        await Task.Delay(8, cancellationToken).ConfigureAwait(false);
                    }
                    catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                    {
                        break;
                    }

                    continue;
                }

                throw new IOException($"read() failed for '{deviceNode}': {new Win32Exception(error).Message}");
            }

            if (bytesRead == 0)
            {
                try
                {
                    await Task.Delay(8, cancellationToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    break;
                }

                continue;
            }

            if (bytesRead != InputEvent.Size)
            {
                throw new IOException($"Expected {InputEvent.Size} bytes from evdev but read {bytesRead}.");
            }

            InputEvent inputEvent = MemoryMarshal.Read<InputEvent>(buffer);
            if (!ApplyEvent(assembler, axisProfile, in inputEvent))
            {
                continue;
            }

            LinuxEvdevFrameSnapshot snapshot = new(
                DeviceNode: deviceNode,
                MinX: axisProfile.MinX,
                MinY: axisProfile.MinY,
                MaxX: axisProfile.MaxX,
                MaxY: axisProfile.MaxY,
                FrameSequence: assembler.FrameSequence,
                Frame: assembler.CommitFrame(ToStopwatchTicks(inputEvent)));
            bool shouldContinue = await onFrame(snapshot).ConfigureAwait(false);
            if (!shouldContinue)
            {
                break;
            }
        }
    }

    private static bool ApplyEvent(LinuxMtFrameAssembler assembler, LinuxTrackpadAxisProfile axisProfile, in InputEvent inputEvent)
    {
        switch (inputEvent.Type)
        {
            case EventTypeAbsolute:
                ApplyAbsoluteEvent(assembler, axisProfile, inputEvent.Code, inputEvent.Value);
                return false;
            case EventTypeKey:
                if (inputEvent.Code == ButtonLeft)
                {
                    assembler.SetButtonPressed(inputEvent.Value != 0);
                }
                else if (inputEvent.Code == ButtonTouch || inputEvent.Code == ButtonToolFinger)
                {
                    assembler.SetLegacyTouchActive(inputEvent.Value != 0);
                }

                return false;
            case EventTypeSync:
                return inputEvent.Code == SyncReport;
            default:
                return false;
        }
    }

    private static void ApplyAbsoluteEvent(LinuxMtFrameAssembler assembler, LinuxTrackpadAxisProfile axisProfile, ushort code, int value)
    {
        switch (code)
        {
            case AbsX:
                assembler.SetLegacyPositionX(axisProfile.NormalizeX(value));
                break;
            case AbsY:
                assembler.SetLegacyPositionY(axisProfile.NormalizeY(value));
                break;
            case AbsPressure:
                assembler.SetLegacyPressure(value);
                break;
            case AbsMtTouchMajor:
                assembler.SetLegacyTouchMajor(value);
                break;
            case AbsMtTouchMinor:
                assembler.SetLegacyTouchMinor(value);
                break;
            case AbsMtSlot:
                assembler.SelectSlot(value);
                break;
            case AbsMtTrackingId:
                assembler.SetTrackingId(value);
                break;
            case AbsMtPositionX:
                assembler.SetPositionX(axisProfile.NormalizeX(value));
                break;
            case AbsMtPositionY:
                assembler.SetPositionY(axisProfile.NormalizeY(value));
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

    private static LinuxTrackpadAxisProfile GetAxisProfile(SafeFileHandle handle)
    {
        LinuxInputAxisInfo? slotAxis = TryGetAxisInfo(handle, AbsMtSlot);
        LinuxInputAxisInfo? mtX = TryGetAxisInfo(handle, AbsMtPositionX);
        LinuxInputAxisInfo? mtY = TryGetAxisInfo(handle, AbsMtPositionY);
        LinuxInputAxisInfo? legacyX = TryGetAxisInfo(handle, AbsX);
        LinuxInputAxisInfo? legacyY = TryGetAxisInfo(handle, AbsY);
        LinuxInputAxisInfo? mtPressure = TryGetAxisInfo(handle, AbsMtPressure);
        LinuxInputAxisInfo? legacyPressure = TryGetAxisInfo(handle, AbsPressure);

        LinuxInputAxisInfo? xAxis = mtX ?? legacyX;
        LinuxInputAxisInfo? yAxis = mtY ?? legacyY;
        LinuxInputAxisInfo? pressureAxis = mtPressure ?? legacyPressure;
        if (xAxis == null || yAxis == null)
        {
            throw new IOException("Trackpad device does not expose usable X/Y absolute axes.");
        }

        return new LinuxTrackpadAxisProfile(
            Slot: slotAxis,
            X: xAxis,
            Y: yAxis,
            Pressure: pressureAxis,
            UsesMtPositionAxes: mtX != null && mtY != null,
            UsesLegacyPositionAxes: mtX == null || mtY == null);
    }

    private static LinuxInputAxisInfo? TryGetAxisInfo(SafeFileHandle handle, ushort axisCode)
    {
        try
        {
            return GetAxisInfo(handle, axisCode);
        }
        catch
        {
            return null;
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
