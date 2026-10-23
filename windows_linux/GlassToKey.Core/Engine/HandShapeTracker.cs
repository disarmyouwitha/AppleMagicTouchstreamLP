namespace GlassToKey;

// Port of AppleMagicTouchstream PinchSpreadTracker. All geometry is in mm;
// fixed per-pad storage keeps frame processing allocation-free.
internal sealed class HandShapeTracker
{
    internal readonly record struct Sample(double Change, double InitialRatio, double FrameRatio);
    private readonly HandGestureContact[] _previous = new HandGestureContact[5];
    private int _count;
    private double _time, _initial, _span, _anchorX, _anchorY;
    private bool _anchor;
    public void Reset() { _count = 0; _anchor = false; }
    public Sample? Process(ReadOnlySpan<HandGestureContact> contacts, double time, bool latched)
    {
        int count = contacts.Length;
        if (count == 0 || count > 5 || (!latched && count < 2)) { Reset(); return null; }
        bool continuous = _count > 0 && time > _time && time-_time < .15;
        double anchorX = 0, anchorY = 0;
        bool anchor = false;
        if (latched && count == 1 && continuous)
        {
            if (_count == 1) { anchor = _anchor; anchorX = _anchorX; anchorY = _anchorY; }
            else
            {
                int others = 0;
                for (int i=0; i<_count; i++) if (_previous[i].Id != contacts[0].Id)
                { anchorX += _previous[i].X; anchorY += _previous[i].Y; others++; }
                if (others > 0) { anchor = true; anchorX /= others; anchorY /= others; }
            }
        }
        double span = Span(contacts,anchor,anchorX,anchorY);
        if (!double.IsFinite(span) || span < 5 || span >= 200) { Reset(); return null; }
        bool same = continuous && count == _count;
        if (same) foreach (var c in contacts)
        {
            bool found = false;
            for (int i=0; i<_count; i++) found |= c.Id == _previous[i].Id;
            same &= found;
        }
        Sample? result = null;
        double initial = span;
        if (same)
        {
            if (Math.Abs(span-_span) >= 15) { Reset(); return null; }
            initial = _initial;
            result = new(span-initial,span/initial-1,span/_span-1);
        }
        else if (continuous && latched)
        {
            result = new(0,0,0);
            if (count == 1 && anchor)
                for (int i=0; i<_count; i++) if (_previous[i].Id == contacts[0].Id)
                {
                    double old = double.Hypot(_previous[i].X-anchorX,_previous[i].Y-anchorY);
                    if (old >= 5 && Math.Abs(span-old) < 15) result = new(0,0,span/old-1);
                    break;
                }
        }
        contacts.CopyTo(_previous); _count = count; _time = time; _initial = initial;
        _span = span; _anchor = anchor; _anchorX = anchorX; _anchorY = anchorY;
        return result;
    }
    private static double Span(ReadOnlySpan<HandGestureContact> c, bool anchor, double x, double y)
    {
        if (c.Length == 1 && anchor) return double.Hypot(c[0].X-x,c[0].Y-y);
        double sum = 0; int pairs = 0;
        for (int i=0; i<c.Length; i++) for (int j=0; j<i; j++)
        { double dx=c[i].X-c[j].X, dy=c[i].Y-c[j].Y; sum += dx*dx+dy*dy; pairs++; }
        return pairs > 0 ? Math.Sqrt(sum/pairs) : 0;
    }
}
