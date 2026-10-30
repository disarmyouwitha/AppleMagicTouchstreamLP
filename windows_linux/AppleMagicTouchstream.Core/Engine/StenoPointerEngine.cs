namespace AppleMagicTouchstream;

// Stationary contacts remain steno. Only a stable configured-finger translation can
// acquire the pointer; its ownership persists through all-up, including partial lifts.
public sealed class StenoPointerEngine
{
    private sealed class Pad
    {
        public readonly HandGestureContact[] Origin=new HandGestureContact[2],Previous=new HandGestureContact[2];
        public readonly ApplePointerAccelerator Accelerator=new(ApplePointerProfile.Reference);
        public bool Pair,Blocked,Claimed;
        public double LastTime=-1,LastReceipt;
        public void Clear() { Pair=Blocked=Claimed=false; LastTime=-1; Accelerator.Reset(); }
    }
    private readonly Pad[] _pads=[new(),new()];
    private readonly IHandGestureOutput _output;
    private int _fingers=2;
    public void Configure(int fingers) { _fingers=fingers==1 ? 1 : 2; Cancel(); }
    public StenoPointerEngine(IHandGestureOutput output) { _output=output; }
    public void Cancel(TrackpadSide? side=null)
    {
        for(int i=0;i<2;i++) if(side==null || (int)side==i)
        { var p=_pads[i]; p.Pair=false; p.Blocked=p.LastTime>=0 || p.Claimed; p.Accelerator.Reset(); }
    }
    public void Tick(double hostTime,bool eligible)
    {
        for(int i=0;i<2;i++) if(!eligible || (_pads[i].LastTime>=0 && hostTime-_pads[i].LastReceipt>.15)) Cancel((TrackpadSide)i);
    }
    public bool Process(TrackpadSide side,ReadOnlySpan<HandGestureContact> contacts,double time,double hostTime,bool eligible)
    {
        var p=_pads[(int)side];
        bool valid=eligible && double.IsFinite(time) && double.IsFinite(hostTime) && hostTime>=time && hostTime-time<=.15
            && (p.LastTime<0 || (time>p.LastTime && time-p.LastTime<=.15));
        for(int i=0;i<contacts.Length;i++)
        {
            var c=contacts[i];
            valid &= double.IsFinite(c.X) && double.IsFinite(c.Y) && c.X>=0 && c.X<=160 && c.Y>=0 && c.Y<=114.9;
            for(int j=0;j<i;j++) if(contacts[j].Id==c.Id) valid=false;
        }
        p.LastTime=time; p.LastReceipt=hostTime;
        if(contacts.Length==0) { bool claimed=p.Claimed; p.Clear(); return claimed; }
        if(!valid || contacts.Length>_fingers) { Cancel(side); return p.Claimed; }
        if(p.Blocked) return p.Claimed;
        if(contacts.Length!=_fingers)
        {
            if(p.Claimed) Cancel(side); else p.Pair=false;
            return p.Claimed;
        }
        if(!p.Pair) { contacts.CopyTo(p.Origin); contacts.CopyTo(p.Previous); p.Pair=true; return false; }
        Span<HandGestureContact> ordered=stackalloc HandGestureContact[2];
        for(int i=0;i<_fingers;i++)
        {
            int j=contacts[0].Id==p.Origin[i].Id ? 0 : _fingers==2 && contacts[1].Id==p.Origin[i].Id ? 1 : -1;
            if(j<0) { Cancel(side); return p.Claimed; }
            ordered[i]=contacts[j];
        }
        double ax=ordered[0].X-p.Origin[0].X,ay=ordered[0].Y-p.Origin[0].Y;
        double bx=_fingers==2 ? ordered[1].X-p.Origin[1].X : ax,by=_fingers==2 ? ordered[1].Y-p.Origin[1].Y : ay;
        double dx=_fingers==1 ? ordered[0].X-p.Previous[0].X : ((ordered[0].X-p.Previous[0].X)+(ordered[1].X-p.Previous[1].X))/2;
        double dy=_fingers==1 ? ordered[0].Y-p.Previous[0].Y : ((ordered[0].Y-p.Previous[0].Y)+(ordered[1].Y-p.Previous[1].Y))/2;
        if(Math.Abs(dx)>=25 || Math.Abs(dy)>=25) { Cancel(side); return p.Claimed; }
        if(!p.Claimed)
        {
            double x=(ax+bx)/2,y=(ay+by)/2,length=Math.Sqrt(x*x+y*y);
            // Both fingers must contribute: settling one finger, pinches and
            // spreads cannot acquire the pointer. Three-plus-contact chords
            // cannot become pointer movement after a partial lift.
            if(length>=2 && (ax*x+ay*y)/length>=1.5 && (bx*x+by*y)/length>=1.5
                && Math.Sqrt((ax-bx)*(ax-bx)+(ay-by)*(ay-by))<=length*.6+.5)
            { p.Claimed=true; dx=x; dy=y; }
        }
        if(p.Claimed)
        {
            var delta=p.Accelerator.Millimetres(time,dx,dy,1);
            if(delta is {} move && double.IsFinite(move.X) && double.IsFinite(move.Y))
            { var bounded=PointerMotionLimits.Constrain(move.X,move.Y); _output.Move(bounded.X,bounded.Y); }
            else Cancel(side);
        }
        ordered.CopyTo(p.Previous); return p.Claimed;
    }
}
