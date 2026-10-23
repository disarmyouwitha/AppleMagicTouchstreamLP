using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using Microsoft.Win32;
using WinForms = System.Windows.Forms;

namespace GlassToKey;

// Session-only app control. UI heartbeat renews a short, independently expiring hook lease.
internal sealed class MouseTakeoverController : IDisposable
{
    private const int HotkeyId = 0x474b;
    private readonly GlobalMouseInputHook _hook;
    private readonly Func<bool> _hasSelectedDevice;
    private readonly object _sync = new();
    private readonly DispatcherTimer _heartbeat = new(DispatcherPriority.Normal) { Interval = TimeSpan.FromMilliseconds(200) };
    private System.Threading.Timer? _watchdog;
    private ShortcutWindow? _window;
    private bool _available, _enabled, _disposed;
    private long _testDeadline, _nextDeviceCheck;
    private string _status = "Off";
    private string? _pendingRelease;
    public event Action? StateChanged;

    public MouseTakeoverController(GlobalMouseInputHook hook, Func<bool> hasSelectedDevice)
    {
        _hook = hook; _hasSelectedDevice = hasSelectedDevice;
        _heartbeat.Tick += OnHeartbeat;
    }

    public bool Enabled { get { lock (_sync) return _enabled && _hook.IsMouseTakeoverActive; } }
    public bool Available { get { lock (_sync) return _available && !_disposed; } }
    public string Status
    {
        get
        {
            lock (_sync)
            {
                if (_enabled && _hook.IsMouseTakeoverActive)
                    return _testDeadline == 0 ? "On · all physical mice blocked" : $"On · {Math.Max(0, Math.Ceiling((_testDeadline - Stopwatch.GetTimestamp()) / (double)Stopwatch.Frequency))}s test";
                return _status;
            }
        }
    }

    public void Start()
    {
        try
        {
            if (!_hook.IsInstalled && !_hook.Install(out string? error))
                throw new InvalidOperationException("Mouse hook unavailable: " + error);
            _window = new ShortcutWindow(this);
            _window.Create();
            if (!RegisterHotKey(_window.Handle, HotkeyId, 0x4003, 0x52))
                throw new InvalidOperationException("Ctrl+Alt+R unavailable (error " + Marshal.GetLastWin32Error() + "). Close other takeover windows/apps using this shortcut, then restart GlassToKey.");
            _hook.SetTakeoverReleaseKey(0x52);
            _hook.SetTakeoverEscapeReleaseEnabled(false);
            _available = true;
            SystemEvents.PowerModeChanged += OnPowerModeChanged;
            SystemEvents.SessionSwitch += OnSessionSwitch;
            _heartbeat.Start();
            _watchdog = new System.Threading.Timer(CheckEmergencyRelease, null, 100, 100);
        }
        catch (Exception ex)
        {
            Release("Unavailable: " + ex.Message);
            _available = false;
            _heartbeat.Stop(); _watchdog?.Dispose();
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            SystemEvents.SessionSwitch -= OnSessionSwitch;
            _window?.Dispose(); _window = null;
        }
    }

    public void SetEnabled(bool enabled, bool thirtySecondTest = false)
    {
        if (!enabled) { Release("Off"); return; }
        try
        {
            if (!Available) return;
            if (!_hasSelectedDevice()) { Release("Off · select a connected trackpad first"); return; }
            foreach (int key in new[] { 1, 2, 4, 5, 6 })
                if ((GetAsyncKeyState(key) & 0x8000) != 0) { Release("Off · release mouse buttons first"); return; }
            lock (_sync)
            {
                long now = Stopwatch.GetTimestamp();
                _testDeadline = thirtySecondTest ? now + 30 * Stopwatch.Frequency : 0;
                _pendingRelease = null; _nextDeviceCheck = now;
                _hook.GatePhysicalMouseFor(TimeSpan.FromSeconds(2));
                _enabled = true;
            }
            NotifyChanged();
        }
        catch (Exception ex) { Release("Off · " + ex.Message); }
    }

    public void Release(string reason)
    {
        lock (_sync)
        {
            _hook.ReleaseMouseTakeover();
            _enabled = false; _testDeadline = 0; _pendingRelease = null; _status = reason;
        }
        NotifyChanged();
    }

    private void NotifyChanged()
    {
        try { StateChanged?.Invoke(); } catch { /* Status observers must not prevent release. */ }
    }

    private void RequestRelease(string reason)
    {
        lock (_sync)
        {
            if (!_enabled) return;
            _hook.ReleaseMouseTakeover(); _pendingRelease = reason;
        }
    }

    private void OnHeartbeat(object? sender, EventArgs e)
    {
        try
        {
            bool checkDevice;
            lock (_sync)
            {
                if (!_enabled) return;
                if (_pendingRelease != null) { Release(_pendingRelease); return; }
                long now = Stopwatch.GetTimestamp();
                if (!_hook.IsMouseTakeoverActive) { Release("Off · input watchdog released"); return; }
                if (_testDeadline != 0 && now >= _testDeadline) { Release("Off · 30sec test complete"); return; }
                checkDevice = now >= _nextDeviceCheck;
                if (checkDevice) _nextDeviceCheck = now + 2 * Stopwatch.Frequency;
            }
            // Device enumeration is kept out of the mouse hook and input hot path.
            if (checkDevice && !_hasSelectedDevice()) { Release("Off · selected trackpad disconnected"); return; }
            lock (_sync)
            {
                if (_enabled && _pendingRelease == null)
                {
                    if (!_hook.IsMouseTakeoverActive) Release("Off · input watchdog released");
                    else _hook.GatePhysicalMouseFor(TimeSpan.FromSeconds(2));
                }
            }
        }
        catch (Exception ex) { Release("Off · " + ex.Message); }
    }

    private void CheckEmergencyRelease(object? state)
    {
        lock (_sync)
        {
            if (!_enabled || _disposed) return;
            if ((GetAsyncKeyState(0x11) & 0x8000) != 0 && (GetAsyncKeyState(0x12) & 0x8000) != 0 && (GetAsyncKeyState(0x52) & 0x8000) != 0)
                RequestRelease("Off · Ctrl+Alt+R released");
            else if (_testDeadline != 0 && Stopwatch.GetTimestamp() >= _testDeadline)
                RequestRelease("Off · 30sec test complete");
        }
    }

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Suspend) RequestRelease("Off · sleep");
    }
    private void OnSessionSwitch(object sender, SessionSwitchEventArgs e) => RequestRelease("Off · session changed");

    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed) return;
            Release("Off · shutdown"); _disposed = true; _available = false;
        }
        _heartbeat.Stop(); _watchdog?.Dispose();
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        SystemEvents.SessionSwitch -= OnSessionSwitch;
        _window?.Dispose(); _window = null;
    }

    private sealed class ShortcutWindow : WinForms.NativeWindow, IDisposable
    {
        private readonly MouseTakeoverController _owner;
        public ShortcutWindow(MouseTakeoverController owner) => _owner = owner;
        public void Create() => CreateHandle(new WinForms.CreateParams { Caption = "GlassToKeyMouseTakeoverShortcut", Parent = new IntPtr(-3) });
        protected override void WndProc(ref WinForms.Message message)
        {
            if (message.Msg == 0x312 && message.WParam.ToInt32() == HotkeyId) _owner.Release("Off · Ctrl+Alt+R released");
            base.WndProc(ref message);
        }
        public void Dispose()
        {
            if (Handle == IntPtr.Zero) return;
            UnregisterHotKey(Handle, HotkeyId); DestroyHandle();
        }
    }
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
}
