namespace GlassToKey;

// Port of AppleMagicTouchstream's GestureSessionEngine, TapClick and ScrollMomentum.
// Coordinates are millimetres, X right / Y down. Finger/hand identities are optional;
// an unknown identity must never be guessed to be a thumb.
public readonly record struct HandGestureContact(uint Id, double X, double Y, int Finger = 0, int Hand = 0);
public interface IHandGestureOutput
{
    void Move(double xPixels, double yPixels);
    void Scroll(double xPoints, double yPoints);
    void PrimaryButton(bool down);
    void Tap(HandGestureAction action);
}
internal interface IHandGestureRuntime : IDisposable
{
    bool Process(TrackpadSide side, in InputFrame frame, ushort maxX, ushort maxY, long timestamp);
    void Tick();
}

public sealed class HandGestureEngine
{
    private sealed class Pad
    {
        public readonly HandGestureContact[] Previous = new HandGestureContact[InputFrame.MaxContacts];
        public int PreviousCount, PendingCount;
        public double PreviousTime, TravelX, TravelY, LastReceipt;
        public bool Reserved, Blocked;
        public HandGestureTrigger? Owner;
        public ApplePointerAccelerator? Accelerator;
        public readonly CountTap Two = new(2), Three = new(3);
        public readonly ThumbIdentity Thumb = new();
        public readonly HandScrollMomentum Momentum = new();
    }
    private readonly Pad[] _pads = [new(), new()];
    private readonly IHandGestureOutput _output;
    private readonly PerHandGestureSettings[] _settings = [new(), new()];
    private TrackpadSide? _dragOwner;
    public HandGestureEngine(IHandGestureOutput output) { _output = output; }

    public void Configure(HandGestureSettings settings, bool sameDevice)
    {
        Reset(); settings = settings.Clone(); settings.Normalize();
        _settings[0] = settings.For(TrackpadSide.Left, sameDevice);
        _settings[1] = settings.For(TrackpadSide.Right);
        for (int i = 0; i < 2; i++)
        {
            var config = _settings[i];
            _pads[i].Accelerator = config.PointerResponse == HandPointerResponse.Fixed ? null
                : new ApplePointerAccelerator(config.PointerResponse == HandPointerResponse.ImportedApple ? config.ImportedPointerProfile! : ApplePointerProfile.Reference);
        }
    }
    public void Reset()
    {
        foreach (var p in _pads) Cancel(p);
        if (_dragOwner != null) { _output.PrimaryButton(false); _dragOwner = null; }
    }
    private static void Cancel(Pad p)
    {
        p.Owner = null; p.PreviousCount = 0; p.TravelX = p.TravelY = 0;
        p.PendingCount = 0; p.Blocked = true;
        p.Two.Cancel(); p.Three.Cancel(); p.Thumb.Reset(); p.Momentum.Cancel(); p.Accelerator?.Reset();
        // Keep reservation through all-up, including setting/permission transitions.
    }
    private void EndOwner(TrackpadSide side, Pad p)
    {
        p.Owner = null; p.Accelerator?.Reset();
        if (_dragOwner == side) { _output.PrimaryButton(false); _dragOwner = null; }
    }
    public void Tick(double hostTime, bool eligible)
    {
        for (int i = 0; i < 2; i++)
        {
            var p = _pads[i];
            if ((!eligible && (p.Owner.HasValue || p.PreviousCount > 0 || p.Momentum.IsCoasting)) || (p.PreviousCount > 0 && hostTime - p.LastReceipt > .15))
            {
                EndOwner((TrackpadSide)i, p); Cancel(p);
            }
            if (eligible && p.Momentum.Advance(hostTime) is { } delta) _output.Scroll(delta.X, delta.Y);
        }
    }
    public bool Process(TrackpadSide side, ReadOnlySpan<HandGestureContact> contacts, double time, double hostTime, bool eligible, bool? reserveEligible = null)
    {
        int index = (int)side;
        var p = _pads[index]; var settings = _settings[index];
        int count = contacts.Length;
        bool enabled(HandGestureTrigger t) => settings.Get(t) != HandGestureAction.None;
        bool candidate = count switch { 2 => enabled(HandGestureTrigger.TwoFingerMove) || enabled(HandGestureTrigger.TwoFingerTap),
            3 => enabled(HandGestureTrigger.ThreeFingerMove) || enabled(HandGestureTrigger.ThreeFingerTap) || enabled(HandGestureTrigger.ThumbTwoTap),
            4 => enabled(HandGestureTrigger.FourFingerMove), _ => false };
        bool reserved = p.Reserved || ((reserveEligible ?? eligible) && candidate);
        p.Reserved = count > 0 && reserved;
        bool valid = double.IsFinite(time) && double.IsFinite(hostTime) && count <= InputFrame.MaxContacts;
        for (int a = 0; a < count; a++)
        {
            valid &= double.IsFinite(contacts[a].X) && double.IsFinite(contacts[a].Y) && contacts[a].Finger != 6;
            for (int b = 0; b < a; b++) valid &= contacts[a].Id != contacts[b].Id;
        }
        p.LastReceipt = hostTime;
        if (!eligible || !valid || (_dragOwner.HasValue && _dragOwner != side))
        {
            EndOwner(side, p); Cancel(p);
            if (count == 0) { p.Blocked = false; p.Two.Clear(); p.Three.Clear(); }
            return reserved;
        }
        // Starting takeover/settings mid-contact waits for a clean lift.
        if (p.Blocked && count > 0) return reserved;
        bool continued = p.PreviousCount > 0 && time > p.PreviousTime && time - p.PreviousTime < .15;
        bool normalEnd = count == 0 && continued;
        double dx = 0, dy = 0; int shared = 0;
        for (int a = 0; a < count; a++) for (int b = 0; b < p.PreviousCount; b++)
            if (contacts[a].Id == p.Previous[b].Id)
            { dx += contacts[a].X - p.Previous[b].X; dy += contacts[a].Y - p.Previous[b].Y; shared++; break; }
        continued &= count == 0 || shared > 0;
        if (shared > 0) { dx /= shared; dy /= shared; }
        if (!continued && p.PreviousCount > 0)
        {
            EndOwner(side, p); Cancel(p);
            if (count != 0) return reserved;
        }
        if (Math.Abs(dx) >= 25 || Math.Abs(dy) >= 25)
        {
            // Match the Mac motion guard: never pass a discontinuous jump to output.
            EndOwner(side, p); Cancel(p); return reserved;
        }
        if (count > 0 && p.Momentum.IsCoasting)
        { p.Momentum.Cancel(); p.Two.Cancel(); p.Three.Cancel(); }
        if (count == 0)
        {
            bool scrolling = p.Owner.HasValue && settings.Get(p.Owner.Value) == HandGestureAction.Scroll;
            bool owned = p.Owner.HasValue;
            EndOwner(side, p);
            if (scrolling && normalEnd) p.Momentum.Start(time, hostTime); else if (owned) p.Momentum.Cancel();
            bool two = p.Two.Process(contacts, time, owned);
            bool three = p.Three.Process(contacts, time, owned);
            var threeTrigger = p.Thumb.Complete();
            if (two && enabled(HandGestureTrigger.TwoFingerTap) && _dragOwner == null) _output.Tap(settings.Get(HandGestureTrigger.TwoFingerTap));
            if (three && threeTrigger.HasValue && enabled(threeTrigger.Value) && _dragOwner == null) _output.Tap(settings.Get(threeTrigger.Value));
            p.Blocked = false; p.PreviousCount = p.PendingCount = 0; p.TravelX = p.TravelY = 0;
            return reserved;
        }
        if (continued && !p.Owner.HasValue)
        {
            if (p.PendingCount != count) { p.PendingCount = count; p.TravelX = p.TravelY = 0; }
            // A first finger can shift while the second lands. That interval did
            // not have a stable two-finger chord at both ends, so it is a fresh
            // baseline when a two-finger tap is also assigned. Counting its
            // single shared finger's shift as pair motion turns taps into moves.
            // Already-owned gestures bypass this branch and keep shared-ID motion.
            // With tap=None, movement retains its original activation behavior.
            bool formingTapChord = count == 2 && enabled(HandGestureTrigger.TwoFingerTap)
                && (p.PreviousCount != 2 || shared != 2);
            if (formingTapChord) p.TravelX = p.TravelY = 0;
            else { p.TravelX += dx; p.TravelY += dy; }
            HandGestureTrigger? trigger = count switch { 2 => HandGestureTrigger.TwoFingerMove, 3 => HandGestureTrigger.ThreeFingerMove, 4 => HandGestureTrigger.FourFingerMove, _ => null };
            double threshold = count == 4 ? .2 : .35;
            if (trigger.HasValue && enabled(trigger.Value) && Math.Sqrt(p.TravelX*p.TravelX+p.TravelY*p.TravelY) >= threshold
                && (count != 3 || AcceptsRow(contacts)))
            {
                p.Owner = trigger;
                dx = p.TravelX; dy = p.TravelY;
                p.Two.Cancel(); p.Three.Cancel();
                if (settings.Get(trigger.Value) == HandGestureAction.PrimaryDrag)
                {
                    foreach (var pad in _pads) pad.Momentum.Cancel();
                    _output.PrimaryButton(true); _dragOwner = side;
                }
            }
        }
        p.Two.Process(contacts, time, p.Owner.HasValue);
        p.Three.Process(contacts, time, p.Owner.HasValue);
        p.Thumb.Observe(contacts);
        if (p.Owner.HasValue && continued)
        {
            var action = settings.Get(p.Owner.Value);
            if (action == HandGestureAction.Scroll)
            {
                // Windows adapter uses 6 scroll points/mm; no installed Apple profile exists here.
                double direction = settings.NaturalScrolling ? 1 : -1;
                double x = dx * 6 * settings.ScrollSensitivity * direction, y = dy * 6 * settings.ScrollSensitivity * direction;
                if (Math.Abs(x) < 150 && Math.Abs(y) < 150)
                { p.Momentum.Observe(x, y, time); _output.Scroll(x, y); }
                else { EndOwner(side, p); Cancel(p); }
            }
            else if (action is HandGestureAction.Pointer or HandGestureAction.PrimaryDrag)
            {
                (double X,double Y)? delta = p.Accelerator?.Millimetres(time,dx,dy,settings.PointerSensitivity);
                if (p.Accelerator == null) delta = (dx*6*settings.PointerSensitivity,dy*6*settings.PointerSensitivity);
                if (delta is {} value && double.IsFinite(value.X) && double.IsFinite(value.Y))
                {
                    var bounded = PointerMotionLimits.Constrain(value.X,value.Y);
                    _output.Move(bounded.X,bounded.Y);
                }
                else { EndOwner(side,p); Cancel(p); }
            }
        }
        contacts.CopyTo(p.Previous); p.PreviousCount = count; p.PreviousTime = time;
        return reserved;
    }
    internal static bool AcceptsRow(ReadOnlySpan<HandGestureContact> c)
    {
        if (c.Length != 3) return false;
        foreach (var p in c) if (p.Finger is 1 or 6) return false;
        double longest = 0; int a = 0, b = 1;
        for (int i = 0; i < 3; i++) for (int j = i+1; j < 3; j++)
        { double d = Distance(c[i], c[j]); if (d < 2 || d > 60) return false; if (d > longest) { longest = d; a = i; b = j; } }
        var middle = c[3-a-b]; double dx = c[b].X-c[a].X, dy = c[b].Y-c[a].Y;
        return Math.Abs(dx*(middle.Y-c[a].Y)-dy*(middle.X-c[a].X))/longest <= 8
            && Distance(middle, c[a]) <= 35 && Distance(middle, c[b]) <= 35;
    }
    private static double Distance(HandGestureContact a, HandGestureContact b) => Math.Sqrt((a.X-b.X)*(a.X-b.X)+(a.Y-b.Y)*(a.Y-b.Y));

    private sealed class CountTap(int required)
    {
        private readonly HandGestureContact[] _fingers = new HandGestureContact[3];
        private int _known;
        private double _started, _last;
        private double? _paired, _lifting;
        private bool _blocked;
        public void Clear() { _known = 0; _paired = _lifting = null; _blocked = false; }
        public void Cancel() { _blocked = true; }
        public bool Process(ReadOnlySpan<HandGestureContact> c, double time, bool active)
        {
            if (c.Length == 0)
            {
                bool result = !_blocked && !active && _paired.HasValue && time > _last && time-_last <= .15
                    && time-_started <= .5 && (_lifting ?? time)-_paired.Value >= .02 && time-(_lifting ?? time) <= .08;
                Clear(); return result;
            }
            if (_blocked) return false;
            if (active || c.Length > required) { Cancel(); return false; }
            if (_known == 0) { _started = _last = time; }
            else if (time <= _last || time-_last > .15 || time-_started > .5) { Cancel(); return false; }
            foreach (var finger in c)
            {
                int i = 0; while (i < _known && _fingers[i].Id != finger.Id) i++;
                if (i == _known)
                {
                    if (_paired.HasValue || time-_started > .08 || _known >= required) { Cancel(); return false; }
                    _fingers[_known++] = finger;
                }
                if (Distance(finger, _fingers[i]) > 1) { Cancel(); return false; }
            }
            if (c.Length == required)
            { if (_lifting.HasValue) { Cancel(); return false; } _paired ??= time; }
            else if (_paired.HasValue)
            { _lifting ??= time; if (time-_lifting.Value > .08) { Cancel(); return false; } }
            _last = time; return false;
        }
    }
    private sealed class ThumbIdentity
    {
        private bool _sawThumb, _matched, _rejected;
        private uint _thumb, _a, _b;
        private int _hand;
        public void Reset() { _sawThumb = _matched = _rejected = false; _hand = 0; }
        public void Observe(ReadOnlySpan<HandGestureContact> c)
        {
            HandGestureContact? thumb = null, a = null, b = null; bool exact = true; int hand = 0;
            foreach (var p in c)
            {
                _sawThumb |= p.Finger == 1;
                if (p.Finger == 1 && thumb == null) thumb = p;
                else if (p.Finger is >= 2 and <= 5 && a == null) a = p;
                else if (p.Finger is >= 2 and <= 5 && b == null) b = p;
                else exact = false;
                if (p.Hand != 0) { if (hand != 0 && hand != p.Hand) { exact = false; _rejected = true; } hand = p.Hand; }
                if (_matched)
                {
                    bool known = p.Id == _thumb || p.Id == _a || p.Id == _b;
                    if (!known || (p.Finger != 0 && (p.Id == _thumb ? p.Finger != 1 : p.Finger is < 2 or > 5))
                        || (p.Hand != 0 && _hand != 0 && p.Hand != _hand)) _rejected = true;
                }
            }
            if (_matched && _hand == 0) _hand = hand;
            if (c.Length == 3 && exact && thumb.HasValue && a.HasValue && b.HasValue && !_matched)
            {
                double pair = Distance(a.Value,b.Value), near = Math.Min(Distance(thumb.Value,a.Value),Distance(thumb.Value,b.Value));
                if (pair >= 2 && pair <= 40 && near >= 15 && near >= pair*1.5)
                { _matched = true; _thumb = thumb.Value.Id; _a = a.Value.Id; _b = b.Value.Id; _hand = hand; }
            }
        }
        public HandGestureTrigger? Complete()
        {
            HandGestureTrigger? result = _sawThumb ? (_matched && !_rejected ? HandGestureTrigger.ThumbTwoTap : null) : HandGestureTrigger.ThreeFingerTap;
            Reset(); return result;
        }
    }
}

// Exact analytic coast and release-speed window from Mac ScrollMomentum.
internal sealed class HandScrollMomentum
{
    private readonly double[] _x = new double[8], _y = new double[8], _dt = new double[8], _time = new double[8];
    private int _head, _count;
    private double? _lastContact;
    private double _lastX, _lastY, _vx, _vy, _started, _lastTick;
    public bool IsCoasting { get; private set; }
    public void Cancel() { _head = _count = 0; _lastContact = null; _lastX = _lastY = _vx = _vy = 0; IsCoasting = false; }
    public void Observe(double x, double y, double time)
    {
        if (IsCoasting || !double.IsFinite(time) || !double.IsFinite(x) || !double.IsFinite(y) || Math.Abs(x) >= 150 || Math.Abs(y) >= 150) { Cancel(); return; }
        double dt = _lastContact.HasValue ? time-_lastContact.Value : 1.0/90;
        if (dt <= 0 || dt >= .15) { Cancel(); return; }
        if (x*_lastX+y*_lastY < 0) _count = _head = 0;
        _lastContact = time; if (x != 0 || y != 0) { _lastX = x; _lastY = y; }
        _x[_head] = x; _y[_head] = y; _dt[_head] = dt; _time[_head] = time;
        _head = (_head+1)%8; _count = Math.Min(8,_count+1);
    }
    public bool Start(double time, double host)
    {
        if (IsCoasting || !_lastContact.HasValue || time < _lastContact.Value || time-_lastContact.Value >= .08) { Cancel(); return false; }
        double x = 0, y = 0, duration = time-_lastContact.Value;
        for (int age = 0; age < _count; age++)
        {
            int i = (_head+7-age)%8; if (time-_time[i] >= .08 || duration >= .08) break;
            double weight = Math.Min(_dt[i], .08-duration)/_dt[i];
            x += _x[i]*weight; y += _y[i]*weight; duration += _dt[i]*weight;
        }
        if (duration <= 0) { Cancel(); return false; }
        _vx = x/duration; _vy = y/duration; double speed = Math.Sqrt(_vx*_vx+_vy*_vy);
        if (!double.IsFinite(speed) || speed < 30) { Cancel(); return false; }
        if (speed > 6000) { _vx *= 6000/speed; _vy *= 6000/speed; }
        _started = _lastTick = host; IsCoasting = true; return true;
    }
    public (double X, double Y)? Advance(double host)
    {
        if (!IsCoasting) return null;
        if (!double.IsFinite(host) || host <= _lastTick || host-_lastTick > .08) { Cancel(); return null; }
        double from = _lastTick-_started, to = Math.Min(2.5,host-_started);
        double scale = .325*(Math.Exp(-from/.325)-Math.Exp(-to/.325));
        var result = (_vx*scale, _vy*scale); _lastTick = host;
        if (to >= 2.5 || Math.Sqrt(_vx*_vx+_vy*_vy)*Math.Exp(-to/.325) < 5) Cancel();
        return result;
    }
}
