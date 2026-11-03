namespace AppleMagicTouchstream;

// Drive Windows' actual frame adapter and recognizer policy with the Mac row,
// anatomy and ownership contracts. Recording output never posts native input.
internal static class NativeGestureParityTests
{
    private sealed class Output : IHandGestureOutput
    {
        internal readonly List<bool> Buttons=[];
        internal readonly List<HandGestureAction> Actions=[];
        internal int Moves,Scrolls,Zooms;
        public void Move(double x,double y)=>Moves++;
        public void Scroll(double x,double y)=>Scrolls++;
        public void PrimaryButton(bool down)=>Buttons.Add(down);
        public void Tap(HandGestureAction action)=>Actions.Add(action);
        public void Zoom(double delta)=>Zooms++;
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
            hand.PointerResponse=HandPointerResponse.Fixed;
        }
        settings.Coordinated.HoldActions=new() { [CoordinatedHandChord.OuterCorners]=HandGestureAction.None };
        return settings;
    }
    private static HandGestureContact[] Row(double depth,double dx=0)
        =>[new(10,30+dx,50,2),new(11,52+dx,50+depth,3),new(12,74+dx,50,4)];
    private static InputFrame NativeRow(int count,double depth,double dx=0,bool hover=false)
    {
        var contacts=Row(depth,dx); var frame=new InputFrame { ContactCount=(byte)(count+(hover ? 1:0)) };
        for(int i=0;i<frame.ContactCount;i++)
            frame.SetContact(i,new(contacts[i].Id,(ushort)Math.Round(contacts[i].X*7612/160),
                (ushort)Math.Round(contacts[i].Y*5065/114.9),(byte)(i<count ? 3:1),0,
                Telemetry:new ContactTelemetry(500,400,30,100,60,4,(byte)contacts[i].Finger,(byte)(i<count ? 4:2))));
        return frame;
    }
    internal static void Run()
    {
        foreach(var side in new[]{TrackpadSide.Left,TrackpadSide.Right})
        {
            foreach(double depth in new[]{9.0,11.0,13.0,18.0})
            {
                var settings=Empty(); (side==TrackpadSide.Left ? settings.Left:settings.Right).ThreeFingerMove=HandGestureAction.PrimaryDrag;
                var output=new Output(); var engine=WindowsHandGestures.CreateRecognizer(output); engine.Configure(settings,false);
                engine.Process(side,[],.9,.9,true);
                engine.Process(side,Row(depth),1,1,true); engine.Process(side,Row(depth,.48),1.01,1.01,true);
                Check(output.Buttons.Count==(depth<14 ? 1:0),"Windows row arch differs from Mac's captured 9–13 mm row regression");
                engine.Process(side,[],1.02,1.02,true);
                Check(output.Buttons.Count==(depth<14 ? 2:0),"arched drag did not release exactly once");
            }
            Landing(side); Shapes(side); ThumbTap(side);
        }
        Console.WriteLine("Native gesture parity passed: arched 3F drag, evidenced third landing/timeout, native thumb gates, shape competition and balanced ownership. No native input.");
    }
    private static void Landing(TrackpadSide side)
    {
        var settings=Empty(); var hand=side==TrackpadSide.Left ? settings.Left:settings.Right;
        hand.TwoFingerMove=HandGestureAction.Pointer; hand.ThreeFingerMove=HandGestureAction.PrimaryDrag;
        hand.TwoFingerTap=HandGestureAction.PrimaryClick; hand.ThreeFingerTap=HandGestureAction.DoubleClick;
        var output=new Output(); var engine=WindowsHandGestures.CreateRecognizer(output); engine.Configure(settings,false);
        void frame(InputFrame input,double time)
        {
            Span<HandGestureContact> contacts=stackalloc HandGestureContact[5];
            int count=HandGestureContactAdapter.ReadContacts(input,7612,5065,contacts,out var fourth,out var third);
            engine.Process(side,contacts[..count],time,time,true,fourthContactPending:fourth,thirdContactPending:third);
        }
        frame(default,.9);
        frame(NativeRow(2,11,hover:true),1); frame(NativeRow(2,11,1.2,hover:true),1.01);
        Check(output.Moves==0 && output.Buttons.Count==0,"two-finger pointer stole a native forming three-finger chord");
        frame(NativeRow(3,11,1.8),1.02);
        Check(output.Moves==1 && output.Buttons.SequenceEqual(new[]{true})
            && engine.RecentRecognition(side,1.02)?.Trigger==HandGestureTrigger.ThreeFingerMove,"third landing failed to select drag");
        frame(NativeRow(2,11,1.4),1.03); frame(NativeRow(1,11,1.6),1.04); frame(default,1.05);
        Check(output.Buttons.SequenceEqual(new[]{true,false}) && output.Actions.Count==0,"staggered drag lift changed owner or left the button down");
        output.Moves=0; output.Buttons.Clear();
        frame(NativeRow(2,11,hover:true),2); frame(NativeRow(2,11,.6,hover:true),2.01);
        frame(NativeRow(2,11,1.4,hover:true),2.081);
        Check(output.Moves==1 && output.Buttons.Count==0,"resting third hover postponed pointer beyond 80 ms"); frame(default,2.09);
        output.Moves=0;
        frame(NativeRow(2,11),3); frame(NativeRow(2,11,1.2),3.01);
        Check(output.Moves==1,"ordinary two-finger movement was delayed without landing evidence");
        frame(NativeRow(3,11,1),3.02);
        Check(output.Buttons.Count==0,"an already activated pointer changed ownership when a finger joined"); frame(default,3.03);
        var raw=NativeRow(2,11,hover:true);
        raw.Contact2=raw.Contact2 with { Telemetry=raw.Contact2.Telemetry!.Value with { FingerType=6 } };
        Span<HandGestureContact> active=stackalloc HandGestureContact[5];
        HandGestureContactAdapter.ReadContacts(raw,7612,5065,active,out _,out var pending);
        Check(!pending,"a hovering palm became third-finger landing evidence");
        raw.Contact2=raw.Contact2 with { Telemetry=null };
        HandGestureContactAdapter.ReadContacts(raw,7612,5065,active,out _,out pending);
        Check(!pending,"legacy slot invented native third-finger evidence");
        raw.Contact0=raw.Contact0 with { Id=1,Telemetry=null };
        HandGestureContactAdapter.ReadContacts(raw,7612,5065,active,out _,out _);
        Check(active[0].Finger==0 && active[1].Finger==3 && active[0].Hand==0,"adapter lost native anatomy or inferred it from an ID/pad");
    }
    private static HandGestureContact[] Shape(int count,double scale=1,double angle=0,int anatomy=1)
        =>Enumerable.Range(0,count).Select(i=>new HandGestureContact((uint)(i+10),
            75+25*scale*Math.Cos(2*Math.PI*i/count+angle),55+25*scale*Math.Sin(2*Math.PI*i/count+angle),
            Finger:anatomy==0 ? 0:anatomy==2 ? 2+i%4:i+1)).ToArray();
    private static void Shapes(TrackpadSide side)
    {
        foreach(int count in Enumerable.Range(2,4))
        foreach(bool spread in new[]{false,true})
        {
            var settings=Empty(); var hand=side==TrackpadSide.Left ? settings.Left:settings.Right;
            hand.Set(PerHandGestureSettings.Pinch(count,spread)!.Value,HandGestureAction.Zoom);
            hand.Set(PerHandGestureSettings.Rotation(count,true)!.Value,HandGestureAction.Back);
            var output=new Output(); var engine=WindowsHandGestures.CreateRecognizer(output); engine.Configure(settings,false);
            engine.Process(side,[],.9,.9,true);
            foreach(int anatomy in new[]{0,2})
            {
                Check(!engine.Process(side,Shape(count,anatomy:anatomy),1,1,true),"thumb-only shape reserved an unclassified/fingertip-only chord");
                engine.Process(side,Shape(count,scale:spread ? 1.1:.9,anatomy:anatomy),1.01,1.01,true);
                Check(output.Zooms==0 && output.Actions.Count==0,"pinch/spread activated without a reported thumb");
                engine.Process(side,Shape(count,angle:.12,anatomy:anatomy),1.02,1.02,true);
                Check(output.Actions.Count==0,"rotation activated without a reported thumb"); engine.Process(side,[],1.03,1.03,true);
            }
            engine.Process(side,Shape(count),2,2,true);
            engine.Process(side,Shape(count,scale:spread ? 1.1:.9),2.01,2.01,true);
            Check(output.Zooms==1,"reported thumb did not permit pinch/spread");
            engine.Process(side,Shape(count,scale:spread ? 1.12:.88,anatomy:0),2.02,2.02,true);
            Check(output.Zooms==2,"label loss cancelled an already activated shape"); engine.Process(side,[],2.03,2.03,true);
            engine.Process(side,Shape(count,anatomy:0),3,3,true);
            engine.Process(side,Shape(count,angle:.12),3.01,3.01,true);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Back}),"late thumb label lost rotation baseline"); engine.Process(side,[],3.02,3.02,true);
        }
        var config=Empty(); var selected=side==TrackpadSide.Left ? config.Left:config.Right;
        selected.FourFingerMove=HandGestureAction.Scroll;
        selected.Set(HandGestureTrigger.FourFingerPinch,HandGestureAction.Zoom);
        var sink=new Output(); var recognizer=WindowsHandGestures.CreateRecognizer(sink); recognizer.Configure(config,false);
        HandGestureContact[] chord=[new(1,25,60,1),new(2,55,45,2),new(3,65,50,3),new(4,75,55,4)];
        recognizer.Process(side,[],.9,.9,true); recognizer.Process(side,chord,1,1,true);
        var fingersOnly=chord.Select(c=>c.Finger==1 ? c:c with { X=c.X+2.5 }).ToArray();
        recognizer.Process(side,fingersOnly,1.01,1.01,true);
        Check(sink.Scrolls==0,"moving fingertips around a stationary thumb stole the chord as scroll");
        recognizer.Process(side,fingersOnly.Select(c=>c with { X=c.X+1 }).ToArray(),1.02,1.02,true);
        Check(sink.Scrolls==1,"full-chord movement failed after thumb joined translation"); recognizer.Process(side,[],1.03,1.03,true);
        config=Empty(); selected=side==TrackpadSide.Left ? config.Left:config.Right;
        selected.TwoFingerTap=HandGestureAction.PrimaryClick;
        selected.Set(HandGestureTrigger.TwoFingerPinch,HandGestureAction.Zoom);
        sink=new(); recognizer=WindowsHandGestures.CreateRecognizer(sink); recognizer.Configure(config,false);
        recognizer.Process(side,[],.9,.9,true); recognizer.Process(side,Shape(2),1,1,true);
        recognizer.Process(side,Shape(2,scale:.984),1.01,1.01,true); recognizer.Process(side,[],1.02,1.02,true);
        Check(sink.Zooms==1 && sink.Actions.Count==0,"a real 0.8 mm thumb pinch lost to an unresolved tap");
    }
    private static void ThumbTap(TrackpadSide side)
    {
        var settings=Empty(); (side==TrackpadSide.Left ? settings.Left:settings.Right).ThumbTwoTap=HandGestureAction.SecondaryClick;
        var output=new Output(); var engine=WindowsHandGestures.CreateRecognizer(output); engine.Configure(settings,false);
        HandGestureContact[] contacts=[new(1,20,20,1),new(2,60,50,2),new(3,72,50,3)];
        engine.Process(side,[],.9,.9,true); engine.Process(side,contacts,1,1,true);
        engine.Process(side,contacts,1.04,1.04,true); engine.Process(side,[],1.05,1.05,true);
        Check(output.Actions.SequenceEqual(new[]{HandGestureAction.SecondaryClick}),"reported Thumb+2 tap remains disabled");
    }
}
