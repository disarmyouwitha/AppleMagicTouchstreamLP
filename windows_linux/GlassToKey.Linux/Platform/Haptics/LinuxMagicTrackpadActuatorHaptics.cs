using System.Diagnostics;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace GlassToKey.Platform.Linux.Haptics;

public sealed class LinuxMagicTrackpadActuatorHaptics : IDisposable
{
    private const byte ReportId = 0x53;
    private const byte ReportCommand = 0x01;
    private const int PayloadBytes = 14;

    private const int InitUninitialized = 0;
    private const int InitInProgress = 1;
    private const int InitReady = 2;
    private const int InitFailed = -1;

    private sealed class ActuatorDevice : IDisposable
    {
        public required FileStream Stream { get; init; }
        public required string DeviceNode { get; init; }
        public required int OutputReportBytes { get; init; }
        public byte[] Payload { get; set; } = Array.Empty<byte>();
        public long LastVibrateTicks;

        public void Dispose()
        {
            Stream.Dispose();
        }
    }

    private readonly object _gate = new();
    private int _initState;
    private string? _leftTouchHint;
    private string? _rightTouchHint;
    private ActuatorDevice? _left;
    private ActuatorDevice? _right;
    private bool _enabled;
    private uint _strength;
    private long _minIntervalTicks;

    public void Configure(bool enabled, uint strength, int minIntervalMs)
    {
        lock (_gate)
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

    public void SetRoutes(string? leftTouchHint, string? rightTouchHint)
    {
        lock (_gate)
        {
            if (string.Equals(_leftTouchHint, leftTouchHint, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(_rightTouchHint, rightTouchHint, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            _leftTouchHint = leftTouchHint;
            _rightTouchHint = rightTouchHint;
            DisposeDevicesNoLock();
            Volatile.Write(ref _initState, InitUninitialized);
        }
    }

    public void WarmupAsync()
    {
        lock (_gate)
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

        _ = ThreadPool.QueueUserWorkItem(static state =>
        {
            if (state is LinuxMagicTrackpadActuatorHaptics haptics)
            {
                haptics.TryEnsureInitialized();
            }
        }, this);
    }

    public bool TryVibrate(TrackpadSide side)
    {
        lock (_gate)
        {
            if (!_enabled)
            {
                return false;
            }
        }

        if (Volatile.Read(ref _initState) != InitReady)
        {
            WarmupAsync();
            return false;
        }

        lock (_gate)
        {
            ActuatorDevice? device = side == TrackpadSide.Right ? _right : _left;
            if (device == null)
            {
                return false;
            }

            long minInterval = Volatile.Read(ref _minIntervalTicks);
            long now = Stopwatch.GetTimestamp();
            if (minInterval > 0)
            {
                long last = device.LastVibrateTicks;
                if (now - last < minInterval)
                {
                    return false;
                }

                device.LastVibrateTicks = now;
            }

            try
            {
                device.Stream.Write(device.Payload);
                return true;
            }
            catch
            {
                DisposeDevicesNoLock();
                Volatile.Write(ref _initState, InitUninitialized);
                WarmupAsync();
                return false;
            }
        }
    }

    public static bool TryPulse(
        string touchHint,
        uint strength,
        int count,
        TimeSpan interval,
        out string message)
    {
        LinuxMagicTrackpadActuatorProbeResult probe = LinuxMagicTrackpadActuatorProbe.Probe(touchHint);
        if (!probe.Supported ||
            string.IsNullOrWhiteSpace(probe.HidrawDeviceNode))
        {
            message = probe.Status;
            return false;
        }

        try
        {
            using SafeFileHandle handle = File.OpenHandle(probe.HidrawDeviceNode, FileMode.Open, FileAccess.Write, FileShare.ReadWrite);
            using FileStream stream = new(handle, FileAccess.Write, bufferSize: 1, isAsync: false);
            byte[] payload = BuildPayload(probe.OutputReportBytes, strength);
            int pulseCount = Math.Max(1, count);
            for (int index = 0; index < pulseCount; index++)
            {
                stream.Write(payload);
                stream.Flush();
                if (index + 1 < pulseCount && interval > TimeSpan.Zero)
                {
                    Thread.Sleep(interval);
                }
            }

            message = $"Pulsed {pulseCount} time(s) through {probe.HidrawDeviceNode}.";
            return true;
        }
        catch (Exception ex)
        {
            message = ex.Message;
            return false;
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            DisposeDevicesNoLock();
            Volatile.Write(ref _initState, InitUninitialized);
        }
    }

    private void DisposeDevicesNoLock()
    {
        _left?.Dispose();
        if (_right != null && !ReferenceEquals(_right, _left))
        {
            _right.Dispose();
        }

        _left = null;
        _right = null;
    }

    private bool TryEnsureInitialized()
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
            string? leftHint;
            string? rightHint;
            uint strength;
            lock (_gate)
            {
                leftHint = _leftTouchHint;
                rightHint = _rightTouchHint;
                strength = _strength;
            }

            if (!TryOpenActuators(leftHint, rightHint, out ActuatorDevice? left, out ActuatorDevice? right))
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

            lock (_gate)
            {
                DisposeDevicesNoLock();
                _left = left;
                _right = right;
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

    private static bool TryOpenActuators(
        string? leftHint,
        string? rightHint,
        out ActuatorDevice? left,
        out ActuatorDevice? right)
    {
        left = TryOpenDevice(leftHint);
        right = TryOpenDevice(rightHint);
        if (left != null &&
            right != null &&
            string.Equals(left.DeviceNode, right.DeviceNode, StringComparison.OrdinalIgnoreCase))
        {
            right.Dispose();
            right = left;
        }

        return left != null || right != null;
    }

    private static ActuatorDevice? TryOpenDevice(string? touchHint)
    {
        LinuxMagicTrackpadActuatorProbeResult probe = LinuxMagicTrackpadActuatorProbe.Probe(touchHint);
        if (!probe.Supported ||
            !probe.CanOpenWrite ||
            string.IsNullOrWhiteSpace(probe.HidrawDeviceNode) ||
            probe.OutputReportBytes <= 1)
        {
            return null;
        }

        SafeFileHandle handle = File.OpenHandle(probe.HidrawDeviceNode, FileMode.Open, FileAccess.Write, FileShare.ReadWrite);
        FileStream stream = new(handle, FileAccess.Write, bufferSize: 1, isAsync: false);
        return new ActuatorDevice
        {
            Stream = stream,
            DeviceNode = probe.HidrawDeviceNode,
            OutputReportBytes = probe.OutputReportBytes
        };
    }

    private static byte[] BuildPayload(int outputReportBytes, uint strength)
    {
        _ = outputReportBytes;
        int payloadLength = PayloadBytes;
        byte[] payload = new byte[payloadLength];
        payload[0] = ReportId;
        payload[1] = ReportCommand;
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
}
