using System.Diagnostics;
using System.Runtime.InteropServices;

namespace GlassToKey;

// One instance per live actor. Replay has no instance and can never post gesture output.
internal sealed class WindowsHandGestures : IHandGestureRuntime
{
    private readonly object _sync = new();
    private readonly GlobalMouseClickSuppressor _hook;
    private int _buttonInterference;
    private readonly Func<bool> _eligible;
    private readonly Action _pointerActivity;
    private readonly Action<string> _releaseTakeover;
    private readonly WindowsGestureOutput _output;
    private readonly HandGestureEngine _engine;
    private bool _disposed;
    private long _frames, _reserved;
    public WindowsHandGestures(GlobalMouseClickSuppressor hook, Func<bool> eligible, Action pointerActivity, Action<string> releaseTakeover)
    {
        _hook = hook; _hook.DiagnosticEvent += ObserveButton;
        _eligible = eligible; _pointerActivity = pointerActivity; _releaseTakeover = releaseTakeover;
        _output = new WindowsGestureOutput(eligible);
        _engine = new(_output);
    }
    // Hook callback only records a flag. Never acquire engine/output locks here.
    private void ObserveButton(MouseHookDiagnosticEvent e)
    {
        if ((e.Flags & 1) != 0 && e.ExtraInfo != NativeGestureOutput.EventTag && e.Message is 0x201 or 0x204 or 0x207 or 0x20B)
            Interlocked.Exchange(ref _buttonInterference,1);
    }
    private void CheckButtonInterference()
    {
        if (Interlocked.Exchange(ref _buttonInterference,0) == 0) return;
        _output.Release(); _engine.Reset();
    }
    public string Status
    {
        get { lock (_sync) return $"{(_eligible() ? "Active" : "Waiting for Mouse Takeover")} · frames {_frames:N0} · reserved {_reserved:N0}"; }
    }
    public void Configure(UserSettings settings)
    {
        lock (_sync)
        {
            bool same = !string.IsNullOrWhiteSpace(settings.LeftDevicePath) && string.Equals(settings.LeftDevicePath, settings.RightDevicePath, StringComparison.OrdinalIgnoreCase);
            _output.Release();
            var effective = (settings.HandGesturesV1 ?? new()).Clone();
            // Current PTP contacts cannot positively classify a thumb. An unavailable
            // input must not reserve a family whose usable bindings are all None.
            effective.Left.ThumbTwoTap = effective.Right.ThumbTwoTap = HandGestureAction.None;
            _engine.Configure(effective, same);
            _output.ResetRemainders();
        }
    }
    public bool Process(TrackpadSide side, in InputFrame frame, ushort maxX, ushort maxY, long timestamp)
    {
        lock (_sync)
        {
            if (_disposed) return false;
            Span<HandGestureContact> contacts = stackalloc HandGestureContact[InputFrame.MaxContacts];
            int count = 0;
            for (int i = 0; i < frame.GetClampedContactCount(); i++)
            {
                var c = frame.GetContact(i); if (!c.TipSwitch) continue;
                contacts[count++] = new(c.Id, maxX == 0 ? double.NaN : c.X * 160.0 / maxX,
                    maxY == 0 ? double.NaN : c.Y * 114.9 / maxY);
            }
            try
            {
                CheckButtonInterference();
                _output.ThrowIfFaulted();
                bool takeover = _eligible();
                bool eligible = takeover && !_output.ForeignButtonDown;
                if (Stopwatch.GetTimestamp()-timestamp > Stopwatch.Frequency*.15) eligible = false;
                bool reserved = _engine.Process(side, contacts[..count], timestamp/(double)Stopwatch.Frequency,
                    Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency, eligible, reserveEligible: takeover);
                _frames++; if (reserved) { _reserved++; _pointerActivity(); }
                return reserved;
            }
            catch (Exception ex) { Fail(ex); return true; }
        }
    }
    public void Tick()
    {
        lock (_sync)
        {
            if (_disposed) return;
            try { CheckButtonInterference(); _output.ThrowIfFaulted(); _engine.Tick(Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency, _eligible() && !_output.ForeignButtonDown); }
            catch (Exception ex) { Fail(ex); }
        }
    }
    private void Fail(Exception ex)
    {
        _output.Release();
        _engine.Reset();
        _releaseTakeover("Off · gesture output failed: " + ex.Message);
    }
    public void Dispose()
    {
        lock (_sync) { if (_disposed) return; _disposed = true; _hook.DiagnosticEvent -= ObserveButton; try { _engine.Reset(); } finally { _output.Dispose(); } }
    }
}

// Uses independent buffers, never the keyboard dispatcher's concurrently used scratch space.
// Absolute virtual-desktop moves avoid applying Windows mouse acceleration twice and keep
// a queued drag destination. Fine movement and wheel fractions are retained.
internal sealed class NativeGestureOutput : IHandGestureOutput
{
    internal const ulong EventTag = 0x47544b47;
    private readonly NativeInput[] _inputs = new NativeInput[4];
    private volatile bool _held;
    private double _xRemainder, _yRemainder, _wheelX, _wheelY;
    private int _queuedX, _queuedY;
    public bool OwnsPrimary => _held;
    public bool ForeignButtonDown => (!_held && Down(1)) || Down(2) || Down(4) || Down(5) || Down(6);
    private static bool Down(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;
    public void ResetRemainders() { _xRemainder = _yRemainder = _wheelX = _wheelY = 0; }
    public void Move(double xPixels, double yPixels)
    {
        var bounded = PointerMotionLimits.Constrain(xPixels,yPixels);
        double x = bounded.X, y = bounded.Y;
        x += _xRemainder; y += _yRemainder;
        int dx = (int)x, dy = (int)y; _xRemainder = x-dx; _yRemainder = y-dy;
        if (dx == 0 && dy == 0) return;
        if (!_held)
        { if (!GetCursorPos(out var current)) throw new InvalidOperationException("Cursor position unavailable"); _queuedX = current.X; _queuedY = current.Y; }
        int left = GetSystemMetrics(76), top = GetSystemMetrics(77), width = GetSystemMetrics(78), height = GetSystemMetrics(79);
        if (width < 2 || height < 2) throw new InvalidOperationException("Display bounds unavailable");
        _queuedX = Math.Clamp(_queuedX+dx, left, left+width-1); _queuedY = Math.Clamp(_queuedY+dy, top, top+height-1);
        // Clamp to an actual monitor, including negative origins and gaps.
        if (GetMonitorInfo(MonitorFromPoint(new Point { X = _queuedX, Y = _queuedY }, 2), out var monitor))
        { _queuedX = Math.Clamp(_queuedX, monitor.Monitor.Left, monitor.Monitor.Right-1); _queuedY = Math.Clamp(_queuedY, monitor.Monitor.Top, monitor.Monitor.Bottom-1); }
        _inputs[0] = Input(0xC001, (int)Math.Round((_queuedX-left)*65535.0/(width-1)), (int)Math.Round((_queuedY-top)*65535.0/(height-1)));
        Send(1);
    }
    public void Scroll(double xPoints, double yPoints)
    {
        // Windows wheel messages have no CGEvent pixel/phase equivalent. 10 Mac points
        // map to one Windows detent (120 units), retaining sub-detent precision.
        _wheelX -= xPoints*12; _wheelY += yPoints*12;
        int x = (int)_wheelX, y = (int)_wheelY; _wheelX -= x; _wheelY -= y;
        int n = 0;
        if (y != 0) _inputs[n++] = Input(0x0800, data: unchecked((uint)y));
        if (x != 0) _inputs[n++] = Input(0x1000, data: unchecked((uint)x));
        if (n > 0) Send(n);
    }
    public void PrimaryButton(bool down)
    {
        if (_held == down) return;
        if (down)
        {
            if (ForeignButtonDown || !GetCursorPos(out var current)) throw new InvalidOperationException("Mouse button busy");
            _queuedX = current.X; _queuedY = current.Y;
            _held = true; // Reserve cleanup before posting down.
            _inputs[0] = Input(2); Send(1);
        }
        else { Release(); if (_held) throw new InvalidOperationException("Primary button release failed"); }
        ResetRemainders();
    }
    public void Tap(HandGestureAction action)
    {
        if (_held || ForeignButtonDown) return;
        bool secondary = action == HandGestureAction.SecondaryClick;
        if (action is not (HandGestureAction.PrimaryClick or HandGestureAction.DoubleClick or HandGestureAction.SecondaryClick)) return;
        int n = action == HandGestureAction.DoubleClick ? 4 : 2;
        for (int i = 0; i < n; i++) _inputs[i] = Input(secondary ? (i%2 == 0 ? 8u : 16u) : (i%2 == 0 ? 2u : 4u));
        try { Send(n); }
        catch { _inputs[0] = Input(secondary ? 16u : 4u); SendInput(1, _inputs, Marshal.SizeOf<NativeInput>()); throw; }
    }
    public void Release()
    {
        if (_held) { _inputs[0] = Input(4); if (SendInput(1, _inputs, Marshal.SizeOf<NativeInput>()) == 1) _held = false; }
        ResetRemainders();
    }
    private void Send(int n)
    {
        if (SendInput((uint)n, _inputs, Marshal.SizeOf<NativeInput>()) != n)
            throw new InvalidOperationException("SendInput failed (" + Marshal.GetLastWin32Error() + ")");
    }
    private static NativeInput Input(uint flags, int x = 0, int y = 0, uint data = 0) => new()
    { Mouse = new MouseInput { X = x, Y = y, Flags = flags, Data = data, Extra = unchecked((nuint)EventTag) } };
    [StructLayout(LayoutKind.Sequential)] private struct NativeInput { public uint Type; public MouseInput Mouse; }
    [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int X, Y; public uint Data, Flags, Time; public nuint Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public uint Size; public Rect Monitor, Work; public uint Flags; }
    private static bool GetMonitorInfo(IntPtr monitor, out MonitorInfo info) { info = new() { Size = (uint)Marshal.SizeOf<MonitorInfo>() }; return GetMonitorInfoNative(monitor, ref info); }
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, [In] NativeInput[] inputs, int size);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(Point point, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW")] private static extern bool GetMonitorInfoNative(IntPtr monitor, ref MonitorInfo info);
}
