using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using WinForms = System.Windows.Forms;

namespace GlassToKey;

// Isolated, opt-in probe. It never starts the typing engine or saves settings.
internal sealed class PtpTakeoverDiagnostic : IDisposable
{
    private readonly string _logPath;
    private readonly bool _gateRequested;
    private readonly bool _osToggleRequested;
    private readonly Action _finished;
    private readonly ConcurrentQueue<string> _lines = new();
    private readonly Dictionary<string, long> _rawCounts = new();
    private readonly Dictionary<string, long> _activeContactCounts = new();
    private readonly RawInputContext _rawContext = new();
    private readonly GlobalMouseInputHook _hook = new();
    private readonly Stopwatch _elapsed = new();
    private Sink? _sink;
    private DispatcherTimer? _timer;
    private bool _gateStarted;
    private bool _gateCompleted;
    private bool _syntheticSent;
    private bool _osToggleSent;
    private bool _osRestoreSent;
    private bool _osToggleSkipped;
    private double _osToggleStartSeconds;
    private long _lastActiveContactTicks;
    private bool? _lastOsEnabled;
    private POINT? _lastCursor;
    private bool _disposed;

    public PtpTakeoverDiagnostic(string logPath, bool gateRequested, bool osToggleRequested, Action finished)
    {
        _logPath = Path.GetFullPath(logPath);
        _gateRequested = gateRequested;
        _osToggleRequested = osToggleRequested;
        _finished = finished;
    }

    public void Start()
    {
        try
        {
            File.WriteAllText(_logPath, string.Empty);
            if (PtpSystemTouchpad.TryGetStatus(out PtpStatus initial))
                Queue($"PTP_STATUS initial present={initial.Present} enabled={initial.Enabled} active={initial.Active} externalMouse={initial.ExternalMousePresent}");
            if (_osToggleRequested)
            {
                if (!PtpSystemTouchpad.TryGetStatus(out initial) || !initial.Present || !initial.Enabled)
                    throw new InvalidOperationException("PTP status is unavailable or input was already disabled; refusing toggle probe.");
                string? executable = Environment.ProcessPath;
                if (string.IsNullOrEmpty(executable) || !executable.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Toggle probe requires the built Windows executable so its independent restore watchdog can start.");
                ProcessStartInfo watchdog = new(executable) { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden };
                watchdog.ArgumentList.Add("--ptp-restore-watchdog");
                watchdog.ArgumentList.Add(_logPath + ".watchdog.log");
                if (Process.Start(watchdog) == null)
                    throw new InvalidOperationException("Restore watchdog failed to start.");
                Queue("WATCHDOG started before global toggle");
            }
            HidDeviceInfo[] devices = RawInputInterop.EnumerateTrackpads();
            _rawContext.SeedTags(devices);
            _sink = new Sink(this);
            _sink.Create();
            if (!RawInputInterop.RegisterForTouchpadRawInput(_sink.Handle, out string? rawError))
                throw new InvalidOperationException($"Raw Input registration failed: {rawError}");
            _hook.DiagnosticEvent += OnMouse;
            if (!_hook.Install(out string? hookError))
                throw new InvalidOperationException($"Mouse hook install failed: {hookError}");
            Queue($"START utc={DateTime.UtcNow:O} gate={_gateRequested} osToggle={_osToggleRequested} devices={devices.Length}");
            foreach (HidDeviceInfo device in devices)
                Queue($"DEVICE tag={device.DeviceIndex}:{device.DeviceHash:X8} path={device.Path}");
            _elapsed.Start();
            _timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(50) };
            _timer.Tick += Tick;
            _timer.Start();
        }
        catch (Exception ex)
        {
            Queue($"STARTUP_FAULT {ex}");
            Dispose();
            throw;
        }
    }

    private void OnMouse(MouseHookDiagnosticEvent e)
    {
        Queue($"MOUSE ticks={e.StopwatchTicks} msg=0x{e.Message:X4} x={e.X} y={e.Y} data=0x{e.MouseData:X8} flags=0x{e.Flags:X8} winTime={e.WindowsTime} extra=0x{e.ExtraInfo:X} gate={_gateStarted && _elapsed.Elapsed < TimeSpan.FromSeconds(15)}");
    }

    private void OnRawInput(IntPtr lParam)
    {
        if (!RawInputInterop.TryGetRawInputPacket(lParam, out RawInputPacket packet) ||
            !_rawContext.TryGetSnapshot(packet.DeviceHandle, out RawInputDeviceSnapshot device) ||
            !RawInputInterop.IsTargetDevice(device.Info))
            return;
        for (uint i = 0; i < packet.ReportCount; i++)
        {
            int offset = packet.DataOffset + (int)(i * packet.ReportSize);
            if (offset + packet.ReportSize > packet.ValidLength) break;
            string countKey = $"{device.Tag.Index}:{device.Tag.Hash:X8} id=0x{packet.Buffer[offset]:X2} size={packet.ReportSize} osEnabled={_lastOsEnabled}";
            _rawCounts[countKey] = _rawCounts.GetValueOrDefault(countKey) + 1;
            int? contacts = packet.ReportSize == 50 && packet.Buffer[offset] == 0x05
                ? packet.Buffer[offset + 48] : null;
            if (contacts > 0)
            {
                _activeContactCounts[countKey] = _activeContactCounts.GetValueOrDefault(countKey) + 1;
                _lastActiveContactTicks = Stopwatch.GetTimestamp();
            }
            string hex = _osToggleRequested && contacts.HasValue
                ? $" hex={Convert.ToHexString(packet.Buffer.AsSpan(offset, 50))}" : string.Empty;
            Queue($"RAW ticks={Stopwatch.GetTimestamp()} tag={device.Tag.Index}:{device.Tag.Hash:X8} usage={device.Info.UsagePage:X4}/{device.Info.Usage:X4} size={packet.ReportSize} id=0x{packet.Buffer[offset]:X2} contacts={contacts} osEnabled={_lastOsEnabled}{hex}");
        }
    }

    private void Tick(object? sender, EventArgs e)
    {
        try
        {
            // Escape is a keyboard-only release; the hook deadline also fails open.
            if ((GetAsyncKeyState(0x1B) & 0x8000) != 0)
            {
                Queue("RELEASE escape");
                _hook.ReleaseMovementGate();
                Finish();
                return;
            }
            double seconds = _elapsed.Elapsed.TotalSeconds;
            if (PtpSystemTouchpad.TryGetStatus(out PtpStatus osStatus))
            {
                if (_lastOsEnabled != osStatus.Enabled)
                    Queue($"PTP_STATUS second={seconds:F2} enabled={osStatus.Enabled} active={osStatus.Active} externalMouse={osStatus.ExternalMousePresent}");
                _lastOsEnabled = osStatus.Enabled;
            }
            if (GetCursorPos(out POINT cursor) && (!_lastCursor.HasValue || !_lastCursor.Value.Equals(cursor)))
            {
                Queue($"CURSOR second={seconds:F2} x={cursor.X} y={cursor.Y} osEnabled={_lastOsEnabled}");
                _lastCursor = cursor;
            }
            bool recentActiveContact = _lastActiveContactTicks > 0 &&
                Stopwatch.GetTimestamp() - _lastActiveContactTicks < Stopwatch.Frequency / 3;
            if (_osToggleRequested && !_osToggleSent && seconds >= 5 && seconds <= 12 && recentActiveContact)
            {
                File.AppendAllText(_logPath + ".watchdog.log", "WATCHDOG_ARMED" + Environment.NewLine);
                _osToggleSent = true;
                _osToggleStartSeconds = seconds;
                Queue($"OS_TOGGLE_OFF sent={PtpSystemTouchpad.SendDocumentedToggle()}");
            }
            if (_osToggleRequested && !_osToggleSent && !_osToggleSkipped && seconds > 12)
            {
                _osToggleSkipped = true;
                Queue("OS_TOGGLE_SKIPPED no live contact in the 5-12 second trigger window");
            }
            if (_osToggleSent && !_osRestoreSent && seconds >= _osToggleStartSeconds + 10)
            {
                _osRestoreSent = true;
                Queue($"OS_RESTORE sent={RestoreOsTouchpadIfNeeded()}");
            }
            if (_gateRequested && !_gateStarted && !_gateCompleted && seconds >= 5)
            {
                _hook.GatePhysicalMovementFor(TimeSpan.FromSeconds(10));
                _gateStarted = true;
                Queue("GATE on; expires automatically after 10 seconds");
            }
            if ((_gateStarted && seconds >= 8 || _osToggleSent && seconds >= _osToggleStartSeconds + 3) && !_syntheticSent)
            {
                _syntheticSent = true;
                INPUT[] input = { new() { type = 0, mouse = new MOUSEINPUT { dx = 20, dy = 0, dwFlags = 0x0001, dwExtraInfo = (UIntPtr)0x47544B50 } } };
                uint sent = SendInput(1, input, Marshal.SizeOf<INPUT>());
                Queue($"SYNTHETIC_MOVE sent={sent} error={Marshal.GetLastWin32Error()}");
            }
            if (_gateStarted && seconds >= 15)
            {
                _hook.ReleaseMovementGate();
                Queue("GATE off");
                _gateStarted = false;
                _gateCompleted = true;
            }
            Flush();
            if (seconds >= 25) Finish();
        }
        catch (Exception ex)
        {
            _hook.ReleaseMovementGate();
            Queue($"FAULT {ex}");
            Finish();
        }
    }

    private void Queue(string line) => _lines.Enqueue(line);

    private void Flush()
    {
        using StreamWriter writer = new(_logPath, append: true);
        while (_lines.TryDequeue(out string? line)) writer.WriteLine(line);
    }

    private void Finish()
    {
        Dispose();
        _finished();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _hook.ReleaseMovementGate();
        if (_osToggleSent)
            Queue($"OS_DISPOSE_RESTORE sent={RestoreOsTouchpadIfNeeded()}");
        _timer?.Stop();
        _timer = null;
        _hook.Dispose();
        _sink?.Dispose();
        _sink = null;
        foreach (KeyValuePair<string, long> count in _rawCounts)
            Queue($"RAW_COUNT {count.Key} count={count.Value}");
        foreach (KeyValuePair<string, long> count in _activeContactCounts)
            Queue($"ACTIVE_CONTACT_FRAME_COUNT {count.Key} count={count.Value}");
        Queue($"END utc={DateTime.UtcNow:O}");
        try { Flush(); } catch { /* Input has already been released. */ }
    }

    private static bool RestoreOsTouchpadIfNeeded()
    {
        return PtpSystemTouchpad.TryGetStatus(out PtpStatus status) &&
            (status.Enabled || PtpSystemTouchpad.SendDocumentedToggle());
    }

    private sealed class Sink : WinForms.NativeWindow, IDisposable
    {
        private readonly PtpTakeoverDiagnostic _owner;
        public Sink(PtpTakeoverDiagnostic owner) => _owner = owner;
        public void Create() => CreateHandle(new WinForms.CreateParams { Caption = "GlassToKeyPtpDiagnostic", X = -32000, Y = -32000, Width = 1, Height = 1 });
        protected override void WndProc(ref WinForms.Message m)
        {
            if (m.Msg == RawInputInterop.WM_INPUT) _owner.OnRawInput(m.LParam);
            base.WndProc(ref m);
        }
        public void Dispose() { if (Handle != IntPtr.Zero) DestroyHandle(); }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public UIntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public MOUSEINPUT mouse; }
    [StructLayout(LayoutKind.Sequential)]
    private readonly struct POINT
    {
        public readonly int X;
        public readonly int Y;
    }
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int virtualKey);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, INPUT[] inputs, int size);
}
