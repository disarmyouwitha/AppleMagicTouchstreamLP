namespace AppleMagicTouchstream;

// Fit continuing contacts around their centroid for legacy geometric callers.
// With reported anatomy, use Mac's thumb-to-fingertip-centroid vector instead.
// The Windows host requires a positive thumb before activating rotation.
internal sealed class HandRotationTracker
{
    internal readonly record struct Sample(double Angle,double Arc,double Radial,double FrameAngle);
    private readonly HandGestureContact[] _origin=new HandGestureContact[5];
    private int _count;
    private double _time,_lastAngle;
    public void Reset() { _count=0; _lastAngle=0; }
    public Sample? Process(ReadOnlySpan<HandGestureContact> contacts,double time,bool latched)
    {
        if(contacts.Length is <2 or >5 || !double.IsFinite(time)) { Reset(); return null; }
        bool same=_count==contacts.Length && time>_time && time-_time<.15;
        foreach(var c in contacts)
        {
            bool found=false;
            for(int i=0;i<_count;i++) found|=c.Id==_origin[i].Id;
            same&=found;
        }
        if(!same)
        {
            bool continuous=_count>0 && time>_time && time-_time<.15;
            contacts.CopyTo(_origin); _count=contacts.Length; _time=time; _lastAngle=0;
            return latched && continuous ? new(0,0,0,0) : null;
        }
        _time=time;
        double ax=0,ay=0,bx=0,by=0;
        int thumbs=0,thumbIndex=-1;
        for(int i=0;i<_count;i++)
        {
            ax+=_origin[i].X; ay+=_origin[i].Y; bx+=contacts[i].X; by+=contacts[i].Y;
            if(contacts[i].Finger==1) { thumbs++; thumbIndex=i; }
        }
        double cross=0,dot=0,oldRadius,newRadius;
        if(thumbs==1)
        {
            var thumb=contacts[thumbIndex]; int oldIndex=0;
            while(_origin[oldIndex].Id!=thumb.Id) oldIndex++;
            var oldThumb=_origin[oldIndex];
            ax=(ax-oldThumb.X)/(_count-1)-oldThumb.X; ay=(ay-oldThumb.Y)/(_count-1)-oldThumb.Y;
            bx=(bx-thumb.X)/(_count-1)-thumb.X; by=(by-thumb.Y)/(_count-1)-thumb.Y;
            oldRadius=double.Hypot(ax,ay); newRadius=double.Hypot(bx,by);
            cross=ax*by-ay*bx; dot=ax*bx+ay*by;
        }
        else
        {
            ax/=_count; ay/=_count; bx/=_count; by/=_count;
            double ar=0,br=0;
            foreach(var c in contacts)
            {
                int i=0; while(_origin[i].Id!=c.Id) i++;
                double x=_origin[i].X-ax,y=_origin[i].Y-ay,u=c.X-bx,v=c.Y-by;
                cross+=x*v-y*u; dot+=x*u+y*v; ar+=x*x+y*y; br+=u*u+v*v;
            }
            // Diameter is the thumb-vector equivalent for a two-contact chord.
            oldRadius=2*Math.Sqrt(ar/_count); newRadius=2*Math.Sqrt(br/_count);
        }
        if(Math.Min(oldRadius,newRadius)<15) return null;
        double angle=Math.Atan2(cross,dot);
        double frame=Math.Atan2(Math.Sin(angle-_lastAngle),Math.Cos(angle-_lastAngle));
        _lastAngle=angle;
        return new(angle,Math.Abs(angle)*Math.Min(oldRadius,newRadius),Math.Abs(newRadius-oldRadius),frame);
    }
}
