using System.Text.Json;

namespace AppleMagicTouchstream;

// Pure geometry, ownership and repeat contracts. No device or native output.
internal static class ShapeGestureParityTests
{
    private sealed class Output : IHandGestureOutput
    {
        internal readonly List<HandGestureAction> Actions=[];
        internal readonly List<string> Labels=[];
        internal readonly List<double> Zooms=[];
        internal int Moves;
        public void Move(double x,double y)=>Moves++;
        public void Scroll(double x,double y)=>Moves++;
        public void PrimaryButton(bool down) { }
        public void Tap(HandGestureAction action)=>Actions.Add(action);
        public void AssignedAction(string label)=>Labels.Add(label);
        public void Zoom(double delta)=>Zooms.Add(delta);
        public void ForceFeedback(TrackpadSide side) { }
    }
    private static void Check(bool pass,string message) { if(!pass) throw new InvalidOperationException(message); }
    private static HandGestureSettings Empty()
    {
        var settings=new HandGestureSettings();
        foreach(var hand in new[]{settings.Left,settings.Right})
        {
            foreach(var trigger in Enum.GetValues<HandGestureTrigger>()) hand.Set(trigger,HandGestureAction.None);
            hand.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.None };
        }
        settings.Coordinated.HoldActions[CoordinatedHandChord.OuterCorners]=HandGestureAction.None;
        return settings;
    }
    private static HandGestureContact[] Chord(int count,double angle=0,double scale=1,double translation=0,bool anatomy=false)
        =>Enumerable.Range(0,count).Select(i=>new HandGestureContact((uint)i+1,
            70+25*scale*Math.Cos(2*Math.PI*i/count+angle)+translation,
            55+25*scale*Math.Sin(2*Math.PI*i/count+angle),Finger:anatomy ? i+1 : 0)).ToArray();
    public static void Run()
    {
        Check((int)HandGestureTrigger.FiveFingerMove==21 && (int)HandGestureTrigger.TwoFingerRotateLeft==22,"Shipped gesture enum identities changed");
        foreach(var side in new[]{TrackpadSide.Left,TrackpadSide.Right})
        foreach(int count in Enumerable.Range(2,4))
        foreach(bool right in new[]{false,true})
        foreach(bool anatomy in new[]{false,true})
        {
            var settings=Empty(); var hand=side==TrackpadSide.Left ? settings.Left : settings.Right;
            var trigger=PerHandGestureSettings.Rotation(count,right)!.Value;
            Check(hand.Get(trigger)==HandGestureAction.None,"Rotation must default to None");
            hand.Set(trigger,HandGestureAction.Back);
            hand.Set(PerHandGestureSettings.Rotation(count,!right)!.Value,HandGestureAction.Forward);
            hand.Set(PerHandGestureSettings.Pinch(count)!.Value,HandGestureAction.Zoom);
            hand.Set(PerHandGestureSettings.Pinch(count,true)!.Value,HandGestureAction.Zoom);
            var output=new Output(); var engine=new HandGestureEngine(output); engine.Configure(settings,false);
            bool frame(HandGestureContact[] c,double t)=>engine.Process(side,c,t,t,true);
            frame([],.9); Check(frame(Chord(count,anatomy:anatomy),1),"Rotation-only family did not reserve");
            double sign=right ? 1 : -1;
            frame(Chord(count,sign*.08,anatomy:anatomy),1.01);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Back}) && output.Zooms.Count==0,$"Rotation {count}/{right}/{anatomy} lost to pinch or wrong direction");
            frame(Chord(count,-sign*.2,anatomy:anatomy),1.02);
            frame(Chord(5,anatomy:anatomy),1.03);
            frame(Chord(5,.1,anatomy:anatomy),1.04);
            frame(Chord(5,.1,anatomy:anatomy).Take(1).ToArray(),1.05);
            frame([],1.06);
            Check(output.Actions.Count==1 && output.Moves==0 && output.Zooms.Count==0,"Rotation changed owner, repeated, or leaked output after membership/reversal");
            frame(Chord(count,anatomy:anatomy),2); frame(Chord(count,sign*.08,anatomy:anatomy),2.01);
            Check(output.Actions.Count==2,"Rotation did not re-arm on all-up"); frame([],2.02);
            frame(Chord(count,anatomy:anatomy),3); frame(Chord(count,scale:1.15,anatomy:anatomy),3.01);
            Check(output.Actions.Count==2 && output.Zooms.Count==1,"Pure scaling became rotation"); frame([],3.02);
        }
        RepeatContracts(); ArbitrationContracts(); RecordedRotations(false); RecordedRotations(true); SettingsContracts();
        Console.WriteLine("Shape gestures passed: 2–5 fingers, both directions/hands, recorded Mac rotations, once/timed/motion, membership and cleanup. No native input.");
    }
    private static void RepeatContracts()
    {
        var repeat=new HandShapeRepeater(); var trigger=HandGestureTrigger.ThreeFingerPinch;
        var timed=new HandShapeRepeat { Mode=HandShapeRepeatMode.Timed,IntervalMilliseconds=50 };
        Check(repeat.Process(trigger,timed,1,0,true),"Timed activation did not emit");
        Check(repeat.Tick(1.049)==null && repeat.Tick(1.051)==trigger,"Timed repeat deadline mismatch");
        Check(!repeat.Process(trigger,timed,1.10,0,false) && repeat.Tick(1.15)==trigger && repeat.Tick(1.151)==null,"Timed repeat burst or stationary failure");
        Check(repeat.Tick(1.5)==null,"Stale timed repeat survived");
        var motion=new HandShapeRepeat { Mode=HandShapeRepeatMode.Motion };
        trigger=HandGestureTrigger.FiveFingerRotateRight;
        Check(repeat.Process(trigger,motion,2,.3,true),"Motion activation did not emit");
        Check(!repeat.Process(trigger,motion,2.01,0,false) && !repeat.Process(trigger,motion,2.02,-.3,false),"Pause/reversal repeated");
        Check(repeat.Process(trigger,motion,2.03,Math.PI/30,false) && repeat.Tick(2.04)==null,"Angular 5 degree step mismatch");
        repeat.Reset(); trigger=HandGestureTrigger.FourFingerPinch;
        repeat.Process(trigger,motion,3,0,true);
        Check(!repeat.Process(trigger,motion,3.01,-.02,false) && repeat.Process(trigger,motion,3.02,-.05,false),"Logarithmic 6 percent scale steps mismatch");
        repeat.Reset(); Check(!repeat.Process(trigger,motion,3.03,-.2,false),"Cancelled repeat resumed");
        // Runtime integration: independent pad leases, still-frame heartbeats,
        // reconfiguration, invalid input and stale delivery stop timer output.
        var settings=Empty();
        foreach(var hand in new[]{settings.Left,settings.Right})
        { hand.Set(HandGestureTrigger.TwoFingerRotateRight,HandGestureAction.Back); hand.ShapeRepeats=new() { [HandGestureTrigger.TwoFingerRotateRight]=timed }; }
        var output=new Output(); var engine=new HandGestureEngine(output); engine.Configure(settings,false);
        foreach(var side in new[]{TrackpadSide.Left,TrackpadSide.Right})
        { engine.Process(side,[],.9,.9,true); engine.Process(side,Chord(2),1,1,true); engine.Process(side,Chord(2,.08),1.01,1.01,true); }
        Check(output.Actions.Count==2,"Both pads failed initial rotation");
        engine.Process(TrackpadSide.Left,[],1.02,1.02,true);
        engine.Process(TrackpadSide.Right,Chord(2,.08),1.04,1.04,true);
        engine.Tick(1.061,true); Check(output.Actions.Count==3,"Lift stopped the other pad's repeat or released pad repeated");
        engine.Tick(1.062,true); Check(output.Actions.Count==3,"Tick caught up in a burst");
        engine.Tick(1.3,true); Check(output.Actions.Count==3,"Stale repeat leaked output");
        engine.Configure(settings,false); engine.Tick(1.4,true); Check(output.Actions.Count==3,"Reconfiguration retained repeat");
        engine.Process(TrackpadSide.Right,[],2,2,true); engine.Process(TrackpadSide.Right,Chord(2),2.01,2.01,true);
        engine.Process(TrackpadSide.Right,Chord(2,.08),2.02,2.02,true);
        engine.Process(TrackpadSide.Right,Chord(2,.08),2.03,2.03,false); engine.Tick(2.08,true);
        Check(output.Actions.Count==4,"Eligibility loss retained repeat");
    }
    private static void RecordedRotations(bool stripAnatomy)
    {
        var settings=Empty(); var hand=settings.Left;
        foreach(int count in Enumerable.Range(2,4))
        {
            hand.Set(PerHandGestureSettings.Movement(count)!.Value,count==2 ? HandGestureAction.Pointer : count==3 ? HandGestureAction.PrimaryDrag : HandGestureAction.Scroll);
            hand.Set(PerHandGestureSettings.Pinch(count)!.Value,HandGestureAction.Zoom); hand.Set(PerHandGestureSettings.Pinch(count,true)!.Value,HandGestureAction.Zoom);
            foreach(bool right in new[]{false,true})
            { var trigger=PerHandGestureSettings.Rotation(count,right)!.Value; hand.Set(trigger,HandGestureAction.Custom); (hand.CustomActions ??= new())[trigger.ToString()]="F"+(1+(int)trigger-(int)HandGestureTrigger.TwoFingerRotateLeft); }
        }
        var assembly=typeof(ShapeGestureParityTests).Assembly;
        using var stream=assembly.GetManifestResourceStream(assembly.GetManifestResourceNames().Single(n=>n.EndsWith("RotationCountsMac.json",StringComparison.Ordinal)))!;
        using var json=JsonDocument.Parse(stream);
        var output=new Output(); var engine=new HandGestureEngine(output); engine.Configure(settings,false);
        engine.Process(TrackpadSide.Left,[],0,0,true);
        int cycle=0; bool wasDown=false,recorded=false; var results=new List<string>();
        foreach(var frame in json.RootElement.GetProperty("frames").EnumerateArray())
        {
            double time=frame.GetProperty("time").GetDouble();
            var contacts=frame.GetProperty("contacts").EnumerateArray().Select(c=>new HandGestureContact(c.GetProperty("id").GetUInt32(),c.GetProperty("x").GetDouble(),c.GetProperty("y").GetDouble(),
                Finger:stripAnatomy ? 0 : c.GetProperty("finger").GetInt32(),Hand:stripAnatomy ? 0 : c.GetProperty("hand").GetInt32())).ToArray();
            int labels=output.Labels.Count,zooms=output.Zooms.Count,moves=output.Moves;
            engine.Process(TrackpadSide.Left,contacts,time,time,true,fourthContactPending:frame.GetProperty("landing").GetBoolean());
            if(!recorded && (output.Labels.Count>labels || output.Zooms.Count>zooms || output.Moves>moves))
            {
                results.Add(cycle+":"+(output.Labels.Count>labels ? output.Labels[^1] : output.Zooms.Count>zooms ? "Zoom" : "Movement")); recorded=true;
            }
            if(wasDown && contacts.Length==0) { cycle++; recorded=false; } wasDown=contacts.Length>0;
        }
        var expected=Enumerable.Range(2,4).SelectMany(count=>Enumerable.Range(0,4).Select(i=>((count-2)*4+i)+":F"+(1+(int)PerHandGestureSettings.Rotation(count,i%2==0)!.Value-(int)HandGestureTrigger.TwoFingerRotateLeft))).ToArray();
        Check(results.Take(16).SequenceEqual(expected),$"Recorded rotation parity (anatomy stripped={stripAnatomy}): "+string.Join(", ",results));
    }
    private static void SettingsContracts()
    {
        var settings=Empty(); var trigger=HandGestureTrigger.FiveFingerRotateLeft;
        settings.Right.Set(trigger,HandGestureAction.Custom); settings.Right.CustomActions=new() { [trigger.ToString()]="Ctrl+R" };
        settings.Right.ShapeRepeats=new() { [trigger]=new() { Mode=HandShapeRepeatMode.Timed,IntervalMilliseconds=65 } };
        settings.Normalize(); var clone=settings.Clone(); clone.Right.ShapeRepeats![trigger]=new() { Mode=HandShapeRepeatMode.Motion };
        Check(settings.Right.ShapeRepeat(trigger).Mode==HandShapeRepeatMode.Timed,"Shape repeat clone shared dictionary");
        Check(settings.For(TrackpadSide.Left,true).ShapeRepeat(trigger)==settings.Right.ShapeRepeat(trigger),"Same-device fallback lost shape repeat behavior");
        var restored=JsonSerializer.Deserialize<HandGestureSettings>(JsonSerializer.Serialize(settings))!; restored.Normalize();
        Check(restored.Right.Get(trigger)==HandGestureAction.Custom && restored.Right.CustomActions![trigger.ToString()]=="Ctrl+R"
            && restored.Right.ShapeRepeat(trigger)==settings.Right.ShapeRepeat(trigger),"Shape bindings/repeats did not round trip");
        Check(new HandShapeRepeat { IntervalMilliseconds=1 }.Normalize().IntervalMilliseconds==20
            && new HandShapeRepeat { IntervalMilliseconds=9000 }.Normalize().IntervalMilliseconds==5000
            && new HandShapeRepeat { IntervalMilliseconds=double.NaN }.Normalize().IntervalMilliseconds==80,"Repeat interval normalization mismatch");
    }
    private static void ArbitrationContracts()
    {
        var settings=Empty(); var hand=settings.Left;
        hand.Set(HandGestureTrigger.TwoFingerPinch,HandGestureAction.Zoom);
        hand.HoldActions=new() { [2]=HandGestureAction.Copy }; hand.HoldThresholds=new() { [2]=100 };
        hand.Set(HandGestureTrigger.TwoFingerForce,HandGestureAction.Paste);
        var output=new Output(); var engine=new HandGestureEngine(output); engine.Configure(settings,false);
        engine.Process(TrackpadSide.Left,[],.9,.9,true); engine.Process(TrackpadSide.Left,Chord(2),1,1,true);
        engine.Process(TrackpadSide.Left,Chord(2,scale:.98),1.11,1.11,true);
        Check(output.Zooms.Count==1 && output.Actions.Count==0,"Pending Hold stole a same-frame shape activation");
        var force=Chord(2,scale:.98).Select(c=>c with { Pressure=130,HasPressure=true }).ToArray();
        engine.Process(TrackpadSide.Left,force,1.12,1.12,true);
        Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Paste}),"Configured Force did not override an active shape");
        engine.Process(TrackpadSide.Left,Chord(2,scale:.95),1.13,1.13,true);
        Check(output.Zooms.Count==1,"Shape resumed after Force takeover"); engine.Process(TrackpadSide.Left,[],1.14,1.14,true);
    }
}
