namespace AppleMagicTouchstream;

// Reads the recognizer's own value snapshots. No native input or live runtime.
internal static class GestureRecognitionTests
{
    private sealed class Output:IHandGestureOutput
    {
        public int Count;
        public void Move(double x,double y)=>Count++;
        public void Scroll(double x,double y)=>Count++;
        public void PrimaryButton(bool down)=>Count++;
        public void Tap(HandGestureAction action)=>Count++;
        public void Zoom(double scale)=>Count++;
        public void ForceFeedback(TrackpadSide side)=>Count++;
    }
    private static void Check(bool pass,string message) { if(!pass) throw new InvalidOperationException(message); }
    private static HandGestureSettings Empty()
    {
        var settings=new HandGestureSettings();
        foreach(var hand in new[]{settings.Left,settings.Right})
        { foreach(var trigger in Enum.GetValues<HandGestureTrigger>()) hand.Set(trigger,HandGestureAction.None); hand.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.None }; }
        settings.Coordinated.HoldActions[CoordinatedHandChord.OuterCorners]=HandGestureAction.None;
        return settings;
    }
    private static HandGestureContact[] Contacts(int count,double dx=0,double angle=0,double scale=1)
        =>Enumerable.Range(0,count).Select(i=>new HandGestureContact((uint)i+1,70+25*scale*Math.Cos(i*2*Math.PI/count+angle)+dx,55+25*scale*Math.Sin(i*2*Math.PI/count+angle))).ToArray();
    public static void Run()
    {
        var settings=Empty(); settings.Left.TwoFingerTap=HandGestureAction.PrimaryClick; settings.Right.ThreeFingerTap=HandGestureAction.DoubleClick;
        var output=new Output(); var engine=new HandGestureEngine(output); engine.Configure(settings,false);
        engine.Process(TrackpadSide.Left,[],.9,.9,true); engine.Process(TrackpadSide.Right,[],.9,.9,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,1)==null,"Pending/empty input invented recognition");
        engine.Process(TrackpadSide.Left,Contacts(2),1,1,true); engine.Process(TrackpadSide.Left,Contacts(2),1.03,1.03,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,1.03)==null,"Pending tap was shown before completion");
        engine.Process(TrackpadSide.Left,[],1.05,1.05,true);
        var tap=engine.RecentRecognition(TrackpadSide.Left,1.06);
        Check(tap?.Title=="2-finger tap" && tap.Value.Time==1.05,"Tap recognition was missing or reported the assigned action");
        Check(engine.RecentRecognition(TrackpadSide.Left,3.04)!=null && engine.RecentRecognition(TrackpadSide.Left,3.06)==null,"Recognition did not expire after two seconds");
        Check(!tap!.Value.Visible(1.04) && !new HandGestureRecognition(HandRecognitionKind.Gesture,0).Visible(2),"Recognition accepted past clocks or an expired deadline");
        engine.Process(TrackpadSide.Right,Contacts(3),2,2,true); engine.Process(TrackpadSide.Right,Contacts(3),2.03,2.03,true); engine.Process(TrackpadSide.Right,[],2.05,2.05,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,2.06)?.Title=="2-finger tap" && engine.RecentRecognition(TrackpadSide.Right,2.06)?.Title=="3-finger tap","Feedback crossed pad identities");
        int before=output.Count; engine.RecentRecognition(TrackpadSide.Left,2.07); engine.RecentRecognition(TrackpadSide.Right,2.07);
        Check(output.Count==before,"Reading recognition posted output");
        engine.Cancel(TrackpadSide.Left);
        Check(engine.RecentRecognition(TrackpadSide.Left,2.1)==null && engine.RecentRecognition(TrackpadSide.Right,2.1)!=null,"Cancelling one pad cleared the other pad's feedback");
        engine.Reset(); Check(engine.RecentRecognition(TrackpadSide.Right,2.1)==null,"Reconfiguration/reset retained stale recognition");

        foreach(var side in new[]{TrackpadSide.Left,TrackpadSide.Right})
        foreach(int count in Enumerable.Range(2,4))
        foreach(int shape in Enumerable.Range(0,4))
        {
            settings=Empty(); var hand=side==TrackpadSide.Left ? settings.Left:settings.Right;
            var trigger=shape<2 ? PerHandGestureSettings.Pinch(count,shape==1)!.Value : PerHandGestureSettings.Rotation(count,shape==3)!.Value;
            hand.Set(trigger,HandGestureAction.Back); engine=new(new Output()); engine.Configure(settings,false);
            engine.Process(side,[],.9,.9,true); engine.Process(side,Contacts(count),1,1,true);
            engine.Process(side,Contacts(count,angle:shape==2 ? -.08:shape==3 ? .08:0,scale:shape==0 ? .95:shape==1 ? 1.05:1),1.01,1.01,true);
            Check(engine.RecentRecognition(side,1.02)?.Trigger==trigger,$"Missing {count}-finger shape recognition: {shape}");
            Check(engine.RecentRecognition(side,1.02)?.Title.Contains("Back")==false,"Feedback exposed an action instead of the recognized gesture");
            engine.Process(side,Contacts(count,angle:shape==2 ? -.09:shape==3 ? .09:0,scale:shape==0 ? .94:shape==1 ? 1.06:1),1.03,1.03,true);
            Check(engine.RecentRecognition(side,1.04)?.Time==1.03,"Active shape did not refresh feedback");
            engine.Process(side,[],1.04,1.04,true);
            Check(engine.RecentRecognition(side,1.05)!=null,"Normal lift erased recent recognition");
        }
        settings=Empty(); settings.Left.TwoFingerMove=HandGestureAction.Pointer; engine=new(new Output()); engine.Configure(settings,false);
        engine.Process(TrackpadSide.Left,[],.9,.9,true); engine.Process(TrackpadSide.Left,Contacts(2),1,1,true);
        engine.Process(TrackpadSide.Left,Contacts(2,.5),1.01,1.01,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,1.02)?.Title=="2-finger movement","Continuous movement feedback missing");
        engine.Process(TrackpadSide.Left,Contacts(1,.5),1.03,1.03,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,1.04)?.Title=="2-finger movement","Partial lift reclassified the recognized gesture");
        engine.Tick(1.3,true); Check(engine.RecentRecognition(TrackpadSide.Left,1.3)==null,"Stale cancellation retained feedback");

        settings=Empty(); settings.Left.HoldActions=new() { [2]=HandGestureAction.Copy }; settings.Left.HoldThresholds=new() { [2]=100 };
        engine=new(new Output()); engine.Configure(settings,false); engine.Process(TrackpadSide.Left,[],.9,.9,true);
        engine.Process(TrackpadSide.Left,Contacts(2),1,1,true); engine.Process(TrackpadSide.Left,Contacts(2),1.11,1.11,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,1.12)?.Title=="2-finger hold","Hold feedback missing");
        settings=Empty(); settings.Left.Set(HandGestureTrigger.TwoFingerForce,HandGestureAction.Copy); engine.Configure(settings,false);
        engine.Process(TrackpadSide.Left,[],2,2,true);
        engine.Process(TrackpadSide.Left,Contacts(2).Select(c=>c with { Pressure=130,HasPressure=true }).ToArray(),2.01,2.01,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,2.02)?.Title=="2-finger force click","Force feedback missing");
        var invalid=Contacts(2); invalid[0]=invalid[0] with { X=double.NaN };
        engine.Process(TrackpadSide.Left,invalid,2.03,2.03,true); Check(engine.RecentRecognition(TrackpadSide.Left,2.04)==null,"Invalid input retained feedback");

        settings=Empty(); settings.Left.DirectionalMovement=new() { [HandGestureTrigger.TwoFingerMove]=new() { Enabled=true,Actions=new() { [HandMovementDirection.Right]=HandGestureAction.Copy } } };
        engine.Configure(settings,false); engine.Process(TrackpadSide.Left,[],3,3,true); engine.Process(TrackpadSide.Left,Contacts(2),3.01,3.01,true);
        engine.Process(TrackpadSide.Left,Contacts(2,4),3.02,3.02,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,3.03)?.Title=="2-finger movement →","Directional recognition omitted the latched arrow");
        settings=Empty(); settings.Left.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.OpenConfig };
        settings.Left.CornerHoldThresholds=new() { [HandCornerChord.OuterCorners]=100 }; engine.Configure(settings,false);
        HandGestureContact[] corners=[new(1,10,10),new(2,10,100),new(3,150,10),new(4,150,100)];
        engine.Process(TrackpadSide.Left,[],4,4,true); engine.Process(TrackpadSide.Left,corners,4.01,4.01,true); engine.Process(TrackpadSide.Left,corners,4.12,4.12,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,4.13)?.Title=="Outer Corners Hold","Corner recognition missing");
        Coordinated(); Steno();
        Console.WriteLine("Recognition feedback tests passed: actual gesture identities, both hands, two-second expiry, directions, holds, force, Both, STENO and cancellation. No native input.");
    }
    private static void Coordinated()
    {
        var settings=Empty(); settings.Coordinated.HoldActions[CoordinatedHandChord.ThreeFingers]=HandGestureAction.Copy;
        settings.Coordinated.HoldThresholds[CoordinatedHandChord.ThreeFingers]=100;
        var engine=new HandGestureEngine(new Output()); engine.Configure(settings,false);
        engine.Process(TrackpadSide.Left,[],.9,.9,true); engine.Process(TrackpadSide.Right,[],.9,.9,true);
        engine.Process(TrackpadSide.Left,Contacts(3),1,1,true); engine.Process(TrackpadSide.Right,Contacts(3),1.01,1.01,true);
        engine.Process(TrackpadSide.Left,Contacts(3),1.12,1.12,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,1.13)?.Kind==HandRecognitionKind.CoordinatedHold
            && engine.RecentRecognition(TrackpadSide.Right,1.13)?.Title=="Both · 3 fingers per hand Hold","Both recognition did not reach both pad snapshots");
        engine.Cancel(TrackpadSide.Right); Check(engine.RecentRecognition(TrackpadSide.Left,1.14)==null,"Cancelled Both feedback remained visible");
    }
    private static void Steno()
    {
        var engine=new StenoPointerEngine(new Output()); engine.Configure(2);
        engine.Process(TrackpadSide.Left,[],.9,.9,true); engine.Process(TrackpadSide.Left,Contacts(2),1,1,true);
        engine.Process(TrackpadSide.Left,Contacts(2,2.1),1.01,1.01,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,1.02)?.Title=="2F mouse","STENO movement feedback missing");
        engine.Process(TrackpadSide.Left,[],1.03,1.03,true);
        Check(engine.RecentRecognition(TrackpadSide.Left,1.04)!=null && engine.RecentRecognition(TrackpadSide.Left,3.02)==null,"STENO completion feedback expiry mismatch");
        foreach(int count in Enumerable.Range(1,4))
        {
            engine.Configure(2); engine.Process(TrackpadSide.Left,[],2,2,true);
            engine.Process(TrackpadSide.Left,Contacts(count).Select(c=>c with { Pressure=130,HasPressure=true }).ToArray(),2.01,2.01,true);
            var kind=count switch {1=>HandRecognitionKind.StenoDrag,2=>HandRecognitionKind.StenoPrimaryClick,3=>HandRecognitionKind.StenoSecondaryClick,_=>HandRecognitionKind.StenoScroll};
            Check(engine.RecentRecognition(TrackpadSide.Left,2.02)?.Kind==kind,"STENO force action feedback missing");
            engine.Cancel(); Check(engine.RecentRecognition(TrackpadSide.Left,2.03)==null,"STENO cancellation retained feedback");
        }
    }
}
