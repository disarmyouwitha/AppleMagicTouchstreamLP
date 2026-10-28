using System.Text.Json;

namespace AppleMagicTouchstream;

// Offline vectors adapted from the Mac production recognizer tests. No OS input.
internal static class HandGestureTests
{
    private sealed class Output : IHandGestureOutput
    {
        public readonly List<(double X,double Y)> Moves = new(), Scrolls = new();
        public readonly List<bool> Buttons = new();
        public readonly List<HandGestureAction> Taps = new();
        public readonly List<double> Zooms = new();
        public readonly List<TrackpadSide> Feedback = new();
        public void Move(double x, double y) => Moves.Add((x,y));
        public void Scroll(double x, double y) => Scrolls.Add((x,y));
        public void PrimaryButton(bool down) => Buttons.Add(down);
        public void Tap(HandGestureAction action) => Taps.Add(action);
        public void Zoom(double scaleDelta) => Zooms.Add(scaleDelta);
        public void ForceFeedback(TrackpadSide side) => Feedback.Add(side);
    }
    private static HandGestureContact[] Contacts(int n, double offset = 0, uint firstId = 1) => Enumerable.Range(0,n)
        .Select(i => new HandGestureContact(firstId+(uint)i,20+i*16+offset,50)).ToArray();
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static (HandGestureEngine,Output) Engine(HandGestureSettings? settings = null)
    {
        var output = new Output(); var engine = new HandGestureEngine(output); settings ??= new();
        // Recognition vectors use a linear response; acceleration has independent golden vectors.
        settings.Left.PointerResponse = settings.Right.PointerResponse = HandPointerResponse.Fixed;
        engine.Configure(settings,false);
        engine.Process(TrackpadSide.Left,[],.9,.9,true); engine.Process(TrackpadSide.Right,[],.9,.9,true);
        return (engine,output);
    }
    private static HandGestureSettings NoScrollSettings()
    {
        var settings = new HandGestureSettings();
        settings.Left.FourFingerMove = settings.Right.FourFingerMove = HandGestureAction.None;
        return settings;
    }
    private static bool Frame(HandGestureEngine engine, int count, double time, double offset = 0, TrackpadSide side = TrackpadSide.Left, bool enabled = true, bool fourthPending = false)
        => engine.Process(side,Contacts(count,offset),time,time,enabled,fourthContactPending:fourthPending);
    public static bool Run(out string failure)
    {
        try
        {
            // Exact movement thresholds and shared-ID movement with a distant joining finger.
            var movementSettings = new HandGestureSettings(); movementSettings.Left.TwoFingerTap = HandGestureAction.None;
            var (e,o) = Engine(movementSettings);
            Check(Frame(e,2,1),"two-finger candidate was not reserved immediately");
            Frame(e,2,1.01,.2); Check(o.Moves.Count == 0,"movement began below 0.35mm");
            Frame(e,2,1.02,.4); Check(o.Moves.Count == 1 && Math.Abs(o.Moves[0].X-2.4)<1e-8,"activation lost accumulated travel");
            e.Process(TrackpadSide.Left,[new(1,20.5,50),new(2,36.5,50),new(3,150,100)],1.03,1.03,true);
            Check(o.Moves.Count == 2 && Math.Abs(o.Moves[^1].X-.6)<1e-8,"joining contact jumped centroid");
            Frame(e,1,1.04,.6); Check(o.Moves.Count == 3 && o.Buttons.Count == 0,"owner changed after finger-count change");
            Check(Frame(e,0,1.05),"all-up frame lost keyboard reservation");
            Check(!Frame(e,1,1.06),"reservation survived into next touch cycle");
            Check(o.Taps.Count == 0,"continuous pointer movement also clicked");

            (e,o) = Engine(NoScrollSettings()); Frame(e,3,1); Frame(e,3,1.01,.36);
            Check(o.Buttons.SequenceEqual(new[]{true}),"compact three-finger row did not begin drag");
            Frame(e,4,1.02,.5); Frame(e,1,1.03,.6); Frame(e,0,1.04);
            Check(o.Buttons.SequenceEqual(new[]{true,false}),"drag did not latch and release exactly once");
            Check(o.Scrolls.Count == 0 && o.Taps.Count == 0,"drag changed action on added contacts");

            (e,o) = Engine();
            e.Process(TrackpadSide.Left,[new(1,20,20),new(2,40,20),new(3,20,50)],1,1,true);
            e.Process(TrackpadSide.Left,[new(1,21.1,20),new(2,41.1,20),new(3,21.1,50)],1.01,1.01,true);
            Check(o.Buttons.Count == 0,"triangular chord incorrectly activated row drag");
            Frame(e,0,1.02); Check(o.Taps.Count == 0,"rejected moving chord emitted fallback tap");

            // Tap timing: staggered landing/lifting, 20ms overlap, 80ms skew, 1mm slop.
            (e,o) = Engine(); Frame(e,1,1); Frame(e,2,1.02); Frame(e,2,1.06); Frame(e,1,1.08); Frame(e,0,1.10); Frame(e,0,1.11);
            Check(o.Taps.SequenceEqual(new[]{HandGestureAction.PrimaryClick}),"staggered two-finger tap did not click once");
            (e,o) = Engine(); Frame(e,1,1); Frame(e,2,1.02); Frame(e,3,1.04); Frame(e,2,1.08); Frame(e,1,1.10); Frame(e,0,1.12);
            Check(o.Taps.SequenceEqual(new[]{HandGestureAction.DoubleClick}),"staggered three-finger tap did not exclusively double-click");
            foreach (int kind in Enumerable.Range(0,5))
            {
                (e,o) = Engine(); Frame(e,1,1);
                if (kind == 0) { Frame(e,2,1.09); Frame(e,0,1.12); }
                if (kind == 1) { Frame(e,2,1.01); Frame(e,1,1.015); Frame(e,0,1.02); }
                if (kind == 2) { Frame(e,2,1.01); Frame(e,1,1.05); Frame(e,0,1.14); }
                if (kind == 3) { Frame(e,2,1.01); Frame(e,2,1.04,1.1); Frame(e,0,1.06); }
                if (kind == 4) { Frame(e,4,1.01); Frame(e,0,1.06); }
                Check(o.Taps.Count == 0,"invalid tap emitted click: "+kind);
            }

            // Discontinuities, stale input, disabled output and settings changes balance drag.
            foreach (int kind in Enumerable.Range(0,6))
            {
                (e,o) = Engine(NoScrollSettings()); Frame(e,3,1); Frame(e,3,1.01,.4);
                if (kind == 0) e.Tick(1.2,true);
                if (kind == 1) e.Tick(1.02,false);
                if (kind == 2) e.Process(TrackpadSide.Left,Contacts(3,.5,10),1.02,1.02,true);
                if (kind == 3) e.Process(TrackpadSide.Left,[new(1,double.NaN,50)],1.02,1.02,true);
                if (kind == 4) Frame(e,3,1.01,.5);
                if (kind == 5) e.Configure(new(),false);
                Check(o.Buttons.SequenceEqual(new[]{true,false}),"drag cleanup failed: "+kind);
                Check(Frame(e,1,1.22),"cancelled candidate escaped reservation: "+kind);
                Frame(e,0,1.23); Check(o.Taps.Count == 0,"cancelled gesture fell back to tap");
            }
            (e,o) = Engine(); e.Tick(.91,false); Frame(e,0,.92,enabled:false); e.Tick(.93,false);
            Frame(e,2,1); Frame(e,2,1.01,1.1);
            Check(o.Moves.Count == 1,"idle off ticks prevented first gesture after takeover");
            (e,o) = Engine(); Frame(e,2,1,enabled:false); Frame(e,2,1.01,.4,enabled:false); Frame(e,0,1.05,enabled:false);
            Check(o.Moves.Count == 0 && o.Taps.Count == 0,"paused output posted events");

            // Per-hand actions, same-device merge and unknown anatomy.
            var settings = new HandGestureSettings(); settings.Left.TwoFingerMove = HandGestureAction.None; settings.Left.TwoFingerTap = HandGestureAction.None;
            settings.Left.Set(HandGestureTrigger.TwoFingerPinch,HandGestureAction.None); settings.Left.Set(HandGestureTrigger.TwoFingerSpread,HandGestureAction.None);
            (e,o) = Engine(settings); Check(!Frame(e,2,1),"None bindings reserved keyboard input");
            Check(Frame(e,2,1,side:TrackpadSide.Right),"other pad did not keep independent bindings");
            settings.Right.TwoFingerMove = HandGestureAction.Scroll;
            Check(settings.For(TrackpadSide.Left,true).TwoFingerMove == HandGestureAction.Scroll,"same-device right fallback missing");
            settings.Left.TwoFingerMove = HandGestureAction.Pointer;
            Check(settings.For(TrackpadSide.Left,true).TwoFingerMove == HandGestureAction.Pointer,"same-device active-left priority missing");
            settings.Left.TwoFingerTap = HandGestureAction.SecondaryClick;
            (e,o) = Engine(settings); Frame(e,2,1); Frame(e,0,1.04);
            Check(o.Taps.SequenceEqual(new[]{HandGestureAction.SecondaryClick}),"tap action was coupled to trigger default");
            (e,o) = Engine();
            var thumb = new HandGestureContact[]{new(1,20,20,1,7),new(2,60,50,2,7),new(3,72,50,3,7)};
            e.Process(TrackpadSide.Left,thumb,1,1,true); e.Process(TrackpadSide.Left,thumb,1.04,1.04,true); Frame(e,0,1.05);
            Check(o.Taps.SequenceEqual(new[]{HandGestureAction.SecondaryClick}),"positively classified spread thumb tap missing");
            (e,o) = Engine();
            var unknown = thumb.Select(c=>c with { Finger=0,Hand=0 }).ToArray();
            e.Process(TrackpadSide.Left,unknown,1,1,true); Frame(e,0,1.05);
            Check(o.Taps.SequenceEqual(new[]{HandGestureAction.DoubleClick}),"unknown Windows identities were guessed to be thumb");

            // Four-finger 0.2mm activation and analytic momentum; retouch brakes without click.
            (e,o) = Engine(); Frame(e,4,1); Frame(e,4,1.01,.21); Frame(e,4,1.02,.6); Frame(e,4,1.03,1.1); Frame(e,0,1.04);
            Check(o.Scrolls.Count == 3 && o.Moves.Count == 0,"four-finger scroll threshold/action differs");
            int before = o.Scrolls.Count; e.Tick(1.05,true); Check(o.Scrolls.Count > before,"release did not start momentum");
            Frame(e,2,1.06); Frame(e,0,1.10); before = o.Scrolls.Count; e.Tick(1.11,true);
            Check(o.Scrolls.Count == before && o.Taps.Count == 0,"braking coast scrolled or clicked");
            var coast = new HandScrollMomentum(); coast.Observe(10,0,1); coast.Observe(10,0,1.01); Check(coast.Start(1.02,2),"momentum did not arm");
            double velocity = 20/(.01+1.0/90+.01);
            var step = coast.Advance(2.01); double expected = velocity*.325*(1-Math.Exp(-.01/.325));
            Check(step.HasValue && Math.Abs(step.Value.X-expected)<1e-7,"momentum numerical model differs from Mac");
            coast.Advance(2.2); Check(!coast.IsCoasting,"stalled momentum did not cancel");

            var serialized = JsonSerializer.Serialize(new UserSettings { HandGesturesV1 = settings });
            var restored = JsonSerializer.Deserialize<UserSettings>(serialized)!;
            Check(restored.Clone().HandGesturesV1.Left.TwoFingerTap == HandGestureAction.SecondaryClick,"gesture settings lost on save/clone");
            restored.HandGesturesV1.Left.TwoFingerTap = HandGestureAction.Pointer; restored.HandGesturesV1.Left.PointerSensitivity = double.NaN; restored.HandGesturesV1.Normalize();
            Check(restored.HandGesturesV1.Left.TwoFingerTap == HandGestureAction.None && restored.HandGesturesV1.Left.PointerSensitivity == 1,"invalid settings were not normalized");
            RunKeyboardArbitration();
            RunAccelerationAndScrollDirection();
            RunPanelPreferences();
            RunFastPointerContinuity();
            RunCapturedTapLanding();
            RunCapturedMovingTaps();
            RunDragScrollArbitration();
            MacGesturePortTests.Run();
            MacGoldParityTests.Run();
            failure = ""; return true;
        }
        catch (Exception ex) { failure = ex.Message; return false; }
    }
    private static void RunDragScrollArbitration()
    {
        // Exercise the actual Windows frame adapter without hooks or live input.
        var raw=new InputFrame { ContactCount=4 };
        for (int i=0;i<3;i++) raw.SetContact(i,new((uint)i+1,2000,2000,3));
        raw.SetContact(3,new(4,3000,2000,1));
        Span<HandGestureContact> active=stackalloc HandGestureContact[InputFrame.MaxContacts];
        Check(WindowsHandGestures.ReadContacts(in raw,7612,5065,active,out bool pending)==3 && pending,
            "Windows discarded confident fourth pre-contact evidence");
        raw.SetContact(3,new(4,3000,2000,0));
        Check(WindowsHandGestures.ReadContacts(in raw,7612,5065,active,out pending)==3 && !pending,
            "unconfident slot became fourth-contact evidence");
        raw.SetContact(3,new(4,9000,2000,1));
        Check(WindowsHandGestures.ReadContacts(in raw,7612,5065,active,out pending)==3 && !pending,
            "out-of-range slot deferred drag");
        raw.SetContact(3,new(4,3000,2000,3));
        Check(WindowsHandGestures.ReadContacts(in raw,7612,5065,active,out pending)==4 && !pending,
            "fourth touching contact remained classified as pending");
        // A moving three-finger landing must not press the button before finger four.
        foreach (var side in new[] { TrackpadSide.Left, TrackpadSide.Right })
        {
            var (e,o) = Engine();
            Frame(e,3,1,side:side); Frame(e,3,1.02,.6,side,fourthPending:true); Frame(e,3,1.06,1.2,side,fourthPending:true);
            Check(o.Buttons.Count == 0 && o.Moves.Count == 0,"forming scroll began a drag during settling");
            Frame(e,4,1.07,1.8,side);
            Check(o.Scrolls.Count == 0,"fourth-finger landing was counted as scroll travel");
            Frame(e,4,1.10,2.1,side); Frame(e,3,1.12,2.3,side); Frame(e,0,1.14,side:side);
            Check(o.Scrolls.Count > 0 && o.Buttons.Count == 0 && o.Taps.Count == 0,"scroll landing/lifting produced drag or tap");

            // Four fingers that never acquired scroll must not become a drag on lift.
            (e,o) = Engine(); Frame(e,4,1,side:side); Frame(e,3,1.01,side:side);
            for (int i=1; i<=20; i++) Frame(e,3,1.01+i*.01,i*.1,side);
            Frame(e,0,1.23,side:side);
            Check(o.Buttons.Count == 0 && o.Taps.Count == 0,"unlatched scroll fell back to drag/tap");

            // Mac does not delay a deliberate three-finger drag without evidence
            // of a fourth landing. Once activated, even a fourth finger cannot steal it.
            (e,o) = Engine(); Frame(e,3,1,side:side); Frame(e,3,1.01,.4,side);
            Check(o.Buttons.SequenceEqual(new[]{true}) && Math.Abs(o.Moves.Single().X-2.4)<1e-8,"unevidenced fourth finger delayed a deliberate drag");
            Frame(e,4,1.02,.5,side); Frame(e,0,1.04,side:side);
            Check(o.Buttons.SequenceEqual(new[]{true,false}) && o.Scrolls.Count == 0,"drag changed owner or failed release");

            // A stationary three-finger tap is unchanged.
            (e,o) = Engine(); Frame(e,3,1,side:side); Frame(e,3,1.03,.2,side); Frame(e,0,1.06,side:side);
            Check(o.Taps.SequenceEqual(new[]{HandGestureAction.DoubleClick}) && o.Buttons.Count == 0,"three-finger tap was delayed or became drag");

            // Resting pre-contact cannot suppress a real drag beyond Mac's 80ms.
            (e,o) = Engine(); Frame(e,3,1,side:side); Frame(e,3,1.04,.4,side,fourthPending:true);
            Check(o.Buttons.Count == 0,"fourth pre-contact failed to defer drag");
            Frame(e,3,1.081,.4,side,fourthPending:true);
            Check(o.Buttons.SequenceEqual(new[]{true}),"hover suppressed drag beyond the landing window");
            Frame(e,0,1.10,side:side);
            Check(o.Buttons.SequenceEqual(new[]{true,false}),"bounded pre-contact drag left button held");

            (e,o) = Engine(NoScrollSettings()); Frame(e,3,1,side:side); Frame(e,3,1.01,.4,side,fourthPending:true);
            Check(o.Buttons.SequenceEqual(new[]{true}),"disabled fourth-finger movement still deferred drag");
            Frame(e,0,1.03,side:side);

            // Tick cannot turn an abandoned pending chord into a delayed button-down.
            (e,o) = Engine(); Frame(e,3,1,side:side); Frame(e,3,1.05,.8,side,fourthPending:true);
            e.Tick(1.3,true); Frame(e,3,1.31,1.2,side); Frame(e,0,1.33,side:side);
            Check(o.Buttons.Count == 0 && o.Taps.Count == 0,"stale pending drag activated or fell back to a tap");
        }
    }
    private static void RunCapturedMovingTaps()
    {
        var assembly = typeof(HandGestureTests).Assembly;
        string name = assembly.GetManifestResourceNames().Single(n=>n.EndsWith(".TwoFingerTapMovingMouse.json",StringComparison.Ordinal));
        using var input = assembly.GetManifestResourceStream(name)!;
        using var fixture = JsonDocument.Parse(input);
        foreach (var side in new[] { TrackpadSide.Left, TrackpadSide.Right })
        foreach (var action in new[] { HandGestureAction.Pointer, HandGestureAction.PrimaryDrag })
        {
            var settings = new HandGestureSettings();
            (side == TrackpadSide.Left ? settings.Left : settings.Right).TwoFingerMove = action;
            var (engine,output) = Engine(settings);
            // Fixture time starts at zero, so clear the configuration barrier on
            // an earlier empty frame, rather than using Engine's usual .9 clock.
            engine.Process(side,[],-.01,-.01,true);
            int start=-1,moves=0,taps=0,buttons=0;
            foreach (var frame in fixture.RootElement.GetProperty("frames").EnumerateArray())
            {
                int index=frame.GetProperty("index").GetInt32(); double time=frame.GetProperty("time").GetDouble();
                var contacts=frame.GetProperty("points").EnumerateArray().Select(p=>new HandGestureContact(p[0].GetUInt32(),p[1].GetDouble(),p[2].GetDouble())).ToArray();
                if (contacts.Length>0 && start<0) { start=index; moves=output.Moves.Count; taps=output.Taps.Count; buttons=output.Buttons.Count; }
                engine.Process(side,contacts,time,time,true); engine.Tick(time,true);
                if (contacts.Length!=0 || start<0) continue;
                if (start is 255 or 489)
                    Check(output.Moves.Count==moves && output.Taps.Count==taps+1 && output.Buttons.Count==buttons,
                        $"recorded short tap {start} became pointer movement/drag instead of a click");
                start=-1;
            }
            Check(output.Taps.Count==15 && output.Moves.Count==860 && output.Zooms.Count==4,
                $"moving/tapping capture changed: {output.Taps.Count} taps, {output.Moves.Count} moves, {output.Zooms.Count} zoom packets");
            if (action==HandGestureAction.PrimaryDrag)
                Check(output.Buttons.Count>0 && output.Buttons.Where((_,i)=>i%2==0).All(b=>b)
                    && output.Buttons.Where((_,i)=>i%2==1).All(b=>!b) && output.Buttons.Count%2==0,"recorded drag ownership was unbalanced");
        }
        // Assigned tap uses its existing 1mm slop; movement starts immediately
        // on invalidation, with no fixed waiting timer and no release-time click.
        var (e,o)=Engine(); Frame(e,2,1); Frame(e,2,1.01,.8);
        Check(o.Moves.Count==0,"valid tap slop acquired pointer movement");
        Frame(e,2,1.02,1.1); Check(o.Moves.Count==1,"movement did not take over outside tap slop");
        Frame(e,1,1.03,1.2); Frame(e,0,1.04);
        Check(o.Taps.Count==0 && o.Moves.Count==2,"movement owner lost continuation or emitted a tap");
    }
    private static void RunCapturedTapLanding()
    {
        var assembly = typeof(HandGestureTests).Assembly;
        string name = assembly.GetManifestResourceNames().Single(n=>n.EndsWith(".TwoFingerTapLanding.json",StringComparison.Ordinal));
        using var input = assembly.GetManifestResourceStream(name)!;
        using var fixture = JsonDocument.Parse(input);
        // Assigned taps retain their 1mm allowance before movement can acquire.
        // The same fourteen motion cycles survive, with intentionally later
        // activation where their early travel was still a valid tap.
        var expectedMotion = new Dictionary<int,int> { [293]=298,[485]=501,[591]=597,[613]=618,[641]=647,[673]=677,[711]=718,
            [747]=755,[783]=793,[827]=835,[863]=876,[902]=911,[931]=941,[973]=976 };
        foreach (var action in new[] { HandGestureAction.Pointer,HandGestureAction.PrimaryDrag })
        {
            var settings = new HandGestureSettings(); settings.Right.TwoFingerMove = action;
            var output = new Output(); var engine = new HandGestureEngine(output); engine.Configure(settings,false);
            engine.Process(TrackpadSide.Right,[],-.01,-.01,true);
            bool active = false; int start = 0, moves = 0, taps = 0, buttons = 0, firstMove = -1, motionCycles = 0;
            foreach (var frame in fixture.RootElement.GetProperty("frames").EnumerateArray())
            {
                int index = frame.GetProperty("index").GetInt32(); double time = frame.GetProperty("time").GetDouble();
                var contacts = frame.GetProperty("points").EnumerateArray().Select(p=>new HandGestureContact(p[0].GetUInt32(),p[1].GetDouble(),p[2].GetDouble())).ToArray();
                if (contacts.Length > 0 && !active) { active = true; start = index; moves = output.Moves.Count; taps = output.Taps.Count; buttons = output.Buttons.Count; firstMove = -1; }
                int before = output.Moves.Count;
                engine.Process(TrackpadSide.Right,contacts,time,time,true); engine.Tick(time,true);
                if (output.Moves.Count > before && firstMove < 0) firstMove = index;
                if (contacts.Length != 0 || !active) continue;
                if (start is 476 or 533)
                    Check(output.Moves.Count == moves && output.Taps.Count == taps+1 && output.Buttons.Count == buttons,
                        $"captured tap {start} still became movement/drag instead of one click");
                if (expectedMotion.TryGetValue(start,out int expected))
                {
                    Check(firstMove == expected,$"captured movement {start} activation changed from frame {expected} to {firstMove}"); motionCycles++;
                }
                active = false;
            }
            Check(motionCycles == 14 && output.Taps.Count == 11 && output.Moves.Count == 546,$"full capture replay classification changed unexpectedly: motion cycles {motionCycles}, taps {output.Taps.Count}, moves {output.Moves.Count}, zooms {output.Zooms.Count}");
            if (action == HandGestureAction.PrimaryDrag) Check(output.Buttons.Count(b=>b) == 14 && output.Buttons.Count(b=>!b) == 14,"captured drag releases are unbalanced");
        }
        // None removes tap-specific arbitration; an assigned movement still works.
        var noTapSettings = new HandGestureSettings(); noTapSettings.Left.TwoFingerTap = HandGestureAction.None;
        var (noneEngine,noneOutput) = Engine(noTapSettings); Frame(noneEngine,1,1); Frame(noneEngine,2,1.01,.8);
        Check(noneOutput.Moves.Count == 1,"None tap binding delayed or suppressed two-finger movement");
    }
    private static void RunFastPointerContinuity()
    {
        foreach (int count in new[] { 2,3 })
        {
            var output = new Output(); var engine = new HandGestureEngine(output);
            var settings=NoScrollSettings(); settings.Left.TwoFingerTap=HandGestureAction.None;
            engine.Configure(settings,false); Frame(engine,0,.9);
            Frame(engine,count,1); Frame(engine,count,1.01,.4);
            Check(output.Moves.Count == 1,"slow motion did not acquire owner");
            Frame(engine,count,1.02,5.4);
            Check(output.Moves.Count == 2 && output.Moves[^1].X > 150,"fast accelerated motion was dropped at old 150px boundary");
            Frame(engine,count,1.03,10.4);
            Frame(engine,count,1.04,10.5);
            Check(output.Moves.Count == 4 && output.Moves[^1].X > 0,"fast motion lost latch before subsequent slow motion");
            if (count == 3) Check(output.Buttons.SequenceEqual(new[]{true}),"fast drag released its button before all-up");
            Frame(engine,0,1.05);
            Check(output.Taps.Count == 0,"fast continuous gesture emitted a tap");
            if (count == 3) Check(output.Buttons.SequenceEqual(new[]{true,false}),"fast drag did not release at all-up");
        }
        var bounded = PointerMotionLimits.Constrain(8192,-4096);
        Check(bounded == (4096,-2048),"large output bound did not retain direction");
        var huge = PointerMotionLimits.Constrain(double.MaxValue,-double.MaxValue);
        Check(double.IsFinite(huge.X) && Math.Abs(huge.X) <= 4096 && Math.Abs(huge.Y) <= 4096,"pathological output was not bounded");
    }
    private static void RunPanelPreferences()
    {
        var settings=new UserSettings();
        HandGesturePanel? panel=null; panel=new HandGesturePanel(settings,()=>panel?.Refresh(settings));
        Check(panel.ColumnDefinitions.Count==5,"Gestures is not a three-column workspace with two dividers");
        System.Windows.Controls.Slider slider(int kind)=>Controls<System.Windows.Controls.Slider>(panel).First(s=>Equals(s.Tag,kind));
        panel.MirrorEdits=true;
        var pointer=slider(0); pointer.Value=1.35; pointer.Value=1.4;
        Check(ReferenceEquals(pointer,slider(0)),"refresh replaced the active sensitivity slider");
        Check(settings.HandGesturesV1.Left.PointerSensitivity==1.4 && settings.HandGesturesV1.Right.PointerSensitivity==1.4,"Mirror Edit did not update both hands");
        panel.MirrorEdits=false; slider(0).Value=.8;
        Check(settings.HandGesturesV1.Left.PointerSensitivity==.8 && settings.HandGesturesV1.Right.PointerSensitivity==1.4,"Left edit changed Right");
        panel.SelectPage("4-main"); panel.SelectSlot(nameof(HandGestureTrigger.FourFingerMove)); panel.MirrorEdits=true;
        var natural=Controls<System.Windows.Controls.CheckBox>(panel).Single(c=>Equals(c.Content,"Natural scrolling"));
        natural.IsChecked=false; natural.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        Check(!settings.HandGesturesV1.Left.NaturalScrolling && !settings.HandGesturesV1.Right.NaturalScrolling,"Natural scrolling edit failed");
        slider(1).Value=.65;
        Check(settings.HandGesturesV1.Left.ScrollSensitivity==.65 && settings.HandGesturesV1.Right.ScrollSensitivity==.65,"scroll gain did not mirror");
        panel.SelectPage("2-shape"); slider(2).Value=1.2;
        Check(settings.HandGesturesV1.Left.ZoomSensitivity==1.2 && settings.HandGesturesV1.Right.ZoomSensitivity==1.2,"zoom gain did not mirror");
        panel.SelectPage("thumb");
        var combo=Controls<System.Windows.Controls.ComboBox>(panel).Single(c=>Equals(c.Tag,HandGestureTrigger.ThumbTwoTap)); combo.SelectedIndex=0;
        Check(settings.HandGesturesV1.Left.ThumbTwoTap==HandGestureAction.None && settings.HandGesturesV1.Right.ThumbTwoTap==HandGestureAction.None,"thumb compatibility assignment was lost");
        panel.EditingScope=HandGestureScope.Both; panel.SelectPage("both-InnerCorners");
        settings.HandGesturesV1.Coordinated.HoldActions[CoordinatedHandChord.InnerCorners]=HandGestureAction.Custom;
        settings.HandGesturesV1.Coordinated.CustomActions["InnerCorners/Hold"]="Hyper"; panel.Refresh(settings);
        var held=Controls<System.Windows.Controls.CheckBox>(panel).Single(c=>Equals(c.Tag,"HeldShortcut"));
        Check(held.IsEnabled,"held shortcut control is unavailable on Hold");
        held.IsChecked=true; held.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        Check(settings.HandGesturesV1.Coordinated.HeldShortcuts.Contains("InnerCorners/Hold") && settings.HandGesturesV1.Left.HeldShortcuts.Count==0,"Both Hold changed independent settings");
        settings.HandGesturesV1.Left.PointerResponse=HandPointerResponse.Fixed; WindowsInputPolicy.NormalizeLegacyModes(settings);
        Check(settings.HandGesturesV1.Left.PointerResponse==HandPointerResponse.AppleReference,"Windows Apple response policy was bypassed");
    }
    internal static IEnumerable<T> Controls<T>(object root) where T : System.Windows.FrameworkElement
    {
        if (root is T element) yield return element;
        IEnumerable<object> children = root switch
        {
            System.Windows.Controls.Panel p => p.Children.Cast<object>(),
            System.Windows.Controls.ContentControl c when c.Content!=null => new[] { c.Content },
            System.Windows.Controls.Decorator d when d.Child!=null => new object[] { d.Child },
            _ => []
        };
        foreach (var child in children) foreach (var found in Controls<T>(child)) yield return found;
    }
    private static void RunAccelerationAndScrollDirection()
    {
        // The same cross-language golden vectors used by the Mac production tests.
        var assembly = typeof(HandGestureTests).Assembly;
        string resource = assembly.GetManifestResourceNames().Single(n => n.EndsWith(".ApplePointerAccelerationVectors.json",StringComparison.Ordinal));
        using var stream = assembly.GetManifestResourceStream(resource)!;
        using var vectors = JsonDocument.Parse(stream);
        var model = new ApplePointerAccelerator(ApplePointerProfile.Reference);
        foreach (var vector in vectors.RootElement.GetProperty("vectors").EnumerateArray())
        {
            var delta = model.Counts(vector.GetProperty("t").GetDouble(),vector.GetProperty("dx").GetDouble(),vector.GetProperty("dy").GetDouble());
            Check(delta.HasValue && Math.Abs(delta.Value.X-vector.GetProperty("expectedX").GetDouble()) < 1e-9
                && Math.Abs(delta.Value.Y-vector.GetProperty("expectedY").GetDouble()) < 1e-9,"Apple reference differs from Mac numerical vectors");
        }
        var analytic = new ApplePointerAccelerator(new() { Resolution = 67, Acceleration = 0,
            Curves = [new() { Index = 0, Linear = 1, Parabolic = .5, TangentLinear = 2, TangentRoot = 4 }] });
        foreach (var (x,y) in new[] { (1.0,1.25),(2.0,3.0),(3.0,5.0),(4.0,7.0),(5.0,Math.Sqrt(77)) })
            Check(Math.Abs(analytic.AcceleratedVelocity(x)-y*96/67) < 1e-10,"Apple polynomial/line/root branch differs");
        Check(model.Counts(1.099,0,0) == null,"non-increasing acceleration timestamp was accepted");
        string snapshot = JsonSerializer.Serialize(new { schema = "gesturepad.pointer-settings.v1", devices = new[] { ApplePointerProfile.Reference } });
        var profile = ApplePointerProfile.ReadSnapshot(snapshot).Single();
        Check(profile.FixedMultiplier == ApplePointerProfile.Reference.FixedMultiplier,"Mac profile import changed multiplier");
        bool rejected = false;
        try { _ = new ApplePointerAccelerator(profile with { Resolution = 0 }); } catch (ArgumentException) { rejected = true; }
        Check(rejected,"invalid imported resolution was accepted");
        var output = new Output(); var engine = new HandGestureEngine(output); var settings = new HandGestureSettings();
        settings.Left.TwoFingerTap=HandGestureAction.None;
        engine.Configure(settings,false); Frame(engine,0,.9); Frame(engine,2,1); Frame(engine,2,1.01,.4);
        var expected = new ApplePointerAccelerator(ApplePointerProfile.Reference).Millimetres(1.01,.4,0,1);
        Check(output.Moves.Count == 1 && expected.HasValue && Math.Abs(output.Moves[0].X-expected.Value.X)<1e-8,"default pointer path did not apply Apple acceleration");
        settings.Left.FourFingerMove = HandGestureAction.None; engine.Configure(settings,false);
        Frame(engine,0,1.02); Frame(engine,3,1.03); Frame(engine,3,1.04,.4);
        Check(output.Buttons.SequenceEqual(new[]{true}) && Math.Abs(output.Moves[^1].X-expected!.Value.X)<1e-8,"drag did not use the same Apple response");
        var reverseSettings = new HandGestureSettings(); reverseSettings.Left.NaturalScrolling = false;
        var (natural,a) = Engine(); var (reverse,b) = Engine(reverseSettings);
        for (int i = 0; i < 4; i++)
        {
            var contacts = Contacts(4,i*.3).Select(c=>c with { Y = c.Y+i*.2 }).ToArray();
            natural.Process(TrackpadSide.Left,contacts,2+i*.01,2+i*.01,true);
            reverse.Process(TrackpadSide.Left,contacts,2+i*.01,2+i*.01,true);
        }
        Frame(natural,0,2.04); Frame(reverse,0,2.04); natural.Tick(2.05,true); reverse.Tick(2.05,true);
        Check(a.Scrolls.Count == b.Scrolls.Count && a.Scrolls.Count > 3,"scroll direction test did not include momentum");
        for (int i = 0; i < a.Scrolls.Count; i++) Check(Math.Abs(a.Scrolls[i].X+b.Scrolls[i].X)<1e-8 && Math.Abs(a.Scrolls[i].Y+b.Scrolls[i].Y)<1e-8,"natural scrolling did not reverse both axes/momentum");
        var saved = new UserSettings { HandGesturesV1 = reverseSettings };
        saved.HandGesturesV1.Left.PointerResponse = HandPointerResponse.ImportedApple;
        saved.HandGesturesV1.Left.ImportedPointerProfile = profile;
        var restored = JsonSerializer.Deserialize<UserSettings>(JsonSerializer.Serialize(saved))!.Clone();
        Check(!restored.HandGesturesV1.Left.NaturalScrolling && restored.HandGesturesV1.Left.ImportedPointerProfile!.Resolution == profile.Resolution,"scroll/profile preferences lost on round-trip");
        foreach (var action in new[] { HandGestureAction.None,HandGestureAction.PrimaryClick,HandGestureAction.DoubleClick,HandGestureAction.SecondaryClick })
            Check(PerHandGestureSettings.Allows(HandGestureTrigger.ThumbTwoTap,action),"thumb tap menu is missing a click action");
    }
    private static void RunKeyboardArbitration()
    {
        var keymap = KeymapStore.LoadBundledDefault();
        var core = TouchProcessorFactory.CreateDefault(keymap); core.UseHandGestureRecognition();
        core.SetKeyboardModeEnabled(true);
        const ushort maxX = 7612, maxY = 5065;
        var preset = TrackpadLayoutPreset.SixByThree;
        var layout = LayoutBuilder.BuildLayout(preset,160,114.9,18,17,ColumnLayoutDefaults.DefaultSettings(preset.Columns),true);
        var rect = layout.Rects[0][1];
        ushort x = (ushort)((rect.X+rect.Width*.5)*maxX), y = (ushort)((rect.Y+rect.Height*.5)*maxY);
        long at(double seconds) => (long)(seconds*System.Diagnostics.Stopwatch.Frequency);
        InputFrame frame(int count) { var f = new InputFrame { ContactCount=(byte)count }; for(int i=0;i<count;i++) f.SetContact(i,new((uint)(i+1),x,y,3)); return f; }
        var one = frame(1); var two = frame(2); var up = frame(0);
        core.ProcessFrame(TrackpadSide.Left,in one,maxX,maxY,at(1));
        core.ProcessFrame(TrackpadSide.Left,in two,maxX,maxY,at(1.01),true);
        Check(core.Snapshot(at(1.01)).TouchStateCount == 0,"claim did not cancel pending keyboard touch");
        core.ProcessFrame(TrackpadSide.Left,in one,maxX,maxY,at(1.03),true);
        core.ProcessFrame(TrackpadSide.Left,in up,maxX,maxY,at(1.05),true);
        Span<DispatchEvent> events = new DispatchEvent[32];
        int n = core.DrainDispatchEvents(events);
        Check(n == 0,"claimed cycle emitted keyboard fallback");
        core.ProcessFrame(TrackpadSide.Right,in one,maxX,maxY,at(1.06));
        Check(core.Snapshot(at(1.06)).TouchStateCount > 0,"other pad keyboard was suppressed");
        core.ProcessFrame(TrackpadSide.Right,in up,maxX,maxY,at(1.08));
        core.ProcessFrame(TrackpadSide.Left,in one,maxX,maxY,at(1.09));
        Check(core.Snapshot(at(1.09)).TouchStateCount > 0,"reused IDs remained disqualified after all-up");

        keymap.Mappings[0][GridKeyPosition.StorageKey(TrackpadSide.Left,0,1)] = new KeyMapping { Primary = new KeyAction { Label = "Shift" }, Hold = null };
        var modifierCore = TouchProcessorFactory.CreateDefault(keymap); modifierCore.UseHandGestureRecognition();
        modifierCore.SetKeyboardModeEnabled(true);
        modifierCore.ProcessFrame(TrackpadSide.Left,in one,maxX,maxY,at(2));
        modifierCore.ProcessFrame(TrackpadSide.Left,in two,maxX,maxY,at(2.01),true);
        n = modifierCore.DrainDispatchEvents(events);
        var emitted = events[..n].ToArray();
        Check(emitted.Count(ev => ev.Kind == DispatchEventKind.ModifierDown) == 1
            && emitted.Count(ev => ev.Kind == DispatchEventKind.ModifierUp) == 1,"claim did not balance an engaged modifier");

        // Existing Windows settings must not resurrect five-finger toggle actions.
        var five = frame(5);
        for (int i = 0; i < 5; i++) five.SetContact(i,new((uint)(i+1),(ushort)(x+1000),y,3));
        modifierCore.ProcessFrame(TrackpadSide.Left,in up,maxX,maxY,at(2.02),true);
        var fiveStart = frame(5);
        modifierCore.ProcessFrame(TrackpadSide.Left,in fiveStart,maxX,maxY,at(2.03));
        modifierCore.ProcessFrame(TrackpadSide.Left,in five,maxX,maxY,at(2.05));
        Check(modifierCore.Snapshot(at(2.05)).TypingEnabled,"legacy five-finger action remained active in Windows composition");
    }
}
