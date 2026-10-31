using System.Diagnostics;
using System.Runtime.InteropServices;

namespace AppleMagicTouchstream;

// One instance per live actor. Replay has no instance and can never post gesture output.
internal sealed class WindowsHandGestures : IHandGestureRuntime
{
    private readonly object _sync = new();
    private readonly GlobalMouseInputHook _hook;
    private int _buttonInterference;
    private readonly Func<bool> _eligible;
    private readonly Action _pointerActivity;
    private readonly Action<string> _releaseTakeover;
    private readonly WindowsGestureOutput _output;
    private readonly HandGestureEngine _engine;
    private readonly StenoPointerEngine _stenoPointer;
    private bool _disposed;
    private bool _stenoMode;
    private bool _lastTakeover;
    private byte _downPads;
    private long _frames, _reserved;
    private readonly bool[] _keyboardPriority=new bool[2];
    public bool SupportsKeyboardProposals => true;
    public void SetKeyboardPriority(TrackpadSide side,bool priority) { lock(_sync) _keyboardPriority[(int)side]=priority; }
    public HandGestureEvidence Evidence(TrackpadSide side) { lock(_sync) return _engine.Evidence(side); }
    public void Cancel(TrackpadSide? side=null) { lock(_sync) { _stenoPointer.Cancel(side); if(side is {} pad) _engine.Cancel(pad); else { _output.Release(); _engine.Reset(); } } }
    public WindowsHandGestures(GlobalMouseInputHook hook, Func<bool> eligible, Action pointerActivity, Action<string> releaseTakeover,
        DispatchEventQueue? keyboardQueue=null,SendInputDispatcher? keyboardDispatcher=null)
    {
        _hook = hook; _hook.DiagnosticEvent += ObserveButton;
        _eligible = eligible; _pointerActivity = pointerActivity; _releaseTakeover = releaseTakeover;
        var keyboard=keyboardQueue!=null && keyboardDispatcher!=null ? new WindowsGestureKeyboardSession(keyboardQueue,keyboardDispatcher,eligible,hook.PhysicalKeyboard) : null;
        _output = new WindowsGestureOutput(eligible,keyboard);
        _engine = new(new TakeoverGestureOutput(_output,_eligible));
        _stenoPointer=new(_output);
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
        get { lock (_sync) return _stenoMode ? "STENO pointer movement is enabled; lift both hands before the next chord." : $"{(_eligible() ? "Active" : "Native mouse · gesture protection active")} · frames {_frames:N0} · reserved {_reserved:N0}"; }
    }
    public void Configure(UserSettings settings)
    {
        lock (_sync)
        {
            _stenoMode=TrackpadLayoutPreset.ResolveByNameOrDefault(settings.LayoutPresetName).IsSteno;
            _lastTakeover=_eligible();
            bool same = !string.IsNullOrWhiteSpace(settings.LeftDevicePath) && string.Equals(settings.LeftDevicePath, settings.RightDevicePath, StringComparison.OrdinalIgnoreCase);
            _output.Release(); _stenoPointer.Configure(settings.StenoPointerFingerCount);
            var effective = (settings.HandGesturesV1 ?? new()).Clone();
            // Windows uses the accepted Apple reference curve for movement and drag.
            effective.Left.PointerResponse = effective.Right.PointerResponse = HandPointerResponse.AppleReference;
            // Current PTP contacts cannot positively classify a thumb. An unavailable
            // input must not reserve a family whose usable bindings are all None.
            effective.Left.ThumbTwoTap = effective.Right.ThumbTwoTap = HandGestureAction.None;
            _engine.Configure(effective, same);
            _output.ResetRemainders();
        }
    }
    internal static int ReadContacts(in InputFrame frame, ushort maxX, ushort maxY, Span<HandGestureContact> contacts, out bool fourthContactPending)
    {
        int count = 0;
        bool pendingContact = false;
        for (int i = 0; i < frame.GetClampedContactCount(); i++)
        {
            var c = frame.GetContact(i);
            if (!c.TipSwitch)
            {
                // PTP has no Mac anatomical labels or native hover phase.
                // An in-range confident non-tip slot is the available landing
                // evidence; it never counts as a touching finger or movement.
                pendingContact |= c.Confidence && maxX > 0 && maxY > 0 && c.X <= maxX && c.Y <= maxY;
                continue;
            }
            contacts[count++] = new(c.Id, maxX == 0 ? double.NaN : c.X * 160.0 / maxX,
                maxY == 0 ? double.NaN : c.Y * 114.9 / maxY, Pressure:c.Pressure8, HasPressure:c.HasForceData);
        }
        fourthContactPending = count == 3 && pendingContact;
        return count;
    }
    public bool Process(TrackpadSide side, in InputFrame frame, ushort maxX, ushort maxY, long timestamp)
    {
        lock (_sync)
        {
            if (_disposed || _stenoMode) return false;
            Span<HandGestureContact> contacts = stackalloc HandGestureContact[InputFrame.MaxContacts];
            int count = ReadContacts(in frame,maxX,maxY,contacts,out bool fourthContactPending);
            try
            {
                _output.ObserveFrame();
                if(count>0) _downPads|=(byte)(1<<(int)side); else _downPads&=(byte)~(1<<(int)side);
                ObserveTakeover();
                CheckButtonInterference();
                _output.ThrowIfFaulted();
                bool eligible = !_output.ForeignButtonDown;
                if (Stopwatch.GetTimestamp()-timestamp > Stopwatch.Frequency*.15) eligible = false;
                bool reserved = _engine.Process(side, contacts[..count], timestamp/(double)Stopwatch.Frequency,
                    Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency, eligible, reserveEligible: true, keyboardPriority:_keyboardPriority[(int)side],
                    fourthContactPending:fourthContactPending);
                _frames++; if (reserved) { _reserved++; _pointerActivity(); }
                return reserved;
            }
            catch (Exception ex) { Fail(ex); return true; }
        }
    }
    public bool ProcessStenoPointer(TrackpadSide side,in InputFrame frame,ushort maxX,ushort maxY,long timestamp)
    {
        lock(_sync)
        {
            if(_disposed || !_stenoMode) return false;
            Span<HandGestureContact> contacts=stackalloc HandGestureContact[InputFrame.MaxContacts];
            int count=ReadContacts(in frame,maxX,maxY,contacts,out _);
            try
            {
                _output.ObserveFrame(); _output.ThrowIfFaulted();
                bool valid=frame.ContactCount<=InputFrame.MaxContacts && _eligible() && !_output.ForeignButtonDown;
                return _stenoPointer.Process(side,contacts[..count],timestamp/(double)Stopwatch.Frequency,
                    Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency,valid);
            }
            catch(Exception error) { _stenoPointer.Cancel(); Fail(error); return true; }
        }
    }
    public void Tick()
    {
        lock (_sync)
        {
            if (_disposed) return;
            if(_stenoMode)
            {
                try { _output.ThrowIfFaulted(); _stenoPointer.Tick(Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency,_eligible() && !_output.ForeignButtonDown); }
                catch(Exception error) { _stenoPointer.Cancel(); Fail(error); }
                return;
            }
            try { ObserveTakeover(); CheckButtonInterference(); _output.ThrowIfFaulted(); _engine.Tick(Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency, !_output.ForeignButtonDown); }
            catch (Exception ex) { Fail(ex); }
        }
    }
    private void ObserveTakeover()
    {
        bool takeover=_eligible();
        if(takeover==_lastTakeover) return;
        _lastTakeover=takeover;
        _output.Release();
        CancelForTakeoverChange(_engine,_downPads,Stopwatch.GetTimestamp()/(double)Stopwatch.Frequency);
    }
    internal static void CancelForTakeoverChange(HandGestureEngine engine,byte downPads,double time)
    {
        engine.Reset();
        // Only pads already known to be all-up can start immediately. A held
        // gesture must lift before AMT output is allowed to acquire it again.
        for(int i=0;i<2;i++) if((downPads&(1<<i))==0) engine.Process((TrackpadSide)i,[],time,time,true);
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
    private readonly NativeInput[] _inputs = new NativeInput[32];
    private volatile bool _held;
    private double _xRemainder, _yRemainder, _wheelX, _wheelY;
    private double _zoomRemainder;
    private readonly ushort[] _keyUps = new ushort[16];
    private int _keyUpCount;
    private readonly long[] _lastForceHaptic = new long[2];
    public bool NeedsKeyRelease => _keyUpCount > 0;
    internal static int InputSize => Marshal.SizeOf<NativeInput>();
    private int _queuedX, _queuedY;
    public bool OwnsPrimary => _held;
    public bool ForeignButtonDown => (!_held && Down(1)) || Down(2) || Down(4) || Down(5) || Down(6);
    private static bool Down(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;
    public void ResetRemainders() { _xRemainder = _yRemainder = _wheelX = _wheelY = _zoomRemainder = 0; }
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
        if (action is HandGestureAction.ScrollUp or HandGestureAction.ScrollDown or HandGestureAction.PanLeft or HandGestureAction.PanRight)
        {
            Scroll(action == HandGestureAction.PanLeft ? 10 : action == HandGestureAction.PanRight ? -10 : 0,
                action == HandGestureAction.ScrollUp ? 10 : action == HandGestureAction.ScrollDown ? -10 : 0);
            return;
        }
        if (WindowsGestureShortcutPlan.For(action).Length > 0) { Shortcut(action); return; }
        bool secondary = action == HandGestureAction.SecondaryClick;
        if (action is not (HandGestureAction.PrimaryClick or HandGestureAction.DoubleClick or HandGestureAction.SecondaryClick)) return;
        int n = action == HandGestureAction.DoubleClick ? 4 : 2;
        for (int i = 0; i < n; i++) _inputs[i] = Input(secondary ? (i%2 == 0 ? 8u : 16u) : (i%2 == 0 ? 2u : 4u));
        try { Send(n); }
        catch { _inputs[0] = Input(secondary ? 16u : 4u); SendInput(1, _inputs, Marshal.SizeOf<NativeInput>()); throw; }
    }
    public void ForceFeedback(TrackpadSide side)
    {
        long now=Stopwatch.GetTimestamp(); int index=(int)side;
        if (now-_lastForceHaptic[index]<Stopwatch.Frequency*.05) return;
        _lastForceHaptic[index]=now;
        MagicTrackpadActuatorHaptics.TryVibrate(side);
    }
    private static bool ModifierBusy => Down(0x10) || Down(0x11) || Down(0x12) || Down(0x5B) || Down(0x5C);
    private void Shortcut(HandGestureAction action)
    {
        if (ModifierBusy) return; // Never release a physical/typing modifier owned elsewhere.
        var edges = WindowsGestureShortcutPlan.For(action);
        foreach (var edge in edges) if (!edge.Up && Down(edge.Key)) return;
        PostShortcut(edges);
    }
    public void AssignedAction(string label)
    {
        if (_held || ForeignButtonDown || ModifierBusy) return;
        var edges=WindowsGestureShortcutPlan.ForAssignment(label);
        foreach (var edge in edges) if (!edge.Up && Down(edge.Key)) return;
        PostShortcut(edges);
    }
    private void PostShortcut(WindowsGestureShortcutPlan.Edge[] edges)
    {
        if (edges.Length==0) return;
        for (int i=0; i<edges.Length; i++) _inputs[i] = Key(edges[i].Key,edges[i].Up);
        _keyUpCount=0;
        foreach (var edge in edges) if (edge.Up) _keyUps[_keyUpCount++]=edge.Key;
        try { Send(edges.Length); _keyUpCount=0; }
        catch
        {
            ReleaseKeys();
            throw;
        }
    }
    public void Zoom(double scaleDelta)
    {
        // User-mode compatibility path. Target apps decide Ctrl+wheel behavior;
        // this is not a synthetic native Precision Touchpad magnification stream.
        if (_held || ForeignButtonDown || ModifierBusy || !double.IsFinite(scaleDelta)) return;
        _zoomRemainder += Math.Clamp(scaleDelta,-.25,.25)*1200;
        int wheel=(int)_zoomRemainder; _zoomRemainder -= wheel;
        if (wheel == 0) return;
        _inputs[0]=Key(0x11,false); _inputs[1]=Input(0x0800,data:unchecked((uint)wheel)); _inputs[2]=Key(0x11,true);
        _keyUps[0]=0x11; _keyUpCount=1;
        try { Send(3); _keyUpCount=0; }
        catch { ReleaseKeys(); throw; }
    }
    private void ReleaseKeys()
    {
        if (_keyUpCount==0) return;
        for (int i=0; i<_keyUpCount; i++) _inputs[i]=Key(_keyUps[i],true);
        if (SendInput((uint)_keyUpCount,_inputs,Marshal.SizeOf<NativeInput>())==(uint)_keyUpCount) _keyUpCount=0;
    }
    public void Release()
    {
        ReleaseKeys();
        if (_held) { _inputs[0] = Input(4); if (SendInput(1, _inputs, Marshal.SizeOf<NativeInput>()) == 1) _held = false; }
        ResetRemainders();
    }
    private void Send(int n)
    {
        if (SendInput((uint)n, _inputs, Marshal.SizeOf<NativeInput>()) != n)
            throw new InvalidOperationException("SendInput failed (" + Marshal.GetLastWin32Error() + ")");
    }
    private static NativeInput Input(uint flags, int x = 0, int y = 0, uint data = 0) => new()
    { Payload = new InputPayload { Mouse = new MouseInput { X = x, Y = y, Flags = flags, Data = data, Extra = unchecked((nuint)EventTag) } } };
    private static NativeInput Key(ushort key, bool up) => new() { Type=1,
        Payload=new InputPayload { Keyboard=new KeyboardInput { Key=key, Flags=(up ? 2u : 0u) | (WindowsVirtualKeyMapper.IsExtendedVirtualKey(key) ? 1u : 0u), Extra=unchecked((nuint)EventTag) } } };
    [StructLayout(LayoutKind.Sequential)] private struct NativeInput { public uint Type; public InputPayload Payload; }
    [StructLayout(LayoutKind.Explicit)] private struct InputPayload
    {
        [FieldOffset(0)] public MouseInput Mouse;
        [FieldOffset(0)] public KeyboardInput Keyboard;
    }
    [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput { public ushort Key, Scan; public uint Flags, Time; public nuint Extra; }
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
