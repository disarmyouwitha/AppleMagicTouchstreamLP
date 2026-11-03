namespace AppleMagicTouchstream;

// Positive anatomy and Mac's spread-thumb geometry. IDs identify contacts only.
internal static class ThumbTwoChord
{
    internal static bool Matches(ReadOnlySpan<HandGestureContact> contacts)
    {
        if(contacts.Length!=3) return false;
        int thumb=-1,a=-1,b=-1,hand=0;
        for(int i=0;i<3;i++)
        {
            var c=contacts[i];
            if(!double.IsFinite(c.X) || !double.IsFinite(c.Y)) return false;
            if(c.Hand!=0) { if(hand!=0 && hand!=c.Hand) return false; hand=c.Hand; }
            if(c.Finger==1 && thumb<0) thumb=i;
            else if(c.Finger is >=2 and <=5 && a<0) a=i;
            else if(c.Finger is >=2 and <=5 && b<0) b=i;
            else return false;
        }
        if(thumb<0 || a<0 || b<0 || contacts[a].Finger==contacts[b].Finger) return false;
        double pair=Distance(contacts[a],contacts[b]);
        double near=Math.Min(Distance(contacts[thumb],contacts[a]),Distance(contacts[thumb],contacts[b]));
        return pair>=2 && pair<=40 && near>=15 && near>=pair*1.5;
    }
    private static double Distance(HandGestureContact a,HandGestureContact b)=>Math.Sqrt((a.X-b.X)*(a.X-b.X)+(a.Y-b.Y)*(a.Y-b.Y));
}

// One stepper per existing session owner; changing direction never acquires a new owner.
internal sealed class ThumbDirectionalStepper
{
    internal const double Activation=0.75, MinimumInterval=.08;
    internal HandMovementDirection? Direction { get; private set; }
    private HandMovementDirection? _candidate;
    private double _candidateTravel,_motion,_lastOutput;
    internal static HandMovementDirection? Diagonal(double x,double y)
    {
        if(!double.IsFinite(x) || !double.IsFinite(y) || x==0 || y==0
            || Math.Min(Math.Abs(x),Math.Abs(y))<Math.Max(Math.Abs(x),Math.Abs(y))*(Math.Sqrt(2)-1)) return null;
        return y<0 ? x<0 ? HandMovementDirection.UpLeft:HandMovementDirection.UpRight
            : x<0 ? HandMovementDirection.DownLeft:HandMovementDirection.DownRight;
    }
    internal static double Projection(HandMovementDirection d,double x,double y)
        =>((d is HandMovementDirection.UpLeft or HandMovementDirection.DownLeft ? -x:x)
            +(d is HandMovementDirection.UpLeft or HandMovementDirection.UpRight ? -y:y))/Math.Sqrt(2);
    internal void Reset() { Direction=_candidate=null; _candidateTravel=_motion=0; _lastOutput=0; }
    internal void Begin(HandMovementDirection direction,double now)
    { Reset(); Direction=direction; _lastOutput=now; }
    internal HandMovementDirection? Process(double x,double y,double now,HandDirectionalSettings settings)
    {
        if(Direction is not {} current || x==0 && y==0) return null;
        var next=Diagonal(x,y);
        if(next is {} direction && direction!=current)
        {
            _motion=0;
            if(_candidate!=direction) { _candidate=direction; _candidateTravel=0; }
            _candidateTravel+=Projection(direction,x,y);
            if(_candidateTravel<Activation || now-_lastOutput<MinimumInterval) return null;
            Direction=direction; _candidate=null; _candidateTravel=0; _lastOutput=now;
            return direction;
        }
        _candidate=null; _candidateTravel=0;
        if(next==current && settings.Mode(current)==HandShapeRepeatMode.Motion)
        {
            _motion+=Math.Max(0,Projection(current,x,y));
            if(_motion>=Activation && now-_lastOutput>=MinimumInterval)
            { _motion=0; _lastOutput=now; return current; }
        }
        else _motion=0;
        return null;
    }
    internal HandMovementDirection? Tick(double now,HandDirectionalSettings settings)
    {
        if(Direction is not {} current || _candidate!=null || settings.Mode(current)!=HandShapeRepeatMode.Timed) return null;
        double interval=Math.Max(MinimumInterval,settings.Repeat(current)/1000);
        if(now-_lastOutput<interval) return null;
        _lastOutput=now; return current;
    }
}
