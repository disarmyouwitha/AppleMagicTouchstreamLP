namespace AppleMagicTouchstream;

// Numerical port of Mac Runtime/ScrollGesture.swift. Each axis retains its own
// bounded history; configuring/ending/cancelling a gesture resets both axes.
public sealed record AppleScrollProfile
{
    public ApplePointerProfile Horizontal { get; init; } = new();
    public ApplePointerProfile Vertical { get; init; } = new();
    public bool Natural { get; init; } = true;
    public AppleScrollProfile Copy() => this with { Horizontal=Horizontal.Copy(), Vertical=Vertical.Copy() };
}

public sealed class AppleScrollAxis
{
    private readonly ApplePointerProfile _profile;
    private readonly ApplePointerAccelerator _curve;
    private readonly double[] _times=new double[9], _amounts=new double[9];
    private int _head, _tail;
    private double? _lastTime;
    private bool? _positive;
    public AppleScrollAxis(ApplePointerProfile profile) { _profile=profile.Copy(); _curve=new(profile); }
    public void Reset() { _head=_tail=0; _lastTime=null; _positive=null; }
    public double? Points(double time,double counts)
    {
        if(!double.IsFinite(time) || !double.IsFinite(counts)) { Reset(); return null; }
        if(counts==0) return 0;
        double elapsed=_lastTime.HasValue ? (time-_lastTime.Value)*1000 : 150;
        if(elapsed<=0) { Reset(); return null; }
        _lastTime=time;
        if(_profile.Acceleration<0) return counts;
        int inserted=_head;
        _times[_head]=elapsed; _amounts[_head]=Math.Abs(counts);
        _head=(_head+1)%9;
        if(_head==_tail) _tail=(_tail+1)%9;
        if(_positive!=(counts>0) || elapsed>500) { _tail=inserted; _positive=counts>0; }
        double sumTime=0,sumAmount=0; int samples=0,index=_head;
        do
        {
            index=(index+8)%9; sumAmount+=_amounts[index]; samples++;
            if(_times[index]>150) { sumTime+=150; break; }
            sumTime+=_times[index];
            if(sumTime>=500) break;
        } while(index!=_tail);
        double rate=_profile.AlgorithmRate/67;
        double meanTime=Math.Clamp(sumTime/samples*rate,1,150);
        double velocity=Math.Max(1.0/65536,(2.0/65536*meanTime*meanTime-955.0/65536*meanTime+98369.0/65536)*sumAmount/samples*rate);
        double output=counts*_curve.AcceleratedVelocity(velocity)/velocity*(6554.0/65536)*10;
        if(!double.IsFinite(output) || Math.Abs(output)>=150) { Reset(); return null; }
        return output;
    }
}

public sealed class AppleScrollAccelerator
{
    private readonly AppleScrollProfile _profile;
    private readonly AppleScrollAxis _x,_y;
    public AppleScrollAccelerator(AppleScrollProfile profile)
    { _profile=profile.Copy(); _x=new(_profile.Horizontal); _y=new(_profile.Vertical); }
    public void Reset() { _x.Reset(); _y.Reset(); }
    public (double X,double Y)? Millimetres(double time,double x,double y,double sensitivity,bool natural)
    {
        if(!double.IsFinite(sensitivity)) { Reset(); return null; }
        double scale=Math.Clamp(sensitivity,.25,2);
        var dx=_x.Points(time,x*_profile.Horizontal.Resolution/25.4*scale);
        var dy=_y.Points(time,y*_profile.Vertical.Resolution/25.4*scale);
        if(!dx.HasValue || !dy.HasValue) { Reset(); return null; }
        double sign=natural ? 1 : -1;
        return(dx.Value*sign,dy.Value*sign);
    }
}
