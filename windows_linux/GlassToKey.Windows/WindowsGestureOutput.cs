using System.Diagnostics;

namespace GlassToKey;

// SendInput can synchronously call the UI thread's low-level hook. Never call it
// while holding the actor/configuration lock that the UI needs. Queue only here;
// the sole native writer owns its buffers, fractional motion and drag destination.
internal sealed class WindowsGestureOutput : IHandGestureOutput, IDisposable
{
    private readonly record struct Command(int Kind, double X, double Y, HandGestureAction Action, long Time, long Generation);
    private readonly object _gate = new();
    private readonly Queue<Command> _queue = new();
    private readonly AutoResetEvent _wake = new(false);
    private readonly NativeGestureOutput _native = new();
    private readonly Func<bool> _eligible;
    private readonly Thread _thread;
    private bool _stopping;
    private long _generation;
    private string? _fault;
    private long _lastActivity;
    public WindowsGestureOutput(Func<bool> eligible)
    {
        _eligible = eligible;
        _thread = new Thread(Run) { IsBackground = true, Name = "GlassToKey.GestureOutput" };
        _thread.Start();
    }
    public bool ForeignButtonDown => _native.ForeignButtonDown;
    public void Move(double xPixels, double yPixels) => Enqueue(0,xPixels,yPixels);
    public void Scroll(double xPoints, double yPoints) => Enqueue(1,xPoints,yPoints);
    public void PrimaryButton(bool down) => Enqueue(down ? 2 : 3);
    public void Tap(HandGestureAction action) => Enqueue(4,action:action);
    public void ResetRemainders() => Enqueue(5);
    public void ThrowIfFaulted()
    {
        string? fault = Interlocked.Exchange(ref _fault,null);
        if (fault != null) throw new InvalidOperationException(fault);
    }
    public void Release()
    {
        lock (_gate)
        {
            _generation++; _queue.Clear();
            if (!_stopping) _queue.Enqueue(new(3,0,0,default,Stopwatch.GetTimestamp(),_generation));
            _wake.Set();
        }
    }
    private void Enqueue(int kind, double x = 0, double y = 0, HandGestureAction action = default)
    {
        lock (_gate)
        {
            if (_stopping) return;
            if (_queue.Count >= 256)
            {
                _generation++; _queue.Clear();
                Interlocked.Exchange(ref _fault,"Gesture output queue overflow");
                _queue.Enqueue(new(3,0,0,default,Stopwatch.GetTimestamp(),_generation));
            }
            else _queue.Enqueue(new(kind,x,y,action,Stopwatch.GetTimestamp(),_generation));
            _wake.Set();
        }
    }
    private void Run()
    {
        try
        {
            while (true)
            {
                Command command = default; bool hasCommand;
                lock (_gate)
                {
                    if (_stopping) return;
                    hasCommand = _queue.TryDequeue(out command);
                }
                if (!hasCommand)
                {
                    if (!_eligible() || (_native.OwnsPrimary && Stopwatch.GetTimestamp()-_lastActivity > Stopwatch.Frequency*.15)) _native.Release();
                    _wake.WaitOne(4); continue;
                }
                if (command.Kind != 3 && (command.Generation != Interlocked.Read(ref _generation) || !_eligible()
                    || Stopwatch.GetTimestamp()-command.Time > Stopwatch.Frequency*.15))
                { _native.Release(); continue; }
                try
                {
                    _lastActivity = Stopwatch.GetTimestamp();
                    switch (command.Kind)
                    {
                        case 0: _native.Move(command.X,command.Y); break;
                        case 1: _native.Scroll(command.X,command.Y); break;
                        case 2: _native.PrimaryButton(true); break;
                        case 3: _native.PrimaryButton(false); break;
                        case 4: _native.Tap(command.Action); break;
                        case 5: _native.ResetRemainders(); break;
                    }
                }
                catch (Exception ex)
                {
                    _native.Release();
                    lock (_gate) { _generation++; _queue.Clear(); }
                    Interlocked.Exchange(ref _fault,ex.Message);
                }
            }
        }
        finally { _native.Release(); }
    }
    public void Dispose()
    {
        lock (_gate) { if (_stopping) return; _stopping = true; _generation++; _queue.Clear(); _wake.Set(); }
        if (_thread.Join(1000)) _wake.Dispose();
    }
}
