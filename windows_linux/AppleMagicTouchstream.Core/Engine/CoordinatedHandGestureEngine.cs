namespace AppleMagicTouchstream;

// Pure recognition. Coordinates follow HandGestureEngine (millimetres, Y down).
// A session retains its first activated owner until BOTH pads lift.
internal sealed class CoordinatedHandGestureEngine
{
    private sealed class Pad
    {
        public readonly HandGestureContact[] Contacts = new HandGestureContact[InputFrame.MaxContacts];
        public readonly HandGestureContact[] Origin = new HandGestureContact[InputFrame.MaxContacts];
        public int Count, OriginalCount;
        public double Receipt, Landed, Lifted;
        public double? ForceSince;
        public bool ForceBlocked,PressureHigh;
    }
    private readonly Pad[] _pads = [new(), new()];
    private static readonly CoordinatedHandChord[] Chords = Enum.GetValues<CoordinatedHandChord>();
    private CoordinatedGestureSettings _settings = new();
    private CoordinatedHandChord? _chord;
    private double _started;
    private double? _firstLift;
    private bool _blocked, _fired, _available, _reserved,_growing;
    public bool Claimed => _fired;
    private HandGestureRecognition? _recognition;
    public HandGestureRecognition? RecentRecognition(double now)=>_recognition is {} value && value.Visible(now) ? value : null;
    public void Cancel(IHandGestureOutput output) { _blocked=true; _chord=null; _recognition=null; output.HeldAssignment(2,null); }
    private void Emit(CoordinatedHandChord chord,bool hold,IHandGestureOutput output,double now,bool force=false)
    {
        var action=_settings.Action(chord,hold,force);
        if(action==HandGestureAction.None) return;
        _recognition=new(force ? HandRecognitionKind.CoordinatedForce : hold ? HandRecognitionKind.CoordinatedHold : HandRecognitionKind.CoordinatedTap,now,Chord:chord);
        if (action==HandGestureAction.Custom)
        { string slot=chord+"/"+(force ? "Force" : hold ? "Hold" : "Tap");
          if (_settings.CustomActions.GetValueOrDefault(slot) is {} label)
          { if (hold && _settings.HeldShortcuts.Contains(slot) && !AppLaunchActionHelper.TryParse(label,out _) && !TextShortcutReference.TryRead(label,out _)) output.HeldAssignment(2,label); else output.AssignedAction(label); } }
        else if (action!=HandGestureAction.None) output.Tap(action);
    }
    public void Configure(CoordinatedGestureSettings settings, bool available)
    { _settings = settings.Clone(); _available = available; Reset(); }
    public void Reset()
    {
        _chord = null; _blocked = true; _fired = _reserved = _growing = false;
        _recognition=null;
        _firstLift = null;
        foreach (var p in _pads) { p.Count = p.OriginalCount = 0; p.Receipt = p.Landed = p.Lifted = 0; p.ForceSince=null; p.ForceBlocked=p.PressureHigh=false; }
    }
    public void Tick(double now, bool eligible,IHandGestureOutput output)
    {
        bool stale=false;
        foreach (var pad in _pads)
            if (pad.Count>0 && now-pad.Receipt>.2) { pad.Count=0; stale=true; }
        if (!eligible || stale)
        { _blocked = true; _chord = null; _recognition=null; output.HeldAssignment(2,null); }
        // A disconnected pad cannot supply all-up. Retire stale samples so its
        // cached contact count cannot indefinitely reserve the healthy pad.
        if (stale && _pads[0].Count==0 && _pads[1].Count==0)
        { _reserved=_fired=false; _firstLift=null; }
    }
    public bool Process(TrackpadSide side, ReadOnlySpan<HandGestureContact> contacts, double now, bool eligible, bool independentOwner, IHandGestureOutput output)
    {
        var pad = _pads[(int)side]; int previous = pad.Count;
        bool stable=previous==contacts.Length && now>pad.Receipt && now-pad.Receipt<=.2;
        foreach(var contact in contacts) { bool found=false; for(int i=0;i<previous;i++) found|=pad.Contacts[i].Id==contact.Id; stable&=found; }
        bool forceValid=true,pressureHigh=false;
        foreach(var contact in contacts) { forceValid &= contact.HasPressure && double.IsFinite(contact.Pressure) && contact.Pressure>=0; pressureHigh |= contact.HasPressure && contact.Pressure>=130; }
        pad.ForceBlocked=contacts.Length>0 && (!forceValid || previous>0 && (pad.ForceBlocked || now<=pad.Receipt || now-pad.Receipt>.2));
        pad.ForceSince=!pad.ForceBlocked && pressureHigh ? stable ? pad.ForceSince ?? now : now : null;
        pad.PressureHigh=pressureHigh;
        pad.Count = contacts.Length; pad.Receipt = now;
        if (previous == 0 && pad.Count > 0) pad.Landed = now;
        if (previous > 0 && pad.Count == 0) pad.Lifted = now;
        contacts.CopyTo(pad.Contacts);
        if (_chord!=null && !_fired)
        {
            if(_growing && pad.Count<previous)_blocked=true;
            if (_firstLift.HasValue && pad.Count>previous) _blocked=true;
            if (pad.Count<pad.OriginalCount) _firstLift ??= now;
        }
        bool reserved = _reserved;
        if (!_available || !eligible || independentOwner || !double.IsFinite(now))
        { _blocked = true; _chord = null; _recognition=null; output.HeldAssignment(2,null); }
        if (_pads[0].Count == 0 && _pads[1].Count == 0)
        {
            output.HeldAssignment(2,null);
            if (_chord is {} chord && !_blocked && !_fired && now-_started is >= .02 and <= .5
                && now-(_firstLift ?? now) <= .15)
                Emit(chord,false,output,now);
            _blocked = _fired = _reserved = _growing = false; _chord = null;
            _firstLift = null;
            return reserved;
        }
        if (_blocked || _fired) return reserved;
        if (_chord == null)
        {
            if (_pads[0].Count == 0 || _pads[1].Count == 0 || now-_pads[0].Receipt > .2 || now-_pads[1].Receipt > .2 || Math.Abs(_pads[0].Landed-_pads[1].Landed) > 1.0) return false;
            foreach (var chord in Chords)
            {
                if (_settings.Action(chord,false) == HandGestureAction.None && _settings.Action(chord,true) == HandGestureAction.None && !ForceReady(chord)) continue;
                if (!Matches(chord, _pads[0], true) || !Matches(chord, _pads[1], false)) continue;
                _chord = chord; _started = now; reserved = _reserved = true;
                foreach (var p in _pads) { p.OriginalCount = p.Count; Array.Copy(p.Contacts,p.Origin,p.Count); }
                break;
            }
        }
        if (_chord is {} current)
        {
            bool expanding=false;
            var target=current switch
            {
                CoordinatedHandChord.TopOuter or CoordinatedHandChord.BottomOuter => (CoordinatedHandChord?)CoordinatedHandChord.OuterCorners,
                CoordinatedHandChord.TopInner or CoordinatedHandChord.BottomInner => CoordinatedHandChord.InnerCorners,
                _=>null
            };
            if(target is {} larger && !_fired && _firstLift==null && _settings.Action(larger,true)!=HandGestureAction.None
                && CanExpand(_pads[0],larger,true) && CanExpand(_pads[1],larger,false))
            {
                expanding=_pads[0].Count>_pads[0].OriginalCount || _pads[1].Count>_pads[1].OriginalCount;
                if(expanding)_growing=true;
                if(_pads[0].Count==2 && _pads[1].Count==2)
                {
                    _chord=current=larger;_started=now;_growing=false;expanding=false;
                    foreach(var p in _pads){p.OriginalCount=p.Count;Array.Copy(p.Contacts,p.Origin,p.Count);}
                }
            }
            foreach (var p in _pads)
            {
                if ((!expanding && p.Count > p.OriginalCount) || (p.Count > 0 && now-p.Receipt > .2)) _blocked = true;
                for (int i=0; i<p.Count; i++)
                {
                    int j=0; while (j<p.OriginalCount && p.Origin[j].Id != p.Contacts[i].Id) j++;
                    if (j==p.OriginalCount) {if(expanding)continue;_blocked=true;break;}
                    if (Math.Pow(p.Origin[j].X-p.Contacts[i].X,2)+Math.Pow(p.Origin[j].Y-p.Contacts[i].Y,2)>4) _blocked = true;
                }
            }
            if (_blocked) { _chord = null; _recognition=null; return true; }
            bool intact = !_growing && !_firstLift.HasValue && _pads[0].Count == _pads[0].OriginalCount && _pads[1].Count == _pads[1].OriginalCount
                && _pads[0].Lifted < _started && _pads[1].Lifted < _started;
            if(intact && ForceReady(current))
            { _fired=true; Emit(current,false,output,now,true); output.ForceFeedback(TrackpadSide.Left); output.ForceFeedback(TrackpadSide.Right); return true; }
            if (intact && _settings.Action(current,true) != HandGestureAction.None && now-_started >= _settings.Milliseconds(current)/1000)
            { _fired = true; Emit(current,true,output,now); }
        }
        return reserved;
    }
    private static bool CanExpand(Pad pad,CoordinatedHandChord target,bool left)
    {
        if(pad.Count<pad.OriginalCount || pad.Count>2)return false;
        int expected=target==CoordinatedHandChord.OuterCorners ? left ? 3:12:left ? 12:3;
        int actual=CornerMask(pad.Contacts.AsSpan(0,pad.Count));if(actual<=0 || (actual&expected)!=actual)return false;
        for(int i=0;i<pad.OriginalCount;i++)
        {
            int j=0;while(j<pad.Count && pad.Contacts[j].Id!=pad.Origin[i].Id)j++;
            if(j==pad.Count || Math.Pow(pad.Contacts[j].X-pad.Origin[i].X,2)+Math.Pow(pad.Contacts[j].Y-pad.Origin[i].Y,2)>4)return false;
        }
        return true;
    }
    private bool ForceReady(CoordinatedHandChord chord)=>chord is CoordinatedHandChord.ThreeFingers or CoordinatedHandChord.FourFingers
        && _settings.Action(chord,false,true)!=HandGestureAction.None && !_pads[0].ForceBlocked && !_pads[1].ForceBlocked && _pads[0].PressureHigh && _pads[1].PressureHigh && _pads[0].ForceSince.HasValue && _pads[1].ForceSince.HasValue
        && Math.Abs(_pads[0].ForceSince!.Value-_pads[1].ForceSince!.Value)<=.15;
    private static bool Matches(CoordinatedHandChord chord, Pad pad, bool left)
    {
        if (chord is CoordinatedHandChord.ThreeFingers or CoordinatedHandChord.FourFingers)
            return pad.Count == (chord == CoordinatedHandChord.ThreeFingers ? 3 : 4);
        int mask = chord switch
        {
            CoordinatedHandChord.OuterCorners => left ? 3 : 12,
            CoordinatedHandChord.InnerCorners => left ? 12 : 3,
            CoordinatedHandChord.TopOuter => left ? 2 : 8,
            CoordinatedHandChord.BottomOuter => left ? 1 : 4,
            CoordinatedHandChord.TopInner => left ? 8 : 2,
            _ => left ? 4 : 1
        };
        return CornerMask(pad.Contacts.AsSpan(0,pad.Count)) == mask;
    }
    internal static int CornerMask(ReadOnlySpan<HandGestureContact> contacts)
    {
        int mask = 0;
        foreach (var c in contacts)
        {
            if (!double.IsFinite(c.X) || !double.IsFinite(c.Y) || c.X < 0 || c.X > 160 || c.Y < 0 || c.Y > 114.9) return -1;
            int x = c.X <= 40 ? 0 : c.X >= 120 ? 1 : -1;
            int y = c.Y <= 28.725 ? 1 : c.Y >= 86.175 ? 0 : -1;
            if (x < 0 || y < 0) return -1;
            int bit = 1 << (x*2+y); if ((mask & bit) != 0) return -1;
            mask |= bit;
        }
        return mask;
    }
}
