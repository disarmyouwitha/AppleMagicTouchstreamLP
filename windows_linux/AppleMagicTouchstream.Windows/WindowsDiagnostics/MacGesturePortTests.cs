using System.Text.Json;
namespace AppleMagicTouchstream;

// Recognition/output plans only. Never opens hardware or posts OS input.
internal static class MacGesturePortTests
{
    private sealed class Output : IHandGestureOutput
    {
        public readonly List<double> Zooms=[];
        public readonly List<HandGestureAction> Actions=[];
        public readonly List<bool> Buttons=[];
        public readonly List<TrackpadSide> Haptics=[];
        public int Moves, Scrolls;
        public void Move(double x,double y) => Moves++;
        public void Scroll(double x,double y) => Scrolls++;
        public void PrimaryButton(bool down) => Buttons.Add(down);
        public void Tap(HandGestureAction action) => Actions.Add(action);
        public void Zoom(double delta) => Zooms.Add(delta);
        public void ForceFeedback(TrackpadSide side) => Haptics.Add(side);
    }
    private static void Check(bool pass,string message) { if (!pass) throw new InvalidOperationException(message); }
    private static HandGestureContact[] Shape(int count,double scale=1,double translation=0, double pressure=0,bool hasPressure=false)
        => Enumerable.Range(0,count).Select(i=>new HandGestureContact((uint)i+1,60+(i-(count-1)/2.0)*16*scale+translation,50,
            Pressure:pressure,HasPressure:hasPressure)).ToArray();
    public static void Run()
    {
        foreach (var side in new[] { TrackpadSide.Left,TrackpadSide.Right })
        {
            var settings=new HandGestureSettings();
            var output=new Output(); var engine=new HandGestureEngine(output);
            void configure() { engine.Configure(settings,false); engine.Process(side,[],.9,.9,true); }
            bool frame(HandGestureContact[] c,double t,bool eligible=true) => engine.Process(side,c,t,t,eligible);
            foreach (int n in Enumerable.Range(2,4)) foreach (bool spread in new[] { false,true })
            {
                output=new(); engine=new(output); configure();
                Check(frame(Shape(n),1),"pinch family did not reserve keyboard input");
                frame(Shape(n,spread ? 1.16 : .84),1.01);
                Check(output.Zooms.Count==1 && Math.Sign(output.Zooms[0])==(spread ? 1 : -1),"shape activation did not select signed Zoom");
                frame(Shape(n,spread ? .84 : 1.16),1.02);
                Check(output.Zooms.Count==2 && Math.Sign(output.Zooms[1])==(spread ? -1 : 1),"zoom reversed ownership instead of direction");
                Check(output.Moves==0 && output.Scrolls==0 && output.Buttons.Count==0,"pinch emitted competing mouse output");
                Check(frame([],1.04),"pinch all-up lost keyboard reservation");
                Check(output.Actions.Count==0,"pinch all-up emitted a tap");
            }
            // Zoom remains active through 2 -> 5 -> 1, with added-member rebase.
            output=new(); engine=new(output); configure(); frame(Shape(2),1); frame(Shape(2,.84),1.01);
            frame(Shape(5),1.02); Check(output.Zooms[^1]==0,"joining fingers caused a zoom jump");
            frame(Shape(5,.97),1.03); int before=output.Zooms.Count;
            var survivor=Shape(5,.97).Take(1).ToArray(); frame(survivor,1.04);
            survivor[0]=survivor[0] with { X=survivor[0].X-1 }; frame(survivor,1.05);
            Check(output.Zooms.Count==before+2 && output.Zooms[^1]>0,"survivor did not continue against virtual anchor");
            frame([],1.07);

            // A shell binding is one-shot even on reversal and membership changes.
            var hand=side==TrackpadSide.Left ? settings.Left : settings.Right;
            hand.Set(HandGestureTrigger.TwoFingerPinch,HandGestureAction.TaskView);
            output=new(); engine=new(output); configure(); frame(Shape(2),1); frame(Shape(2,.84),1.01);
            frame(Shape(2,1.05),1.02); frame(Shape(4),1.03); frame(Shape(4,.95),1.04); frame([],1.06);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.TaskView}) && output.Zooms.Count==0,"shell pinch repeated or produced Zoom");
            hand.Set(HandGestureTrigger.TwoFingerPinch,HandGestureAction.None);
            output=new(); engine=new(output); configure(); frame(Shape(2),1); frame(Shape(2,.84),1.01);
            Check(output.Zooms.Count==0 && output.Actions.Count==0,"disabled inward direction still activated");
            frame(Shape(2,1.16),1.02); Check(output.Zooms.Count==1 && output.Zooms[0]>0,"outward direction inherited disabled inward binding"); frame([],1.04);
            hand.Set(HandGestureTrigger.TwoFingerPinch,HandGestureAction.Zoom);

            output=new(); engine=new(output); configure(); frame(Shape(4),1);
            // Use a small rotation to remain inside the existing 25 mm motion guard.
            var rigid=Shape(4).Select(c=>c with { X=60+(c.X-60)*Math.Cos(.1)+.3, Y=50+(c.X-60)*Math.Sin(.1) }).ToArray();
            frame(rigid,1.01); Check(output.Zooms.Count==0,"rigid translation/rotation became shape scaling"); frame([],1.03);

            output=new(); engine=new(output); configure(); frame(Shape(2),1); frame(Shape(2,.84),1.01);
            int zoomBefore=output.Zooms.Count;
            frame(Shape(2,.8),1.02,false); frame(Shape(2,.75),1.03); frame([],1.05);
            Check(output.Zooms.Count==zoomBefore,"disabled pinch resumed before all-up");

            // Force chooses current contact count and fires once; unknown pressure cannot fire.
            foreach (int n in Enumerable.Range(1,5))
            {
                hand.Set(PerHandGestureSettings.Force(n)!.Value,HandGestureAction.SecondaryClick);
                output=new(); engine=new(output); configure(); frame(Shape(n,pressure:129,hasPressure:true),1);
                Check(output.Actions.Count==0,"force fired below threshold");
                Check(frame(Shape(n,pressure:130,hasPressure:true),1.01),"force crossing did not reserve input");
                frame(Shape(n,pressure:200,hasPressure:true),1.02); frame(Shape(1,pressure:200,hasPressure:true),1.03); frame([],1.05);
                Check(output.Actions.SequenceEqual(new[]{HandGestureAction.SecondaryClick}) && output.Haptics.SequenceEqual(new[]{side}),"force repeated, used wrong count or haptic pad");
                output=new(); engine=new(output); configure(); frame(Shape(n,pressure:255),1);
                Check(output.Actions.Count==0 && output.Haptics.Count==0,"pressure-free decoder produced force click"); frame([],1.05);
                hand.Set(PerHandGestureSettings.Force(n)!.Value,HandGestureAction.None);
            }
            hand.Set(HandGestureTrigger.OneFingerForce,HandGestureAction.PrimaryClick);
            hand.Set(HandGestureTrigger.TwoFingerForce,HandGestureAction.PrimaryClick);
            output=new(); engine=new(output); configure(); frame(Shape(2,pressure:80,hasPressure:true),1);
            Check(output.Actions.Count==0,"force summed pressures instead of using their maximum");
            var invalid=Shape(2,pressure:150,hasPressure:true); invalid[1]=invalid[1] with { Id=invalid[0].Id };
            frame(invalid,1.02); frame([],1.04);
            Check(output.Actions.Count==0,"invalid duplicate IDs produced a force action");
            hand.Set(HandGestureTrigger.TwoFingerForce,HandGestureAction.None);
            output=new(); engine=new(output); configure(); frame(Shape(2),1); frame(Shape(1,pressure:200,hasPressure:true),1.02); frame([],1.04);
            Check(output.Actions.Count==0,"partial lift became a one-finger force click");
            // Force interrupts a drag with a balanced button release.
            hand.Set(HandGestureTrigger.ThreeFingerForce,HandGestureAction.ShowDesktop);
            output=new(); engine=new(output); configure(); frame(Shape(3),1); frame(Shape(3),1.08); frame(Shape(3,translation:.4),1.13);
            Check(output.Buttons.SequenceEqual(new[]{true}),"drag fixture failed to activate after settling");
            frame(Shape(3,translation:.5,pressure:150,hasPressure:true),1.14); frame([],1.16);
            Check(output.Buttons.SequenceEqual(new[]{true,false}) && output.Actions.Count==0,"force replaced an already activated drag owner");
            hand.Set(HandGestureTrigger.ThreeFingerForce,HandGestureAction.None);
            output=new(); engine=new(output); configure(); frame(Shape(2),1); frame(Shape(2,.84),1.01);
            frame(Shape(2,.90,pressure:140,hasPressure:true),1.02); // two force is None: continue Zoom.
            Check(output.Actions.Count==0 && output.Zooms.Count==2,"None force interrupted Zoom");
            engine.Tick(1.3,true); frame(Shape(2,.85),1.31); frame([],1.33);
            Check(output.Zooms.Count==2,"stale pinch resumed before clean lift");
        }
        // Existing enum values, saved custom bindings, clone isolation and portable exports.
        Check((int)HandGestureTrigger.ThumbTwoTap==5 && (int)HandGestureAction.SecondaryClick==6,"old enum serialization changed");
        var old=JsonSerializer.Deserialize<HandGestureSettings>("{\"Left\":{\"TwoFingerTap\":6}}")!; old.Normalize();
        Check(old.Left.TwoFingerTap==HandGestureAction.SecondaryClick && old.Left.Get(HandGestureTrigger.FiveFingerSpread)==HandGestureAction.Zoom,"old bindings did not preserve values/default new inputs");
        var settings2=new UserSettings(); settings2.HandGesturesV1.Left.Set(HandGestureTrigger.FiveFingerSpread,HandGestureAction.StartMenu); settings2.HandGesturesV1.Left.ZoomSensitivity=1.35;
        var bundle=AppleMagicTouchstreamProfileBundle.Create(settings2,KeymapStore.LoadBundledDefault());
        Check(bundle.TryLoadPortableProfile(out var restored,out _,out _) && restored.HandGesturesV1.Left.Get(HandGestureTrigger.FiveFingerSpread)==HandGestureAction.StartMenu
            && restored.HandGesturesV1.Left.ZoomSensitivity==1.35,"portable export lost new gestures");
        restored.HandGesturesV1.Left.Set(HandGestureTrigger.FiveFingerSpread,HandGestureAction.None);
        Check(settings2.HandGesturesV1.Left.Get(HandGestureTrigger.FiveFingerSpread)==HandGestureAction.StartMenu,"gesture clone shared mutable bindings");
        foreach (var action in new[] { HandGestureAction.NotificationCenter,HandGestureAction.TaskView,HandGestureAction.StartMenu,HandGestureAction.ShowDesktop })
        {
            var edges=WindowsGestureShortcutPlan.For(action); var held=new HashSet<ushort>();
            foreach (var edge in edges) Check(edge.Up ? held.Remove(edge.Key) : held.Add(edge.Key),"shortcut edges are unbalanced");
            Check(edges.Length>0 && held.Count==0,"shortcut left a key held");
        }
        Check(NativeGestureOutput.InputSize==(IntPtr.Size==8 ? 40 : 28),"native input union has incorrect ABI size");
    }
}
