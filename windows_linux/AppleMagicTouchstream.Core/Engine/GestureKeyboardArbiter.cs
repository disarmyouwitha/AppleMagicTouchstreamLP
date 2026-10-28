using System.Diagnostics;
namespace AppleMagicTouchstream;

internal readonly record struct KeyboardProposalToken(int Generation,int Layer,int Epoch);

// Fixed owned frame copies. Retained input is replayed to keyboard recognition
// only; gesture recognition/output always observes the original frames once.
internal sealed class GestureKeyboardArbiter
{
    internal const int Capacity=1024;
    private enum Mode { Idle, Pending, Typing, Gesture }
    private readonly record struct Proposal(InputFrame Frame,ushort MaxX,ushort MaxY,long Time,DispatchModifierFlags Modifiers);
    private sealed class Pad
    {
        public readonly Proposal[] Frames=new Proposal[Capacity];
        public int Count,LastContacts;
        public long LastTime,GestureEpoch;
        public KeyboardProposalToken Token;
        public Mode Mode;
    }
    private readonly Pad[] _pads=[new(),new()];
    private readonly TouchProcessorCore _core;
    private readonly IHandGestureRuntime _gestures;
    private readonly Func<bool>? _flush;
    public GestureKeyboardArbiter(TouchProcessorCore core,IHandGestureRuntime gestures,Func<bool>? flush=null) { _core=core; _gestures=gestures; _flush=flush; }
    public void Invalidate(bool allCycles=false) { foreach(var p in _pads) { p.Count=0; if(allCycles || p.LastContacts>0) p.Mode=Mode.Gesture; } }
    public void Reject(TrackpadSide side) { var p=_pads[(int)side]; p.Count=0; p.Mode=Mode.Gesture; }
    public void Tick(long now)
    { foreach(var p in _pads) if(p.LastContacts>0 && now-p.LastTime>Stopwatch.Frequency*.15) { p.Count=0; p.Mode=Mode.Gesture; } }
    public void Process(TrackpadSide side,in InputFrame frame,ushort maxX,ushort maxY,long time)
    {
        var p=_pads[(int)side]; int active=0; bool valid=maxX>0 && maxY>0 && frame.ContactCount<=InputFrame.MaxContacts;
        for(int i=0;i<frame.GetClampedContactCount();i++)
        {
            var c=frame.GetContact(i); if(!c.TipSwitch) continue; active++;
            for(int j=0;j<i;j++) if(frame.GetContact(j).TipSwitch && frame.GetContact(j).Id==c.Id) valid=false;
        }
        var token=_core.ProposalToken; var before=_gestures.Evidence(side);
        if(p.LastContacts>0 && (p.Token!=token || p.GestureEpoch!=before.Epoch || time<=p.LastTime || time-p.LastTime>=Stopwatch.Frequency*.15))
        { p.Count=0; p.Mode=Mode.Gesture; }
        if(!valid) { p.Count=0; p.Mode=Mode.Gesture; }
        bool typing=p.Mode==Mode.Typing || (p.Mode!=Mode.Gesture && _core.KeyboardChordOwnsCycle(side));
        _gestures.SetKeyboardPriority(side,typing);
        bool reserved=_gestures.Process(side,in frame,maxX,maxY,time); var evidence=_gestures.Evidence(side);
        if(typing)
        { p.Count=0; p.Mode=Mode.Typing; _core.ProcessFrame(side,in frame,maxX,maxY,time); }
        else if(p.Mode==Mode.Gesture || evidence.Claimed || (!evidence.Enabled && p.Mode==Mode.Pending))
        { p.Count=0; p.Mode=Mode.Gesture; _core.ProcessFrame(side,in frame,maxX,maxY,time,true); }
        else if(reserved || p.Mode==Mode.Pending)
        {
            if(p.Mode==Mode.Idle) { p.Mode=Mode.Pending; p.Token=token; p.GestureEpoch=evidence.Epoch; }
            if(p.Count==Capacity) { p.Count=0; p.Mode=Mode.Gesture; _core.ProcessFrame(side,in frame,maxX,maxY,time,true); }
            else
            {
                p.Frames[p.Count++]=new(frame,maxX,maxY,time,_core.KeyboardModifiersSnapshot);
                if(active==0 || (active<2 && !evidence.TapPending))
                {
                    int count=p.Count; p.Count=0; bool committed=true;
                    for(int i=0;i<count;i++)
                    {
                        var proposal=p.Frames[i]; var retained=proposal.Frame;
                        _core.ProcessFrame(side,in retained,proposal.MaxX,proposal.MaxY,proposal.Time,false,proposal.Modifiers);
                        if(_flush?.Invoke()==false) { committed=false; break; }
                    }
                    p.Mode=committed ? Mode.Typing : Mode.Gesture; _gestures.SetKeyboardPriority(side,committed);
                }
            }
        }
        else
        {
            _core.ProcessFrame(side,in frame,maxX,maxY,time);
            if(_core.KeyboardChordOwnsCycle(side)) { p.Mode=Mode.Typing; _gestures.SetKeyboardPriority(side,true); }
        }
        p.LastContacts=active; p.LastTime=time; p.Token=_core.ProposalToken; p.GestureEpoch=evidence.Epoch;
        if(active==0) { p.Count=0; p.Mode=Mode.Idle; _gestures.SetKeyboardPriority(side,false); }
    }
}
