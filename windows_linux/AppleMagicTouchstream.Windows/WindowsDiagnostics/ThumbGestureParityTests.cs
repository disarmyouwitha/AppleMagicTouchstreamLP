using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AppleMagicTouchstream;

internal static class ThumbGestureParityTests
{
    private static readonly HandMovementDirection[] Diagonals=[HandMovementDirection.UpLeft,HandMovementDirection.UpRight,HandMovementDirection.DownLeft,HandMovementDirection.DownRight];
    private sealed class Output : IHandGestureOutput
    {
        internal readonly List<HandGestureAction> Actions=[];
        internal readonly List<(int Owner,string? Label)> Held=[];
        public void Move(double x,double y) { throw new InvalidOperationException("Thumb input leaked pointer output"); }
        public void Scroll(double x,double y) { throw new InvalidOperationException("Thumb input leaked scroll output"); }
        public void PrimaryButton(bool down) { throw new InvalidOperationException("Thumb input leaked drag output"); }
        public void Tap(HandGestureAction action)=>Actions.Add(action);
        public void Zoom(double delta) { }
        public void ForceFeedback(TrackpadSide side) { }
        public void HeldAssignment(int owner,string? label)=>Held.Add((owner,label));
    }
    private static void Check(bool pass,string message) { if(!pass) throw new InvalidOperationException(message); }
    private static HandGestureContact[] Chord(double x=0,double y=0,int thumb=1)
        =>[new(10,35+x,85+y,thumb),new(11,70+x,40+y,2),new(12,85+x,40+y,3)];
    private static HandGestureSettings Settings()
    {
        var settings=new HandGestureSettings();
        foreach(var hand in new[]{settings.Left,settings.Right})
        {
            foreach(var trigger in Enum.GetValues<HandGestureTrigger>()) hand.Set(trigger,HandGestureAction.None);
            hand.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.None };
            hand.DirectionalMovement=new() { [HandGestureTrigger.ThumbTwoMove]=new() {
                Actions=Diagonals.ToDictionary(d=>d,d=>HandGestureAction.Copy) } };
        }
        settings.Coordinated.HoldActions=new() { [CoordinatedHandChord.OuterCorners]=HandGestureAction.None };
        return settings;
    }
    private static (HandGestureEngine Engine,Output Output) Start(HandGestureSettings settings,TrackpadSide side)
    {
        var output=new Output(); var engine=WindowsHandGestures.CreateRecognizer(output); engine.Configure(settings,false);
        engine.Process(side,[],.9,.9,true); output.Held.Clear(); return(engine,output);
    }
    internal static void Run()
    {
        foreach(var side in new[]{TrackpadSide.Left,TrackpadSide.Right})
        {
            foreach(var direction in Diagonals)
            {
                var (engine,output)=Start(Settings(),side);
                double sx=direction is HandMovementDirection.UpLeft or HandMovementDirection.DownLeft ? -1:1;
                double sy=direction is HandMovementDirection.UpLeft or HandMovementDirection.UpRight ? -1:1;
                engine.Process(side,Chord(),1,1,true);
                engine.Process(side,Chord(sx*.5,sy*.5),1.01,1.01,true);
                Check(output.Actions.Count==0,"Diagonal activated below 0.75 mm projected travel");
                engine.Process(side,Chord(sx*.55,sy*.55),1.02,1.02,true);
                Check(output.Actions.Count==1 && engine.RecentRecognition(side,1.02)?.Direction==direction,"Wrong diagonal or activation threshold");
                Check(engine.RecentRecognition(side,1.02)?.Title.Contains("Thumb + 2")==true,"Thumb movement feedback missing");
                // Owner and direction remain valid through unknown labels and partial lifts.
                engine.Process(side,[new(11,70+sx*.6,40+sy*.6),new(12,85+sx*.6,40+sy*.6)],1.03,1.03,true);
                engine.Process(side,[],1.04,1.04,true);
                Check(output.Actions.Count==1,"Diagonal lift emitted another action/tap");
                engine.Process(side,Chord(),1.05,1.05,true); engine.Process(side,Chord(sx,sy),1.06,1.06,true);
                Check(output.Actions.Count==2,"Diagonal did not rearm after all-up");
            }
            Reject(side); Holds(side); Competition(side); Repeats(side);
        }
        Stepper(); PersistenceAndInterface();
        Console.WriteLine("Thumb gestures passed: four diagonals, native anatomy/geometry, full-chord travel, direction changes/repeats, independent Hold, arbitration, cleanup and settings/UI. No native input.");
    }
    private static void Reject(TrackpadSide side)
    {
        for(int test=0;test<8;test++)
        {
            var (engine,output)=Start(Settings(),side);
            var first=Chord(); var next=Chord(2,2);
            switch(test)
            {
                case 0: first=Chord(thumb:0); next=Chord(2,2,0); break;
                case 1: first[1]=first[1] with {Finger=1}; next[1]=next[1] with {Finger=1}; break;
                case 2: first[2]=first[2] with {Finger=2}; next[2]=next[2] with {Finger=2}; break;
                case 3: first[0]=first[0] with {X=65,Y=50}; next[0]=first[0] with {X=67,Y=52}; break;
                case 4: first[0]=first[0] with {Hand=1}; next[0]=next[0] with {Hand=1}; first[1]=first[1] with {Hand=2}; next[1]=next[1] with {Hand=2}; break;
                case 5: next[0]=first[0]; break; // stationary thumb, only fingertips moved
                case 6: next=Chord(2,0); break; // cardinal is outside diagonal sectors
                case 7: first[0]=first[0] with {Finger=6}; next[0]=next[0] with {Finger=6}; break;
            }
            engine.Process(side,first,1,1,true); engine.Process(side,next,1.01,1.01,true); engine.Process(side,[],1.02,1.02,true);
            Check(output.Actions.Count==0,$"Invalid thumb chord activated: {test}");
        }
        var (joined,recording)=Start(Settings(),side);
        joined.Process(side,Chord()[..2],1,1,true);
        joined.Process(side,Chord(5,5),1.01,1.01,true);
        joined.Process(side,Chord(5.1,5.1),1.02,1.02,true);
        Check(recording.Actions.Count==0,"Pre-cohort travel activated a joining thumb chord");
        joined.Process(side,Chord(6,6),1.03,1.03,true);
        Check(recording.Actions.Count==1,"Joined thumb chord failed to establish a fresh baseline");
    }
    private static void Holds(TrackpadSide side)
    {
        var settings=Settings(); var hand=side==TrackpadSide.Left ? settings.Left:settings.Right;
        hand.DirectionalMovement=null; hand.HoldActions=new() { [3]=HandGestureAction.Copy,[6]=HandGestureAction.Paste };
        hand.HoldThresholds=new() { [3]=100,[6]=300 };
        var (engine,output)=Start(settings,side);
        engine.Process(side,Chord(),1,1,true);
        for(int i=1;i<=3;i++) engine.Process(side,Chord(),1+i*.1,1+i*.1,true);
        Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Paste}) && engine.RecentRecognition(side,1.3)?.Title=="Thumb + 2 fingertips hold","Thumb Hold used ordinary three-finger action/threshold");
        engine.Process(side,Chord(thumb:0)[..2],1.4,1.4,true); engine.Process(side,[],1.5,1.5,true);
        Check(output.Actions.Count==1,"Hold changed owner through partial lift");
        var noThumb=Chord(thumb:0);
        engine.Process(side,noThumb,1.6,1.6,true); engine.Process(side,noThumb,1.71,1.71,true);
        Check(output.Actions.Last()==HandGestureAction.Copy,"Unknown anatomy incorrectly required a thumb for ordinary Hold");
        engine.Process(side,[],1.72,1.72,true);
        var invalid=Chord(); invalid[0]=invalid[0] with {X=65,Y=50};
        engine.Process(side,invalid,1.8,1.8,true);
        for(int i=1;i<=4;i++) engine.Process(side,invalid.Select(c=>c with {Finger=0}).ToArray(),1.8+i*.1,1.8+i*.1,true);
        Check(output.Actions.Count==2,"Known invalid thumb chord fell through to ordinary three-finger Hold");

        hand.HoldActions[6]=HandGestureAction.Custom; hand.CustomActions=new() { ["Hold6"]="Ctrl+C" }; hand.HeldShortcuts.Add("Hold6"); hand.HoldThresholds[6]=100;
        for(int cleanup=0;cleanup<5;cleanup++)
        {
            (engine,output)=Start(settings,side);
            engine.Process(side,Chord(),1,1,true); engine.Process(side,Chord(thumb:0),1.11,1.11,true);
            Check(output.Held.Count(c=>c.Label=="Ctrl+C")==1,"Thumb Hold failed to retain native identity before firing");
            switch(cleanup)
            {
                case 0: engine.Process(side,[],1.12,1.12,true); break;
                case 1: engine.Tick(1.3,true); break;
                case 2: engine.Cancel(side); break;
                case 3: engine.Configure(settings,false); break;
                case 4: var bad=Chord(); bad[0]=bad[0] with {X=double.NaN}; engine.Process(side,bad,1.12,1.12,true); break;
            }
            Check(output.Held.Last(c=>c.Owner==(int)side).Label==null,"Held thumb shortcut leaked keys on cleanup");
        }
    }
    private static void Competition(TrackpadSide side)
    {
        var settings=Settings(); var hand=side==TrackpadSide.Left ? settings.Left:settings.Right;
        hand.HoldActions=new() { [6]=HandGestureAction.Paste }; hand.HoldThresholds=new() { [6]=100 };
        var (engine,output)=Start(settings,side);
        engine.Process(side,Chord(),1,1,true); engine.Process(side,Chord(.6,.6),1.11,1.11,true);
        Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Copy}),"Pending Hold beat a qualifying diagonal");
        engine.Tick(1.3,true); Check(output.Actions.Count==1,"Stale diagonal repeated");
        hand.Set(HandGestureTrigger.ThreeFingerPinch,HandGestureAction.Cut);
        (engine,output)=Start(settings,side); var origin=Chord();
        engine.Process(side,origin,1,1,true);
        var pinch=origin.Select(c=>c with {X=63+(c.X-63)*.8+.6,Y=55+(c.Y-55)*.8+.6}).ToArray();
        engine.Process(side,pinch,1.01,1.01,true);
        Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Cut}) && engine.RecentRecognition(side,1.01)?.Trigger==HandGestureTrigger.ThreeFingerPinch,"Diagonal stole a dominant pinch");
    }
    private static void Stepper()
    {
        var directions=new HandDirectionalSettings(); var stepper=new ThumbDirectionalStepper();
        stepper.Begin(HandMovementDirection.UpLeft,1);
        Check(stepper.Process(.3,.3,1.01,directions)==null,"Direction switched below travel/time hysteresis");
        Check(stepper.Process(.3,.3,1.09,directions)==HandMovementDirection.DownRight,"Direction change failed");
        Check(stepper.Process(0,0,1.2,directions)==null && stepper.Process(.8,.8,1.3,directions)==null,"Once mode repeated");
        directions.RepeatModes[HandMovementDirection.DownRight]=HandShapeRepeatMode.Motion;
        Check(stepper.Process(.8,.8,1.31,directions)==HandMovementDirection.DownRight,"Motion repeat failed");
        Check(stepper.Process(.8,.8,1.32,directions)==null,"Motion repeat exceeded 80 ms output limit");
        directions.RepeatModes[HandMovementDirection.DownRight]=HandShapeRepeatMode.Timed;
        directions.RepeatMilliseconds[HandMovementDirection.DownRight]=100;
        Check(stepper.Tick(1.35,directions)==null && stepper.Tick(1.42,directions)==HandMovementDirection.DownRight && stepper.Tick(1.42,directions)==null,"Timed repeat interval/burst guard failed");
        stepper.Reset(); Check(stepper.Tick(2,directions)==null,"Reset left a directional repeat active");
    }
    private static void Repeats(TrackpadSide side)
    {
        var settings=Settings(); var hand=side==TrackpadSide.Left ? settings.Left:settings.Right;
        var directions=hand.DirectionalMovement![HandGestureTrigger.ThumbTwoMove];
        directions.Actions[HandMovementDirection.UpLeft]=HandGestureAction.Paste;
        directions.RepeatModes[HandMovementDirection.DownRight]=HandShapeRepeatMode.Timed;
        directions.RepeatMilliseconds[HandMovementDirection.DownRight]=100;
        var (engine,output)=Start(settings,side);
        engine.Process(side,Chord(),1,1,true); engine.Process(side,Chord(1,1),1.01,1.01,true);
        engine.Process(side,Chord(1,1),1.1,1.1,true); engine.Tick(1.12,true); engine.Tick(1.12,true);
        Check(output.Actions.Count==2,"Live engine missed timed repeat or emitted a catch-up burst");
        engine.Process(side,Chord(.6,.6),1.13,1.13,true);
        Check(output.Actions.Count==2,"Direction change ignored 80 ms output guard");
        engine.Process(side,Chord(.2,.2),1.21,1.21,true);
        Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Copy,HandGestureAction.Copy,HandGestureAction.Paste})
            && engine.RecentRecognition(side,1.21)?.Direction==HandMovementDirection.UpLeft,"Live direction stepper used wrong assignment or feedback");
        engine.Tick(1.3,true); Check(output.Actions.Count==3,"Old timed direction repeated after a direction change");
        engine.Process(side,[],1.31,1.31,true); engine.Tick(1.4,true);
        Check(output.Actions.Count==3,"Lift failed to cancel timed repeats");
        (engine,output)=Start(settings,side);
        engine.Process(side,Chord(),1,1,true); engine.Process(side,Chord(1,1),1.01,1.01,true);
        engine.Tick(1.2,true); Check(output.Actions.Count==1,"Stale contact delivery left a timed repeat active");
    }
    private static void PersistenceAndInterface()
    {
        Check((int)HandGestureTrigger.ThumbTwoMove==30 && (int)HandGestureTrigger.FiveFingerRotateRight==29
            && (int)HandMovementDirection.Right==3,"Existing serialized enum identity changed");
        var defaults=new PerHandGestureSettings(); Check(!defaults.Enabled(HandGestureTrigger.ThumbTwoMove) && defaults.Hold(6)==HandGestureAction.None,"New thumb gestures must default None");
        var settings=new UserSettings(); var panel=new HandGesturePanel(settings,()=>{}); panel.SelectPage("thumb"); panel.MirrorEdits=true;
        foreach(var direction in Diagonals)
        {
            panel.SelectSlot("ThumbTwoMove/"+direction); Check(panel.SelectedSlot=="ThumbTwoMove/"+direction,"Missing diagonal card");
            var action=HandGestureTests.Controls<SearchableActionComboBox>(panel).Single(c=>c.PickerTitle=="Gesture Action");
            action.SelectedValuePath="Action"; action.SelectedValue=HandGestureAction.Copy;
                var mode=HandGestureTests.Controls<ComboBox>(panel).Single(c=>Equals(c.Tag,"ThumbRepeatMode")); mode.SelectedValuePath="Mode"; mode.SelectedValue=HandShapeRepeatMode.Motion;
            foreach(var hand in new[]{settings.HandGesturesV1.Left,settings.HandGesturesV1.Right})
                Check(hand.Enabled(HandGestureTrigger.ThumbTwoMove) && hand.Directional(HandGestureTrigger.ThumbTwoMove)?.Mode(direction)==HandShapeRepeatMode.Motion,"Mirror Edit lost diagonal action/repeat");
        }
        panel.SelectSlot("Hold6"); Check(panel.SelectedSlot=="Hold6","Missing independent thumb Hold card");
        var holdAction=HandGestureTests.Controls<SearchableActionComboBox>(panel).Single(c=>c.PickerTitle=="Gesture Action");
        holdAction.SelectedValuePath="Action"; holdAction.SelectedValue=HandGestureAction.Paste;
        settings.HandGesturesV1.Right.HoldThresholds=new() { [6]=777 };
        var bundle=AppleMagicTouchstreamProfileBundle.Create(settings,KeymapStore.LoadBundledDefault());
        Check(AppleMagicTouchstreamProfileBundle.TryParse(bundle.SerializeToJson(),out var parsed,out var error),error);
        Check(parsed.TryLoadPortableProfile(out var restored,out _,out error),error);
        Check(restored.HandGesturesV1.Right.Hold(6)==HandGestureAction.Paste && restored.HandGesturesV1.Right.HoldMilliseconds(6)==777
            && restored.HandGesturesV1.Left.Directional(HandGestureTrigger.ThumbTwoMove)?.Mode(HandMovementDirection.UpLeft)==HandShapeRepeatMode.Motion,"Settings export lost thumb gestures");
        var clone=JsonSerializer.Deserialize<HandGestureSettings>(JsonSerializer.Serialize(settings.HandGesturesV1))!;
        clone.Left.DirectionalMovement=null; clone.Left.HoldActions=null;
        var fallback=clone.For(TrackpadSide.Left,true);
        Check(fallback.Enabled(HandGestureTrigger.ThumbTwoMove) && fallback.Hold(6)==HandGestureAction.Paste && fallback.HoldMilliseconds(6)==777,"Single-pad fallback lost thumb gesture settings");
        var copied=fallback.Clone(); copied.DirectionalMovement![HandGestureTrigger.ThumbTwoMove].RepeatModes[HandMovementDirection.UpLeft]=HandShapeRepeatMode.Once;
        Check(fallback.Directional(HandGestureTrigger.ThumbTwoMove)?.Mode(HandMovementDirection.UpLeft)==HandShapeRepeatMode.Motion,"Clone shared repeat settings");
        var path=Path.Combine(Path.GetTempPath(),"AMT-thumb-"+Guid.NewGuid().ToString("N")+".json");
        try
        {
            Check(settings.TrySave(path,out error),error);
            var loaded=UserSettings.Load(path);
            Check(loaded.HandGesturesV1.Right.HoldMilliseconds(6)==777 && loaded.HandGesturesV1.Left.Enabled(HandGestureTrigger.ThumbTwoMove),"Saved thumb settings failed to survive restart");
        }
        finally { if(File.Exists(path)) File.Delete(path); }
        if(Environment.GetEnvironmentVariable("APPLEMAGICTOUCHSTREAM_THUMB_PREVIEW_DIR") is {} directory)
        {
            Directory.CreateDirectory(directory);
            foreach(int width in new[]{1380,1100})
            {
                panel.SelectSlot("ThumbTwoMove/UpLeft"); panel.Measure(new Size(width,900)); panel.Arrange(new Rect(0,0,width,900)); panel.UpdateLayout();
                var bitmap=new RenderTargetBitmap(width,900,96,96,PixelFormats.Pbgra32); bitmap.Render(panel);
                var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var file=File.Create(Path.Combine(directory,$"thumb-gestures-{width}.png")); encoder.Save(file);
            }
        }
    }
}
