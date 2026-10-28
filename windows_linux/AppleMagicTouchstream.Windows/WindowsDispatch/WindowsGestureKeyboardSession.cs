using System.Diagnostics;
namespace AppleMagicTouchstream;

// The actor only queues semantic changes. The existing keyboard pump owns all
// keyboard writes and reference counts, including held gesture shortcuts.
internal sealed class WindowsGestureKeyboardSession
{
    private readonly object _gate=new();
    private readonly DispatchEventQueue _queue;
    private readonly SendInputDispatcher _dispatcher;
    private readonly Func<bool> _eligible;
    private readonly PhysicalKeyboardTracker? _physical;
    public bool PhysicalTrackingAvailable=>_physical?.Available==true;
    public bool PhysicalKeyDown(ushort key)=>_physical?.IsDown(key)==true;
    private readonly string?[] _held=new string?[3];
    private long _generation;
    private long _lastFrame;
    private string? _fault;
    public void ReportFault(string message) { Interlocked.Exchange(ref _fault,message); ReleaseAll(); }
    public void ThrowIfFaulted() { if(Interlocked.Exchange(ref _fault,null) is {} message) throw new InvalidOperationException(message); }
    public void Heartbeat()=>Interlocked.Exchange(ref _lastFrame,Stopwatch.GetTimestamp());
    public bool IsEligible=>_eligible() && Stopwatch.GetTimestamp()-Interlocked.Read(ref _lastFrame)<Stopwatch.Frequency*.15;
    public WindowsGestureKeyboardSession(DispatchEventQueue queue,SendInputDispatcher dispatcher,Func<bool> eligible,PhysicalKeyboardTracker? physical=null)
    { _queue=queue; _dispatcher=dispatcher; _eligible=eligible; _physical=physical; dispatcher.GestureKeyboardSession=this; }
    public bool Accepts(in DispatchEvent e)=>e.GestureGeneration==Interlocked.Read(ref _generation) && _eligible()
        && Stopwatch.GetTimestamp()-e.TimestampTicks<Stopwatch.Frequency*.15;
    public void SetHeld(int owner,string? label)
    {
        if((uint)owner>=3) return;
        lock(_gate)
        {
            if(_held[owner]==label) return;
            if(label!=null) Heartbeat();
            _held[owner]=label; Post(label==null ? DispatchEventKind.GestureShortcutUp : DispatchEventKind.GestureShortcutDown,owner,label ?? "");
        }
    }
    public void Tap(string label) { lock(_gate) Post(DispatchEventKind.GestureShortcutTap,3,label); }
    private void Post(DispatchEventKind kind,int owner,string label)
    {
        var e=new DispatchEvent(Stopwatch.GetTimestamp(),kind,0,DispatchMouseButton.None,(ulong)owner+1,DispatchEventFlags.None,
            owner==1 ? TrackpadSide.Right : TrackpadSide.Left,label,GestureGeneration:_generation);
        if(!_queue.TryEnqueue(e)) ReleaseAllCore();
    }
    public void ReleaseAll() { lock(_gate) ReleaseAllCore(); }
    private void ReleaseAllCore() { Interlocked.Increment(ref _generation); Array.Clear(_held); _dispatcher.RequestGestureKeyboardRelease(); }
}
