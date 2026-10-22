using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace GlassToKey;

// Opt-in, separate test process. No saved settings and no typing-engine startup.
internal sealed class MouseTakeoverTestWindow : Window, IDisposable
{
    private const int ReleaseHotkey = 0x4754;
    private readonly GlobalMouseClickSuppressor _hook = new();
    private readonly RawInputContext _raw = new();
    private readonly ConcurrentQueue<string> _pending = new();
    private readonly HashSet<IntPtr> _devices = new();
    private readonly StreamWriter _log;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly CheckBox _check = new() { Content = "Mouse Takeover", Margin = new Thickness(0, 12, 0, 12), FontSize = 18 };
    private readonly TextBlock _status = new() { FontSize = 22, FontWeight = FontWeights.Bold, TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _stats = new() { Margin = new Thickness(0, 12, 0, 12), TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _synthetic = new() { TextWrapping = TextWrapping.Wrap };
    private readonly Button _test = new() { Content = "_30sec test", Padding = new Thickness(14, 8, 14, 8) };
    private readonly TextBlock _releaseHelp = new() { Text = "Checking keyboard release shortcut…", TextWrapping = TextWrapping.Wrap, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 12, 0, 0) };
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(100) };
    private System.Threading.Timer? _watchdog;
    private HwndSource? _source;
    private bool _ready, _armed, _updating, _disposed, _syntheticSent, _afterSynthetic;
    private long _lease, _frames, _gateFrames, _positiveGateFrames, _moves, _wheels, _buttons, _injected;
    private long _payloadBytes;
    private int _sampleTick;
    private uint _releaseKey;
    private string _releaseShortcut = "Escape";

    public MouseTakeoverTestWindow(string logPath)
    {
        _log = new StreamWriter(new FileStream(logPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read));
        Title = "GlassToKey — Mouse Takeover test";
        Width = 660; SizeToContent = SizeToContent.Height; MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var panel = new StackPanel { Margin = new Thickness(24) };
        panel.Children.Add(new TextBlock { Text = "Mouse Takeover · temporary test", FontSize = 24, FontWeight = FontWeights.SemiBold });
        panel.Children.Add(new TextBlock { Text = "Blocks physical movement, clicks, and scrolling from ALL mice. Injected input passes through. Windows shell gestures may still run.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0) });
        panel.Children.Add(_releaseHelp);
        panel.Children.Add(_check);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        buttons.Children.Add(_test);
        var release = new Button { Content = "_Release", Padding = new Thickness(14, 8, 14, 8), Margin = new Thickness(8, 0, 0, 0) };
        release.Click += (_, _) => Release("release button"); buttons.Children.Add(release);
        panel.Children.Add(buttons);
        _status.Margin = new Thickness(0, 16, 0, 0); panel.Children.Add(_status);
        panel.Children.Add(_stats); panel.Children.Add(_synthetic);
        panel.Children.Add(new TextBlock { Text = "At 5 seconds the test injects a 20-pixel move. Verify that finger motion stays blocked while this small jump still works. Watch the contact-report counter and try scrolling/clicking.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0) });
        panel.Children.Add(new TextBlock { Text = "Keep Windows Touchpad ON. This test does not change gesture settings or run the typing engine. Nothing is saved as a preference.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0) });
        panel.Children.Add(new TextBlock { Text = "Log: " + logPath, TextWrapping = TextWrapping.Wrap, FontSize = 11, Margin = new Thickness(0, 12, 0, 0) });
        Content = panel;
        _check.Checked += (_, _) => { if (!_updating) Arm(); };
        _check.Unchecked += (_, _) => { if (!_updating) Release("checkbox unchecked"); };
        _test.Click += (_, _) => { if (!_armed) Arm(); };
        _timer.Tick += Tick;
        SourceInitialized += (_, _) => Initialize();
        Closed += (_, _) => Dispose();
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { Release("Escape"); e.Handled = true; } };
        ShowReleased("Not active");
        _check.IsEnabled = _test.IsEnabled = false;
    }

    private void Initialize()
    {
        try
        {
            _source = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);
            if (_source == null) throw new InvalidOperationException("Window message source unavailable.");
            _source.AddHook(WindowMessage);
            // F12 is reserved by Windows for debuggers, including when no debugger is running.
            foreach (uint candidate in new uint[] { 0x79, 0x78, 0x77 })
                if (RegisterHotKey(_source.Handle, ReleaseHotkey, 0x4003, candidate)) { _releaseKey = candidate; break; }
            if (_releaseKey == 0)
                throw new InvalidOperationException("Cannot register Ctrl+Alt+F10, F9, or F8. Close other test windows or apps using these shortcuts and reopen the test.");
            _releaseShortcut = "Ctrl+Alt+F" + (_releaseKey - 0x70 + 1);
            _hook.SetTakeoverReleaseKey((int)_releaseKey);
            _releaseHelp.Text = "Release anywhere: " + _releaseShortcut + " or Escape. Every activation ends after 30 seconds.";
            if (!RawInputInterop.RegisterForTouchpadRawInput(_source.Handle, out string? rawError))
                throw new InvalidOperationException("Raw Input registration failed: " + rawError);
            _hook.DiagnosticEvent += OnMouse;
            if (!_hook.Install(out string? hookError)) throw new InvalidOperationException("Mouse hook failed: " + hookError);
            _ready = true;
            _check.IsEnabled = _test.IsEnabled = true;
            Queue("READY release=" + _releaseShortcut + ",Escape durationLimit=30s");
            _timer.Start();
            Flush();
        }
        catch (Exception ex)
        {
            _hook.ReleaseMouseTakeover(); _hook.Dispose();
            _check.IsEnabled = _test.IsEnabled = false;
            _status.Text = "TEST UNAVAILABLE — " + ex.Message; _status.Foreground = Brushes.Firebrick;
            Queue("FAULT " + ex); Flush();
        }
    }

    private void Arm()
    {
        if (!_ready || _disposed || _armed) return;
        // A physical down delivered before arming must not have its matching up swallowed.
        foreach (int key in new[] { 1, 2, 4, 5, 6 })
            if ((GetAsyncKeyState(key) & 0x8000) != 0) { Release("Release all mouse buttons before arming"); return; }
        _gateFrames = _positiveGateFrames = _moves = _wheels = _buttons = _injected = 0;
        _syntheticSent = _afterSynthetic = false;
        _synthetic.Text = "Synthetic move will run after 5 seconds.";
        _lease = _hook.GatePhysicalMouseFor(TimeSpan.FromSeconds(30));
        _armed = true; _updating = true; _check.IsChecked = true; _updating = false;
        _test.IsEnabled = false; Topmost = true;
        long lease = _lease;
        _watchdog?.Dispose();
        // Independent of the WPF dispatcher. A stale timer cannot release a newer lease.
        _watchdog = new System.Threading.Timer(_ => _hook.ReleaseMouseTakeover(lease), null, TimeSpan.FromSeconds(30), System.Threading.Timeout.InfiniteTimeSpan);
        Queue("TAKEOVER_ON lease=" + lease); UpdateDisplay();
    }

    private void Release(string reason)
    {
        _hook.ReleaseMouseTakeover(); _watchdog?.Dispose(); _watchdog = null;
        if (_disposed) return;
        if (_armed) Queue($"TAKEOVER_OFF reason={reason} frames={_gateFrames} positiveCountFrames={_positiveGateFrames} moves={_moves} wheels={_wheels} buttons={_buttons} injected={_injected}");
        _armed = false; _updating = true; _check.IsChecked = false; _updating = false;
        _test.IsEnabled = _ready; Topmost = false; ShowReleased(reason);
    }

    private void ShowReleased(string reason)
    {
        _status.Text = "RELEASED — " + reason;
        _status.Foreground = Brushes.ForestGreen;
    }

    private void Tick(object? sender, EventArgs e)
    {
        try
        {
            if (_armed)
            {
                if ((GetAsyncKeyState(0x1B) & 0x8000) != 0) Release("Escape");
                else if ((GetAsyncKeyState(0x11) & 0x8000) != 0 && (GetAsyncKeyState(0x12) & 0x8000) != 0 && (GetAsyncKeyState((int)_releaseKey) & 0x8000) != 0) Release(_releaseShortcut);
                else if (!_hook.IsMouseTakeoverActive) Release("deadline or keyboard release");
                else
                {
                    double left = (_lease - Stopwatch.GetTimestamp()) / (double)Stopwatch.Frequency;
                    if (!_syntheticSent && left <= 25)
                    {
                        _syntheticSent = true;
                        GetCursorPos(out Point before);
                        var input = new[] { new Input { Type = 0, Mouse = new MouseInput { Dx = 20, Flags = 1, Extra = (UIntPtr)0x47544B54 } } };
                        uint sent = SendInput(1, input, Marshal.SizeOf<Input>());
                        int error = sent == 1 ? 0 : Marshal.GetLastWin32Error();
                        Queue($"SYNTHETIC_MOVE sent={sent} error={error} before={before.X},{before.Y}");
                        _synthetic.Text = $"Synthetic move: {sent}/1 sent; error {error}.";
                        _afterSynthetic = true;
                    }
                    else if (_afterSynthetic)
                    {
                        _afterSynthetic = false; GetCursorPos(out Point after);
                        Queue($"SYNTHETIC_AFTER cursor={after.X},{after.Y}");
                    }
                    if (++_sampleTick % 10 == 0) { GetCursorPos(out Point pt); Queue($"CURSOR x={pt.X} y={pt.Y}"); }
                }
            }
            UpdateDisplay(); Flush();
        }
        catch (Exception ex)
        {
            Release("test error"); _ready = false; _check.IsEnabled = _test.IsEnabled = false;
            _status.Text += " — " + ex.Message;
        }
    }

    private void UpdateDisplay()
    {
        if (_armed)
        {
            _status.Text = "TAKEOVER ON — " + Math.Max(0, Math.Ceiling((_lease - Stopwatch.GetTimestamp()) / (double)Stopwatch.Frequency)) + "s remaining";
            _status.Foreground = Brushes.Firebrick;
        }
        _stats.Text = $"Raw frames: {_frames} total · {_gateFrames} during takeover · {_positiveGateFrames} with nonzero contact count\nHook events during takeover: {_moves} moves · {_wheels} wheels · {_buttons} buttons · {_injected} injected";
    }

    private void OnMouse(MouseHookDiagnosticEvent e)
    {
        if (!_hook.IsMouseTakeoverActive) return;
        if ((e.Flags & 1) != 0) _injected++;
        else if (e.Message == 0x200) _moves++;
        else if (e.Message == 0x20a || e.Message == 0x20e) _wheels++;
        else _buttons++;
        Queue($"MOUSE msg=0x{e.Message:X} x={e.X} y={e.Y} flags=0x{e.Flags:X} extra=0x{e.ExtraInfo:X}");
    }

    private IntPtr WindowMessage(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled)
    {
        if (msg == 0x312 && wp.ToInt32() == ReleaseHotkey) { Release(_releaseShortcut); handled = true; }
        if (msg == RawInputInterop.WM_INPUT)
        {
            try
            {
                if (!RawInputInterop.TryGetRawInputPacket(lp, out RawInputPacket packet) ||
                    !_raw.TryGetSnapshot(packet.DeviceHandle, out RawInputDeviceSnapshot device) || !RawInputInterop.IsTargetDevice(device.Info)) return IntPtr.Zero;
                if (_devices.Add(packet.DeviceHandle)) Queue("DEVICE handle=" + packet.DeviceHandle + " path=" + device.DeviceName);
                for (uint i = 0; i < packet.ReportCount; i++)
                {
                    int offset = packet.DataOffset + checked((int)(i * packet.ReportSize));
                    int size = checked((int)packet.ReportSize);
                    if (offset + size > packet.ValidLength) break;
                    bool gate = _hook.IsMouseTakeoverActive;
                    int contacts = size == 50 && packet.Buffer[offset] == 5 ? packet.Buffer[offset + 48] : -1;
                    _frames++; if (gate) { _gateFrames++; if (contacts > 0) _positiveGateFrames++; }
                    if (_payloadBytes < 16 * 1024 * 1024)
                    {
                        _payloadBytes += size;
                        Queue($"RAW handle={packet.DeviceHandle} gate={gate} contacts={contacts} hex={Convert.ToHexString(packet.Buffer.AsSpan(offset, size))}");
                    }
                }
            }
            catch (Exception ex) { Release("raw input error"); Queue("FAULT " + ex); }
        }
        return IntPtr.Zero;
    }

    private void Queue(string text)
    {
        if (_pending.Count < 10000) _pending.Enqueue($"{DateTime.UtcNow:O} t={_clock.Elapsed.TotalSeconds:F3} {text}");
    }
    private void Flush()
    {
        while (_pending.TryDequeue(out string? line)) _log.WriteLine(line);
        _log.Flush();
    }
    public void Dispose()
    {
        if (_disposed) return;
        // Release native input first, even if a closing-window property or log write fails.
        _hook.ReleaseMouseTakeover(); _watchdog?.Dispose(); _timer.Stop();
        try { Release("window closed"); } catch { }
        _disposed = true; _hook.Dispose();
        if (_source != null) { if (_releaseKey != 0) UnregisterHotKey(_source.Handle, ReleaseHotkey); _source.RemoveHook(WindowMessage); }
        Queue("END");
        try { Flush(); } catch (IOException) { }
        try { _log.Dispose(); } catch (IOException) { }
    }

    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int Dx, Dy; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public MouseInput Mouse; }
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
}
