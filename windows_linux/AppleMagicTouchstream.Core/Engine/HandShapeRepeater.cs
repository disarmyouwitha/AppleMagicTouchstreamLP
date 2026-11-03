namespace AppleMagicTouchstream;

// Mac GestureShapeRepeater: one initial action, then timed or signed motion
// steps. One output per frame/tick, with no catch-up bursts after a late tick.
internal sealed class HandShapeRepeater
{
    private HandGestureTrigger? _trigger;
    private HandShapeRepeat _config=HandShapeRepeat.Default;
    private double _receipt, _deadline, _progress;
    public void Reset() { _trigger=null; _progress=0; }
    public bool Process(HandGestureTrigger trigger,HandShapeRepeat config,double now,double delta,bool began)
    {
        if (began)
        {
            Reset(); _config=config; _receipt=now; _deadline=now+config.IntervalMilliseconds/1000;
            if(config.Mode!=HandShapeRepeatMode.Once) _trigger=trigger;
            return true;
        }
        if(_trigger!=trigger || config!=_config || !double.IsFinite(now) || now<_receipt || now-_receipt>.2)
        { Reset(); return false; }
        _receipt=now;
        if(config.Mode!=HandShapeRepeatMode.Motion || !double.IsFinite(delta)) return false;
        double step;
        if(PerHandGestureSettings.IsRotation(trigger))
            step=delta*(PerHandGestureSettings.RotatesRight(trigger) ? 1 : -1)/(Math.PI/36);
        else
        {
            if(delta<=-1) return false;
            bool spread=trigger is >= HandGestureTrigger.TwoFingerSpread and <= HandGestureTrigger.FiveFingerSpread;
            step=Math.Log(1+delta)*(spread ? 1 : -1)/Math.Log(1.06);
        }
        _progress=Math.Max(0,_progress+step);
        if(_progress<1) return false;
        _progress%=1; return true;
    }
    public HandGestureTrigger? Tick(double now)
    {
        if(_trigger==null) return null;
        if(!double.IsFinite(now) || now<_receipt || now-_receipt>.2) { Reset(); return null; }
        if(_config.Mode!=HandShapeRepeatMode.Timed || now<_deadline) return null;
        _deadline=now+_config.IntervalMilliseconds/1000;
        return _trigger;
    }
}
