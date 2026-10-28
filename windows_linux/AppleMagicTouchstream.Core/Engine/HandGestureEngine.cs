namespace AppleMagicTouchstream;

// Port of AppleMagicTouchstream's GestureSessionEngine, TapClick and ScrollMomentum.
// Coordinates are millimetres, X right / Y down. Finger/hand identities are optional;
// an unknown identity must never be guessed to be a thumb.
public readonly record struct HandGestureContact(uint Id, double X, double Y, int Finger = 0, int Hand = 0, double Pressure = 0, bool HasPressure = false);
public interface IHandGestureOutput
{
    void Move(double xPixels, double yPixels);
    void Scroll(double xPoints, double yPoints);
    void PrimaryButton(bool down);
    void Tap(HandGestureAction action);
    void Zoom(double scaleDelta);
    void ForceFeedback(TrackpadSide side);
    // Semantic catalog identity, dispatched only by live platform adapters.
    void AssignedAction(string label) { }
    void HeldAssignment(int owner,string? label) { }
}
public readonly record struct HandGestureEvidence(bool Enabled,bool Reserved,bool Claimed,bool TapPending,long Epoch);
internal interface IHandGestureRuntime : IDisposable
{
    bool Process(TrackpadSide side, in InputFrame frame, ushort maxX, ushort maxY, long timestamp);
    void Tick();
    bool SupportsKeyboardProposals => false;
    void SetKeyboardPriority(TrackpadSide side,bool priority) { }
    HandGestureEvidence Evidence(TrackpadSide side) => default;
    void Cancel(TrackpadSide? side=null) { }
}

public sealed class HandGestureEngine
{
    private const double DragScrollSettleSeconds = .12;
    private sealed class Pad
    {
        public readonly HandGestureContact[] Previous = new HandGestureContact[InputFrame.MaxContacts];
        public int PreviousCount, PendingCount;
        public double PreviousTime, TravelX, TravelY, LastReceipt, ThreeChordSince;
        public bool Reserved, Blocked, SawFour, ForceBlocked, ForceClaimed, CycleClaimed, KeyboardOwned;
        public HandGestureEvidence Evidence;
        public HandGestureTrigger? Owner;
        public ApplePointerAccelerator? Accelerator;
        public readonly CountTap Two = new(2), Three = new(3), Four = new(4), Five = new(5);
        public readonly HandGestureContact[] HoldOrigin = new HandGestureContact[5];
        public int HoldCount;
        public double HoldSince, DirectionTime, DirectionTravel;
        public bool HoldBlocked, HoldClaimed, CornerPending;
        public HandMovementDirection? Direction;
        public readonly ThumbIdentity Thumb = new();
        public readonly HandScrollMomentum Momentum = new();
        public readonly HandShapeTracker Shape = new();
    }
    private readonly Pad[] _pads = [new(), new()];
    private readonly IHandGestureOutput _output;
    private readonly CoordinatedHandGestureEngine _coordinated = new();
    private readonly PerHandGestureSettings[] _settings = [new(), new()];
    private TrackpadSide? _dragOwner;
    private long _epoch;
    public HandGestureEngine(IHandGestureOutput output) { _output = output; }

    public void Configure(HandGestureSettings settings, bool sameDevice)
    {
        Reset(); settings = settings.Clone(); settings.Normalize();
        _settings[0] = settings.For(TrackpadSide.Left, sameDevice);
        _settings[1] = settings.For(TrackpadSide.Right);
        _coordinated.Configure(settings.Coordinated ?? new(), !sameDevice);
        for (int i = 0; i < 2; i++)
        {
            var config = _settings[i];
            _pads[i].Accelerator = config.PointerResponse == HandPointerResponse.Fixed ? null
                : new ApplePointerAccelerator(config.PointerResponse == HandPointerResponse.ImportedApple ? config.ImportedPointerProfile! : ApplePointerProfile.Reference);
        }
    }
    public void Reset()
    {
        _epoch++;
        for (int i=0;i<2;i++) { _output.HeldAssignment(i,null); Cancel(_pads[i]); }
        _output.HeldAssignment(2,null); _coordinated.Reset();
        if (_dragOwner != null) { _output.PrimaryButton(false); _dragOwner = null; }
    }
    public void Cancel(TrackpadSide side) { EndOwner(side,_pads[(int)side]); Cancel(_pads[(int)side]); _coordinated.Cancel(_output); }
    private static void Cancel(Pad p)
    {
        p.CycleClaimed=true;
        p.Owner = null; p.PreviousCount = 0; p.TravelX = p.TravelY = 0;
        p.PendingCount = 0; p.Blocked = true; p.ThreeChordSince = double.NaN; p.SawFour = false;
        CancelTaps(p); p.Thumb.Reset(); p.Momentum.Cancel(); p.Accelerator?.Reset();
        p.HoldCount = 0; p.HoldBlocked = true; p.HoldClaimed = false; p.Direction = null; p.DirectionTravel = 0;
        p.CornerPending = false;
        p.Shape.Reset(); p.ForceBlocked = true; p.ForceClaimed = false;
        // Keep reservation through all-up, including setting/permission transitions.
    }
    private static void CancelTaps(Pad p) { p.Two.Cancel(); p.Three.Cancel(); p.Four.Cancel(); p.Five.Cancel(); }
    private void Emit(PerHandGestureSettings settings,HandGestureAction action,string slot,int heldOwner=-1)
    {
        if (action == HandGestureAction.Custom)
        { if (settings.CustomActions?.GetValueOrDefault(slot) is {} label)
            { if (heldOwner>=0 && settings.HeldShortcuts.Contains(slot) && !AppLaunchActionHelper.TryParse(label,out _)) _output.HeldAssignment(heldOwner,label);
              else _output.AssignedAction(label); } }
        else if (action != HandGestureAction.None) _output.Tap(action);
    }
    private void EndOwner(TrackpadSide side, Pad p)
    {
        _output.HeldAssignment((int)side,null);
        p.Owner = null; p.Accelerator?.Reset();
        if (_dragOwner == side) { _output.PrimaryButton(false); _dragOwner = null; }
    }
    public void Tick(double hostTime, bool eligible)
    {
        _coordinated.Tick(hostTime,eligible,_output);
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
    public HandGestureEvidence Evidence(TrackpadSide side) => _pads[(int)side].Evidence with { Epoch=_epoch };
    public bool Process(TrackpadSide side, ReadOnlySpan<HandGestureContact> contacts, double time, double hostTime, bool eligible, bool? reserveEligible = null,bool keyboardPriority=false)
    {
        var p=_pads[(int)side]; bool claimed=p.CycleClaimed;
        bool reserved=ProcessCore(side,contacts,time,hostTime,eligible,reserveEligible,keyboardPriority);
        bool tapPending=(_settings[(int)side].Get(HandGestureTrigger.TwoFingerTap)!=HandGestureAction.None && p.Two.CanComplete)
            || ((_settings[(int)side].Get(HandGestureTrigger.ThreeFingerTap)!=HandGestureAction.None || _settings[(int)side].Get(HandGestureTrigger.ThumbTwoTap)!=HandGestureAction.None) && p.Three.CanComplete)
            || (_settings[(int)side].Get(HandGestureTrigger.FourFingerTap)!=HandGestureAction.None && p.Four.CanComplete)
            || (_settings[(int)side].Get(HandGestureTrigger.FiveFingerTap)!=HandGestureAction.None && p.Five.CanComplete);
        p.CycleClaimed |= p.Owner.HasValue || p.HoldClaimed || p.ForceClaimed || p.CornerPending;
        p.Evidence=new(eligible,reserved,reserved && (claimed || p.CycleClaimed),tapPending,_epoch);
        if (contacts.Length==0) p.CycleClaimed=false;
        return reserved;
    }
    private bool ProcessCore(TrackpadSide side, ReadOnlySpan<HandGestureContact> contacts, double time, double hostTime, bool eligible, bool? reserveEligible,bool keyboardPriority)
    {
        int index = (int)side;
        var p = _pads[index]; var settings = _settings[index];
        int count = contacts.Length;
        if (keyboardPriority || p.KeyboardOwned)
        {
            p.KeyboardOwned=count>0; EndOwner(side,p); Cancel(p); p.Reserved=false;
            _coordinated.Process(side,contacts,hostTime,false,true,_output);
            if (count==0) { p.Blocked=p.ForceBlocked=p.HoldBlocked=false; p.Two.Clear(); p.Three.Clear(); p.Four.Clear(); p.Five.Clear(); }
            return false;
        }
        bool enabled(HandGestureTrigger t) => settings.Enabled(t);
        bool candidate = count switch { 2 => enabled(HandGestureTrigger.TwoFingerMove) || enabled(HandGestureTrigger.TwoFingerTap),
            3 => enabled(HandGestureTrigger.ThreeFingerMove) || enabled(HandGestureTrigger.ThreeFingerTap) || enabled(HandGestureTrigger.ThumbTwoTap),
            4 => enabled(HandGestureTrigger.FourFingerMove) || enabled(HandGestureTrigger.FourFingerTap),
            5 => enabled(HandGestureTrigger.FiveFingerMove) || enabled(HandGestureTrigger.FiveFingerTap), _ => false };
        candidate |= settings.Hold(count) != HandGestureAction.None;
        candidate |= count == 4 && settings.CornerAction(HandCornerChord.OuterCorners) != HandGestureAction.None
            && CoordinatedHandGestureEngine.CornerMask(contacts) == 15;
        if (PerHandGestureSettings.Pinch(count) is {} inward && PerHandGestureSettings.Pinch(count,true) is {} outward)
            candidate |= enabled(inward) || enabled(outward);
        var forceTrigger = PerHandGestureSettings.Force(count);
        bool forcePress = false;
        if (forceTrigger.HasValue && enabled(forceTrigger.Value))
            foreach (var c in contacts) forcePress |= c.HasPressure && double.IsFinite(c.Pressure) && c.Pressure >= 130;
        candidate |= forcePress;
        bool reserved = p.Reserved || ((reserveEligible ?? eligible) && candidate);
        p.Reserved = count > 0 && reserved;
        bool valid = double.IsFinite(time) && double.IsFinite(hostTime) && count <= InputFrame.MaxContacts;
        for (int a = 0; a < count; a++)
        {
            valid &= double.IsFinite(contacts[a].X) && double.IsFinite(contacts[a].Y) && contacts[a].Finger != 6;
            valid &= !contacts[a].HasPressure || (double.IsFinite(contacts[a].Pressure) && contacts[a].Pressure >= 0 && contacts[a].Pressure <= 255);
            for (int b = 0; b < a; b++) valid &= contacts[a].Id != contacts[b].Id;
        }
        p.LastReceipt = hostTime;
        bool independentOwner = false;
        foreach (var pad in _pads) independentOwner |= pad.KeyboardOwned || pad.Owner.HasValue || pad.HoldClaimed || pad.ForceClaimed;
        bool pairReserved = _coordinated.Process(side, valid ? contacts : [], hostTime, eligible && valid, independentOwner, _output);
        if (pairReserved)
        {
            Cancel(p); p.Reserved = count > 0; p.Blocked = count > 0;
            return true;
        }
        if (!eligible || !valid || (_dragOwner.HasValue && _dragOwner != side))
        {
            EndOwner(side, p); Cancel(p);
            if (count == 0) { p.Blocked = p.ForceBlocked = p.HoldBlocked = false; p.Two.Clear(); p.Three.Clear(); p.Four.Clear(); p.Five.Clear(); }
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
        { p.Momentum.Cancel(); CancelTaps(p); p.HoldBlocked = true; }
        if (count == 0)
        {
            bool scrolling = p.Owner.HasValue && settings.Get(p.Owner.Value) == HandGestureAction.Scroll;
            bool owned = p.Owner.HasValue || p.ForceClaimed || p.HoldClaimed || p.CornerPending;
            p.CycleClaimed |= owned;
            EndOwner(side, p);
            if (scrolling && normalEnd) p.Momentum.Start(time, hostTime); else if (owned) p.Momentum.Cancel();
            bool two = p.Two.Process(contacts, time, owned);
            bool three = p.Three.Process(contacts, time, owned);
            bool four = p.Four.Process(contacts, time, owned);
            bool five = p.Five.Process(contacts, time, owned);
            var threeTrigger = p.Thumb.Complete();
            p.CycleClaimed |= two && enabled(HandGestureTrigger.TwoFingerTap) || three && threeTrigger.HasValue && enabled(threeTrigger.Value)
                || four && enabled(HandGestureTrigger.FourFingerTap) || five && enabled(HandGestureTrigger.FiveFingerTap);
            if (two && enabled(HandGestureTrigger.TwoFingerTap) && _dragOwner == null) Emit(settings,settings.Get(HandGestureTrigger.TwoFingerTap),nameof(HandGestureTrigger.TwoFingerTap));
            if (three && threeTrigger.HasValue && enabled(threeTrigger.Value) && _dragOwner == null) Emit(settings,settings.Get(threeTrigger.Value),threeTrigger.Value.ToString());
            if (four && enabled(HandGestureTrigger.FourFingerTap) && _dragOwner == null) Emit(settings,settings.Get(HandGestureTrigger.FourFingerTap),nameof(HandGestureTrigger.FourFingerTap));
            if (five && enabled(HandGestureTrigger.FiveFingerTap) && _dragOwner == null) Emit(settings,settings.Get(HandGestureTrigger.FiveFingerTap),nameof(HandGestureTrigger.FiveFingerTap));
            p.Blocked = false; p.PreviousCount = p.PendingCount = 0; p.TravelX = p.TravelY = 0;
            p.ThreeChordSince = double.NaN; p.SawFour = false;
            p.ForceBlocked = p.ForceClaimed = false; p.Shape.Reset();
            p.HoldCount = 0; p.HoldBlocked = p.HoldClaimed = false; p.Direction = null; p.DirectionTravel = 0;
            p.CornerPending = false;
            return reserved;
        }
        // Match Mac force arbitration: additions before pressing are allowed,
        // but lifting/substituting fingers blocks a later force action this cycle.
        if (p.PreviousCount > 0 && (count < p.PreviousCount || shared != p.PreviousCount)) p.ForceBlocked = true;
        if (!p.Owner.HasValue && !p.HoldClaimed && !p.ForceClaimed && !p.ForceBlocked && forcePress)
        {
            EndOwner(side,p); p.Shape.Reset(); p.Momentum.Cancel();
            CancelTaps(p); p.ForceClaimed = true;
            Emit(settings,settings.Get(forceTrigger!.Value),forceTrigger.Value.ToString()); _output.ForceFeedback(side);
        }
        // Holds share the same all-up ownership and cleanup path as motion/force.
        // A changed cohort restarts an unresolved hold; an activated owner never changes.
        if (p.CornerPending && (count!=4 || shared!=4)) p.HoldBlocked=true;
        if (!p.Owner.HasValue && !p.ForceClaimed && !p.HoldClaimed && !p.HoldBlocked && count is >= 2 and <= 5)
        {
            if (p.HoldCount != count || shared != count)
            { p.HoldCount = count; p.HoldSince = time; contacts.CopyTo(p.HoldOrigin); }
            for (int i = 0; i < count; i++)
            {
                int origin = 0; while (origin < p.HoldCount && p.HoldOrigin[origin].Id != contacts[i].Id) origin++;
                if (origin == p.HoldCount || Distance(contacts[i], p.HoldOrigin[origin]) > 2) p.HoldBlocked = true;
            }
            bool cornerCandidate = count == 4 && CoordinatedHandGestureEngine.CornerMask(contacts) == 15
                && settings.CornerAction(HandCornerChord.OuterCorners) != HandGestureAction.None;
            p.CornerPending |= cornerCandidate;
            if (!p.HoldBlocked && !cornerCandidate && settings.Hold(count) != HandGestureAction.None && time-p.HoldSince >= settings.HoldMilliseconds(count)/1000)
            { p.HoldClaimed = true; CancelTaps(p); p.Shape.Reset(); Emit(settings,settings.Hold(count),"Hold"+count,index); }
            if (!p.HoldBlocked && !p.HoldClaimed && count == 4 && CoordinatedHandGestureEngine.CornerMask(contacts) == 15
                && settings.CornerAction(HandCornerChord.OuterCorners) != HandGestureAction.None
                && time-p.HoldSince >= settings.CornerMilliseconds(HandCornerChord.OuterCorners)/1000)
            { p.HoldClaimed = true; CancelTaps(p); p.Shape.Reset(); Emit(settings,settings.CornerAction(HandCornerChord.OuterCorners),"CornerHold",index); }
        }
        if (p.ForceClaimed || p.HoldClaimed || p.CornerPending)
        {
            contacts.CopyTo(p.Previous); p.PreviousCount = count; p.PreviousTime = time;
            return reserved;
        }
        p.Two.Process(contacts, time, p.Owner.HasValue);
        p.Three.Process(contacts, time, p.Owner.HasValue);
        p.Four.Process(contacts, time, p.Owner.HasValue);
        p.Five.Process(contacts, time, p.Owner.HasValue);
        bool tapStillPossible = (count == 2 && enabled(HandGestureTrigger.TwoFingerTap) && p.Two.CanComplete)
            || (count == 3 && (enabled(HandGestureTrigger.ThreeFingerTap) || enabled(HandGestureTrigger.ThumbTwoTap)) && p.Three.CanComplete)
            || (count == 4 && enabled(HandGestureTrigger.FourFingerTap) && p.Four.CanComplete)
            || (count == 5 && enabled(HandGestureTrigger.FiveFingerTap) && p.Five.CanComplete);
        bool pinchOwned = p.Owner.HasValue && PerHandGestureSettings.IsPinch(p.Owner.Value);
        var shape = p.Shape.Process(contacts,time,pinchOwned);
        bool pinchBegan = false;
        bool dragScrollConflict = settings.ThreeFingerMove == HandGestureAction.PrimaryDrag
            && settings.FourFingerMove == HandGestureAction.Scroll;
        if (!p.Owner.HasValue)
        {
            p.SawFour |= count >= 4;
            // Require an uninterrupted three-finger chord before any button-down.
            // Count/identity changes restart the window; tap recognizers keep their
            // own timing and continue to observe every report below.
            if (count != 3) p.ThreeChordSince = double.NaN;
            else if (!continued || p.PreviousCount != 3 || shared != 3 || double.IsNaN(p.ThreeChordSince))
                p.ThreeChordSince = time;
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
            bool formingTapChord = tapStillPossible && (p.PreviousCount != count || shared != count);
            bool formingScrollChord = count == 4 && enabled(HandGestureTrigger.FourFingerMove)
                && (p.PreviousCount != 4 || shared != 4);
            bool waitingForScroll = count == 3 && dragScrollConflict
                && (p.SawFour || time - p.ThreeChordSince < DragScrollSettleSeconds);
            if (formingTapChord || formingScrollChord || waitingForScroll) p.TravelX = p.TravelY = 0;
            else { p.TravelX += dx; p.TravelY += dy; }
            HandGestureTrigger? trigger = PerHandGestureSettings.Movement(count);
            double threshold = count == 4 ? .2 : .35;
            double translation = Math.Sqrt(p.TravelX*p.TravelX+p.TravelY*p.TravelY);
            var direction = PerHandGestureSettings.Pinch(count,(shape?.Change ?? 0) > 0);
            bool shapeDominant = direction.HasValue && enabled(direction.Value) && shape.HasValue
                && Math.Abs(shape.Value.Change) > translation * (3.0/Math.Max(2,count));
            if (shapeDominant && !tapStillPossible && Math.Abs(shape!.Value.Change) >= .6)
            {
                p.Owner = direction; pinchBegan = true;
                CancelTaps(p); p.Momentum.Cancel();
                var action = settings.Get(direction!.Value);
                if (PerHandGestureSettings.IsDiscrete(action)) Emit(settings,action,direction.Value.ToString());
            }
            else if (!shapeDominant && trigger.HasValue && enabled(trigger.Value) && translation >= (settings.Directional(trigger.Value) != null ? 3 : threshold)
                && !waitingForScroll && (count != 3 || settings.Directional(trigger.Value) != null || AcceptsRow(contacts)))
            {
                p.Owner = trigger;
                dx = p.TravelX; dy = p.TravelY;
                CancelTaps(p);
                if (settings.Directional(trigger.Value) is {} directions)
                {
                    p.Direction = Math.Abs(dx) > Math.Abs(dy) ? (dx > 0 ? HandMovementDirection.Right : HandMovementDirection.Left)
                        : (dy > 0 ? HandMovementDirection.Down : HandMovementDirection.Up);
                    p.DirectionTime = time; p.DirectionTravel = 0;
                    Emit(settings,directions.Get(p.Direction.Value),trigger.Value+"/"+p.Direction.Value);
                    dx = dy = 0;
                }
                else if (settings.Get(trigger.Value) == HandGestureAction.PrimaryDrag)
                {
                    foreach (var pad in _pads) pad.Momentum.Cancel();
                    _output.PrimaryButton(true); _dragOwner = side;
                }
            }
        }
        p.Thumb.Observe(contacts);
        if (p.Owner.HasValue && continued)
        {
            var action = settings.Get(p.Owner.Value);
            if (p.Direction is {} direction && settings.Directional(p.Owner.Value) is {} directions)
            {
                double projection = direction switch { HandMovementDirection.Up => -dy, HandMovementDirection.Down => dy, HandMovementDirection.Left => -dx, _ => dx };
                p.DirectionTravel = Math.Max(0, p.DirectionTravel + projection);
                double interval = directions.Repeat(direction)/1000;
                if (interval > 0 && time-p.DirectionTime >= interval && p.DirectionTravel >= 1)
                { Emit(settings,directions.Get(direction),p.Owner.Value+"/"+direction); p.DirectionTime = time; p.DirectionTravel = 0; }
            }
            else if (PerHandGestureSettings.IsPinch(p.Owner.Value))
            {
                if (!shape.HasValue) { EndOwner(side,p); Cancel(p); }
                else if (action == HandGestureAction.Zoom)
                    _output.Zoom(Math.Clamp((pinchBegan ? shape.Value.InitialRatio : shape.Value.FrameRatio)*settings.ZoomSensitivity,-.25,.25));
            }
            else if (action == HandGestureAction.Scroll)
            {
                // Windows adapter uses 6 scroll points/mm; no installed Apple profile exists here.
                double scrollSign = settings.NaturalScrolling ? 1 : -1;
                double x = dx * 6 * settings.ScrollSensitivity * scrollSign, y = dy * 6 * settings.ScrollSensitivity * scrollSign;
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
        public bool CanComplete => !_blocked && _paired.HasValue;
        private readonly HandGestureContact[] _fingers = new HandGestureContact[5];
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
