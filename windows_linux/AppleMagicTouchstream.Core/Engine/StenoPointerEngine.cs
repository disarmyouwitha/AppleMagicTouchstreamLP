namespace AppleMagicTouchstream;

// Fixed STENO mouse policy. Pending two-hand chords retain priority; a mouse win
// owns the whole chord cycle, while each pad retains its own drag/scroll lifetime.
public sealed class StenoPointerEngine
{
    private enum Owner {None,Pointer,Drag,Click,Scroll}
    private sealed class Pad
    {
        public readonly HandGestureContact[] Previous=new HandGestureContact[InputFrame.MaxContacts],Origin=new HandGestureContact[2];
        public int Count,OriginCount,MaximumCount;
        public double LastTime=-1,Receipt;
        public bool Blocked,ForceBlocked;
        public Owner Owner;
        public ApplePointerAccelerator Pointer=new(ApplePointerProfile.Reference);
        public AppleScrollAccelerator? Scroll;
        public readonly HandScrollMomentum Momentum=new();
        public double PointerGain=1,ScrollGain=1;
        public bool Natural=true;
    }
    private readonly Pad[] _pads=[new(),new()];
    private readonly IHandGestureOutput _output;
    private byte _down,_dragOwners;
    private bool _cycleOwned,_sawBoth;
    private double _forceThreshold=130;
    public bool HasOwner=>_cycleOwned;
    public StenoPointerEngine(IHandGestureOutput output) { _output=output; }
    // Retired finger-mode argument remains API-compatible; all modes use 2F.
    public void Configure(int fingers,HandGestureSettings? motion=null,double forceThreshold=130)
    {
        Cancel();_forceThreshold=double.IsFinite(forceThreshold) ? Math.Clamp(forceThreshold,1,500):130;
        for(int i=0;i<2;i++)
        {
            var hand=i==0 ? motion?.Left:motion?.Right;var pad=_pads[i];
            pad.Pointer=new(hand is {PointerResponse:HandPointerResponse.ImportedApple,ImportedPointerProfile:{} profile} ? profile:ApplePointerProfile.Reference);
            pad.Scroll=hand?.ImportedScrollProfile is {} scroll ? new(scroll):null;
            pad.PointerGain=hand?.PointerSensitivity ?? 1;pad.ScrollGain=hand?.ScrollSensitivity ?? 1;pad.Natural=hand?.NaturalScrolling ?? true;
        }
    }
    private void Release(TrackpadSide side)
    {
        byte bit=(byte)(1<<(int)side);
        if((_dragOwners&bit)!=0) { _dragOwners&=(byte)~bit;if(_dragOwners==0)_output.PrimaryButton(false); }
        var p=_pads[(int)side];p.Owner=Owner.None;p.Pointer.Reset();p.Scroll?.Reset();
    }
    public void Cancel(TrackpadSide? side=null)
    {
        for(int i=0;i<2;i++)if(side==null || (int)side==i)
        { var p=_pads[i];Release((TrackpadSide)i);_down&=(byte)~(1<<i);p.Blocked=p.Count>0;p.ForceBlocked=p.Count>0;p.Momentum.Cancel();p.OriginCount=0; }
        if(_down==0) {_cycleOwned=false;_sawBoth=false;}
    }
    public void Tick(double hostTime,bool eligible)
    {
        for(int i=0;i<2;i++)
        {
            var p=_pads[i];
            if(!eligible || p.Count>0 && hostTime-p.Receipt>.15) { Cancel((TrackpadSide)i);continue; }
            if(p.Momentum.Advance(hostTime) is {} scroll)_output.Scroll(scroll.X,scroll.Y);
        }
    }
    public bool Process(TrackpadSide side,ReadOnlySpan<HandGestureContact> contacts,double time,double hostTime,bool eligible)
    {
        var p=_pads[(int)side];byte bit=(byte)(1<<(int)side);bool priorCycle=_cycleOwned;
        bool valid=eligible && contacts.Length<=InputFrame.MaxContacts && double.IsFinite(time) && double.IsFinite(hostTime) && hostTime>=time && hostTime-time<=.15 && (p.LastTime<0 || time>p.LastTime && (p.Count==0 || time-p.LastTime<=.15));
        for(int i=0;i<contacts.Length;i++)
        {
            var c=contacts[i];valid&=double.IsFinite(c.X) && double.IsFinite(c.Y) && c.X>=0 && c.X<=160 && c.Y>=0 && c.Y<=114.9;
            valid&=!c.HasPressure || double.IsFinite(c.Pressure) && c.Pressure>=0 && c.Pressure<=500;
            for(int j=0;j<i;j++)valid&=c.Id!=contacts[j].Id;
        }
        if(contacts.Length>0)_down|=bit;else _down&=(byte)~bit;
        if(contacts.Length>0)foreach(var pad in _pads)pad.Momentum.Cancel();
        if(_down==3 && !_cycleOwned)_sawBoth=true;
        double dx=0,dy=0;int matched=0;
        foreach(var c in contacts)for(int j=0;j<p.Count;j++)if(p.Previous[j].Id==c.Id){dx+=c.X-p.Previous[j].X;dy+=c.Y-p.Previous[j].Y;matched++;break;}
        if(matched>0){dx/=matched;dy/=matched;}
        if(p.Count>0 && contacts.Length>0 && matched==0)valid=false;
        if(Math.Abs(dx)>=25 || Math.Abs(dy)>=25)valid=false;
        p.LastTime=time;p.Receipt=hostTime;
        if(!valid)
        { p.Count=Math.Min(contacts.Length,InputFrame.MaxContacts);Cancel(side);if(contacts.Length==0)Clear(p);if(_down==0){_cycleOwned=false;_sawBoth=false;}return priorCycle; }
        if(contacts.Length==0)
        {
            bool scroll=p.Owner==Owner.Scroll;Release(side);
            if(scroll)p.Momentum.Start(time,hostTime);
            Clear(p);
            if(_down==0){_cycleOwned=false;_sawBoth=false;}
            return priorCycle;
        }
        if(contacts.Length<p.Count)p.ForceBlocked=true;
        if(contacts.Length>4)p.ForceBlocked=true;
        if(p.Blocked){Remember(p,contacts);return _cycleOwned;}
        p.MaximumCount=Math.Max(p.MaximumCount,contacts.Length);
        bool mayActivate=_cycleOwned || !_sawBoth && _down==bit;
        if(p.Owner is Owner.None or Owner.Pointer && !p.ForceBlocked && mayActivate && contacts.Length<=4)
        {
            bool high=false;foreach(var c in contacts)high|=c.HasPressure && c.Pressure>=_forceThreshold;
            if(high)
            {
                _cycleOwned=true;p.Pointer.Reset();p.Scroll?.Reset();p.Momentum.Cancel();
                p.Owner=contacts.Length switch {1=>Owner.Drag,4=>Owner.Scroll,_=>Owner.Click};
                if(p.Owner==Owner.Drag){bool first=_dragOwners==0;_dragOwners|=bit;if(first)_output.PrimaryButton(true);}
                else if(p.Owner==Owner.Click)_output.Tap(contacts.Length==2 ? HandGestureAction.PrimaryClick:HandGestureAction.SecondaryClick);
                _output.ForceFeedback(side);Remember(p,contacts);return true; // discard all pre-force travel
            }
        }
        if(p.Owner==Owner.Scroll)
        {
            double sign=p.Natural ? 1:-1;
            (double X,double Y)? result=p.Scroll is {} accelerator ? accelerator.Millimetres(time,dx,dy,p.ScrollGain,p.Natural):(dx*6*p.ScrollGain*sign,dy*6*p.ScrollGain*sign);
            if(result is not {} scroll){Cancel(side);Remember(p,contacts);return _cycleOwned;}
            if(double.IsFinite(scroll.X) && double.IsFinite(scroll.Y) && Math.Abs(scroll.X)<150 && Math.Abs(scroll.Y)<150)
            {p.Momentum.Observe(scroll.X,scroll.Y,time);_output.Scroll(scroll.X,scroll.Y);}
            else Cancel(side);
        }
        else if(p.Owner is Owner.Drag or Owner.Pointer)
        {Move(p,time,dx,dy,side);}
        else if(p.Owner==Owner.None && p.MaximumCount<=2 && contacts.Length==2 && mayActivate)
        {
            if(p.OriginCount!=2){contacts.CopyTo(p.Origin);p.OriginCount=2;}
            else
            {
                double ax=0,ay=0,bx=0,by=0;bool continuous=true;
                for(int i=0;i<2;i++){int j=contacts[0].Id==p.Origin[i].Id ? 0:contacts[1].Id==p.Origin[i].Id ? 1:-1;if(j<0){continuous=false;break;}if(i==0){ax=contacts[j].X-p.Origin[i].X;ay=contacts[j].Y-p.Origin[i].Y;}else{bx=contacts[j].X-p.Origin[i].X;by=contacts[j].Y-p.Origin[i].Y;}}
                double x=(ax+bx)/2,y=(ay+by)/2,length=Math.Sqrt(x*x+y*y);
                if(continuous && length>=2 && (ax*x+ay*y)/length>=1.5 && (bx*x+by*y)/length>=1.5 && Math.Sqrt(Math.Pow(ax-bx,2)+Math.Pow(ay-by,2))<=length*.6+.5)
                {p.Owner=Owner.Pointer;_cycleOwned=true;Move(p,time,x,y,side);}
            }
        }
        Remember(p,contacts);return _cycleOwned;
    }
    private void Move(Pad p,double time,double dx,double dy,TrackpadSide side)
    {
        if(p.Pointer.Millimetres(time,dx,dy,p.PointerGain) is {} delta)
        {var bounded=PointerMotionLimits.Constrain(delta.X,delta.Y);_output.Move(bounded.X,bounded.Y);}
        else Cancel(side);
    }
    private static void Remember(Pad p,ReadOnlySpan<HandGestureContact> contacts){p.Count=contacts.Length;contacts.CopyTo(p.Previous);}
    private static void Clear(Pad p){p.Count=p.OriginCount=p.MaximumCount=0;p.LastTime=-1;p.Blocked=p.ForceBlocked=false;p.Owner=Owner.None;p.Pointer.Reset();p.Scroll?.Reset();}
}
