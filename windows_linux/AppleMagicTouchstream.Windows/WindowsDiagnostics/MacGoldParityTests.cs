using System.Text.Json;

namespace AppleMagicTouchstream;

internal static class MacGoldParityTests
{
    private sealed class Output : IHandGestureOutput
    {
        public readonly List<HandGestureAction> Actions=[];
        public int Moves, Scrolls;
        public readonly List<string> Assignments=[];
        public readonly List<string?> Held=[];
        public readonly List<bool> Buttons=[];
        public void Move(double x,double y) => Moves++;
        public void Scroll(double x,double y) { Scrolls++; }
        public void PrimaryButton(bool down) => Buttons.Add(down);
        public void Tap(HandGestureAction action) { if (action!=HandGestureAction.None) Actions.Add(action); }
        public void Zoom(double delta) { }
        public void ForceFeedback(TrackpadSide side) { }
        public void AssignedAction(string label) => Assignments.Add(label);
        public void HeldAssignment(int owner,string? label) { if (owner<2) Held.Add(label); }
    }
    private static void Check(bool value,string message) { if (!value) throw new InvalidOperationException(message); }
    private static HandGestureSettings Empty()
    {
        var settings=new HandGestureSettings();
        foreach (var hand in new[] { settings.Left, settings.Right })
        {
            foreach (var trigger in Enum.GetValues<HandGestureTrigger>()) hand.Set(trigger,HandGestureAction.None);
            hand.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.None };
        }
        settings.Coordinated.HoldActions[CoordinatedHandChord.OuterCorners]=HandGestureAction.None;
        return settings;
    }
    private static HandGestureContact[] Contacts(int count,double dx=0,double dy=0)
        => Enumerable.Range(0,count).Select(i=>new HandGestureContact((uint)i+1,30+i*16+dx,50+dy)).ToArray();
    private static (HandGestureEngine Engine,Output Output) Create(HandGestureSettings settings,bool same=false)
    {
        var output=new Output(); var engine=new HandGestureEngine(output); engine.Configure(settings,same);
        engine.Process(TrackpadSide.Left,[],.9,.9,true); engine.Process(TrackpadSide.Right,[],.9,.9,true);
        return (engine,output);
    }
    private static bool Frame(HandGestureEngine engine,HandGestureContact[] contacts,double time,TrackpadSide side=TrackpadSide.Left,bool eligible=true)
        => engine.Process(side,contacts,time,time,eligible);
    private static void RunCapturedCorners()
    {
        var assembly=typeof(MacGoldParityTests).Assembly;
        string resource=assembly.GetManifestResourceNames().Single(n=>n.EndsWith(".FourCorners.atpcap",StringComparison.Ordinal));
        string path=System.IO.Path.Combine(System.IO.Path.GetTempPath(),"amt-corner-regression-"+Guid.NewGuid().ToString("N")+".atpcap");
        try
        {
            using (var source=assembly.GetManifestResourceStream(resource)!)
            using (var file=System.IO.File.Create(path)) source.CopyTo(file);
            Span<HandGestureContact> contacts=stackalloc HandGestureContact[InputFrame.MaxContacts];
            foreach (var side in new[] { TrackpadSide.Left,TrackpadSide.Right })
            {
                var settings=Empty(); var hand=side==TrackpadSide.Left ? settings.Left : settings.Right;
                hand.TwoFingerMove=HandGestureAction.Pointer; hand.TwoFingerTap=HandGestureAction.PrimaryClick;
                hand.ThreeFingerMove=HandGestureAction.PrimaryDrag; hand.ThreeFingerTap=HandGestureAction.SecondaryClick;
                hand.FourFingerMove=HandGestureAction.Scroll;
                hand.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.OpenConfig };
                var (engine,output)=Create(settings); Frame(engine,[],-.01,side);
                using var reader=new InputCaptureReader(path); long? first=null; int index=0,previouslyLegacy=0;
                var decoderSession=new TrackpadDecoderSession();
                var overrides=new Dictionary<string,TrackpadDecoderProfile>();
                while (reader.TryReadNext(out var record))
                {
                    first ??=record.ArrivalQpcTicks;
                    double time=(record.ArrivalQpcTicks-first.Value)/(double)reader.HeaderQpcFrequency;
                    var info=new RawInputDeviceInfo(record.VendorId,record.ProductId,record.UsagePage,record.Usage);
                    // Re-run today's live Auto selection. Honoring the stored
                    // historical profile would deliberately reproduce the bug.
                    var profile=TrackpadDecoderProfileResolver.ResolveAuto(record.Payload.Span,in info);
                    Check(profile==TrackpadDecoderProfile.Official,$"edge contact changed packet layout at recorded frame {index}");
                    if (record.DecoderProfile==TrackpadDecoderProfile.Legacy) previouslyLegacy++;
                    var device=new RawInputDeviceSnapshot("recorded-pad",info,new(0,1));
                    Check(decoderSession.TryDecode(1,in device,record.Payload.Span,record.ArrivalQpcTicks,overrides,out profile,out var decoded)
                        && profile==TrackpadDecoderProfile.Official,
                        $"corner recording failed to decode frame {index}");
                    var frame=decoded.Frame;
                    int count=WindowsHandGestures.ReadContacts(in frame,7612,5065,contacts,out bool fourthPending);
                    foreach (var c in contacts[..count]) Check(c.X is >=0 and <=160 && c.Y is >=0 and <=114.9,"corner decoding produced out-of-range geometry");
                    engine.Process(side,contacts[..count],time,time,true,fourthContactPending:fourthPending); engine.Tick(time,true);
                    index++;
                }
                int opened=output.Actions.Count(a=>a==HandGestureAction.OpenConfig);
                Check(index==484 && previouslyLegacy==211 && opened==3 && output.Buttons.Count==0,
                    $"corner replay changed: frames={index}, old Legacy packets={previouslyLegacy}, opens={opened}, drag edges={output.Buttons.Count}");
                Console.WriteLine($"Corner replay ({side}): {index} frames, {previouslyLegacy} formerly Legacy packets, {opened} Open Config actions.");
            }
        }
        finally { if (System.IO.File.Exists(path)) System.IO.File.Delete(path); }
    }
    private static void RunPendingAcquisition()
    {
        foreach (var side in new[] { TrackpadSide.Left,TrackpadSide.Right })
        {
            var settings=Empty(); var hand=side==TrackpadSide.Left ? settings.Left : settings.Right;
            hand.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.OpenConfig };
            hand.FourFingerMove=HandGestureAction.Scroll;
            var corners=new HandGestureContact[] { new(1,10,10),new(2,10,100),new(3,150,10),new(4,150,100) };
            var (engine,output)=Create(settings);
            // A forming pair can invalidate its generic Hold before all four
            // corners land. The completed corner chord gets its own baseline.
            Frame(engine,corners[..2],1,side);
            var shifted=corners.Select(c=>c with { X=c.X+3 }).ToArray();
            Frame(engine,shifted[..2],1.02,side);
            Frame(engine,shifted,1.03,side);
            for (int i=1;i<=11;i++) Frame(engine,shifted,1.03+i*.05,side);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.OpenConfig}) && output.Scrolls==0,
                "moving partial cohort poisoned the completed corner Hold");
            Frame(engine,shifted[..2],1.60,side); Frame(engine,[],1.62,side);
            Check(output.Actions.Count==1,"corner partial lift repeated its action");

            // Geometry selects only the initial chord. Remaining within 2mm of
            // those anchors may cross a region boundary without restarting Hold.
            corners[0]=corners[0] with { X=39.5 };
            (engine,output)=Create(settings); Frame(engine,corners,1,side);
            var jitter=corners.Select(c=>c with { X=c.X+.7 }).ToArray();
            for (int i=1;i<=11;i++) Frame(engine,jitter,1+i*.05,side);
            Check(output.Actions.Count==1 && output.Scrolls==0,"corner boundary jitter cancelled valid anchored Hold");
            Frame(engine,[],1.57,side);

            // Lifting before the threshold cannot reassemble/restart corners or
            // fall back to a smaller gesture during the reserved cycle.
            (engine,output)=Create(settings); Frame(engine,corners,1,side); Frame(engine,corners[..3],1.05,side);
            for (int i=1;i<=11;i++) Frame(engine,corners,1.05+i*.05,side);
            Frame(engine,[],1.62,side);
            Check(output.Actions.Count==0 && output.Scrolls==0,"cancelled corner Hold resumed after partial lift");

            hand.CornerHoldActions[HandCornerChord.OuterCorners]=HandGestureAction.Custom;
            hand.CustomActions=new() { ["CornerHold"]="Shift" }; hand.HeldShortcuts.Add("CornerHold");
            (engine,output)=Create(settings); Frame(engine,corners,1,side);
            for (int i=1;i<=11;i++) Frame(engine,corners,1+i*.05,side);
            Check(output.Held.Last()=="Shift","corner held shortcut failed to activate");
            Frame(engine,corners[..3],1.57,side);
            Check(output.Held.Last()=="Shift","corner partial lift released an activated held shortcut early");
            Frame(engine,corners,1.59,side);
            Check(output.Held.Last()==null,"corner rejoining retained an invalid held shortcut");
            Frame(engine,[],1.61,side);

            settings=Empty(); hand=side==TrackpadSide.Left ? settings.Left : settings.Right;
            hand.FourFingerMove=HandGestureAction.Scroll;
            hand.HoldActions=new() { [4]=HandGestureAction.Paste };
            (engine,output)=Create(settings); var row=Contacts(4); Frame(engine,row,1,side);
            var oneSettles=row.ToArray(); oneSettles[0]=oneSettles[0] with { X=oneSettles[0].X+1 };
            for (int i=1;i<=11;i++) Frame(engine,oneSettles,1+i*.05,side);
            Check(output.Scrolls==0 && output.Actions.SequenceEqual(new[]{HandGestureAction.Paste}),
                "one settling fingertip stole four-finger Hold as scrolling");
            Frame(engine,[],1.57,side);
            (engine,output)=Create(settings); Frame(engine,row,1,side);
            Frame(engine,Contacts(4,.3),1.01,side);
            Check(output.Scrolls==1 && output.Actions.Count==0,"coherent four-finger movement failed to win over pending Hold");
            Frame(engine,Contacts(3,.4),1.02,side); Frame(engine,[],1.04,side);
            Check(output.Actions.Count==0,"activated scroll fell back to Hold after lift");

            // Without a competing Hold, keep ordinary scroll's 0.2mm centroid
            // threshold; the agreement condition is not a global dead zone.
            hand.HoldActions.Clear(); (engine,output)=Create(settings);
            Frame(engine,row,1,side); Frame(engine,oneSettles,1.01,side);
            Check(output.Scrolls==1,"four-finger agreement gate leaked into ordinary scrolling");
            Frame(engine,[],1.03,side);
        }
    }
    public static void Run()
    {
        RunCapturedCorners();
        RunPendingAcquisition();
        foreach (int count in new[] {4,5})
        {
            var settings=Empty(); var trigger=count==4 ? HandGestureTrigger.FourFingerTap : HandGestureTrigger.FiveFingerTap;
            settings.Left.Set(trigger,HandGestureAction.Copy);
            var (engine,output)=Create(settings);
            Check(Frame(engine,Contacts(count),1),"new tap failed to reserve"); Frame(engine,Contacts(count),1.04); Frame(engine,[],1.06);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Copy}),"four/five-finger tap failed");
            (engine,output)=Create(settings); Frame(engine,Contacts(count),1); Frame(engine,Contacts(count,2),1.04); Frame(engine,[],1.06);
            Check(output.Actions.Count==0,"moving chord became a tap");
        }
        for (int count=2;count<=5;count++)
        {
            var settings=Empty(); settings.Left.HoldActions=new() { [count]=HandGestureAction.Paste };
            settings.Left.HoldThresholds=new() { [count]=500 };
            var (engine,output)=Create(settings);
            for (int i=0;i<=9;i++) Frame(engine,Contacts(count),1+i*.05);
            Check(output.Actions.Count==0,"hold fired early");
            Frame(engine,Contacts(count),1.501); Frame(engine,Contacts(count),1.55); Frame(engine,Contacts(1),1.56); Frame(engine,[],1.57);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Paste}),"hold timing, count latch or once-only output failed");
            (engine,output)=Create(settings); Frame(engine,Contacts(count),1); engine.Tick(1.2,true); Frame(engine,Contacts(count),1.21); Frame(engine,[],1.22);
            Check(output.Actions.Count==0,"stale hold resumed without lift");
            (engine,output)=Create(settings);
            for (int i=0;i<=12;i++) Frame(engine,Contacts(count,i*.3),1+i*.05);
            Check(output.Actions.Count==0,"moving chord fired a stationary hold");
        }
        foreach (var direction in Enum.GetValues<HandMovementDirection>())
        {
            var settings=Empty(); settings.Left.DirectionalMovement=new() { [HandGestureTrigger.FiveFingerMove]=new() { Enabled=true, Actions=new() { [direction]=HandGestureAction.Undo }, RepeatMilliseconds=new() { [direction]=80 } } };
            var (engine,output)=Create(settings);
            double x=direction==HandMovementDirection.Left ? -1 : direction==HandMovementDirection.Right ? 1 : 0;
            double y=direction==HandMovementDirection.Up ? -1 : direction==HandMovementDirection.Down ? 1 : 0;
            Frame(engine,Contacts(5),1); Frame(engine,Contacts(5,3.2*x,3.2*y),1.01);
            Check(output.Actions.Count==1 && output.Moves==0,"direction did not select discrete action");
            Frame(engine,Contacts(5,3.2*x,3.2*y),1.10); Check(output.Actions.Count==1,"stationary directional chord repeated");
            Frame(engine,Contacts(5,4.4*x,4.4*y),1.11); Check(output.Actions.Count==2,"travel-gated directional repeat failed");
            Frame(engine,Contacts(2,5*x,5*y),1.12); Frame(engine,[],1.13); Check(output.Actions.Count==2,"count change duplicated directional action");
        }
        foreach (bool hold in new[] {false,true})
        {
            var settings=Empty();
            (hold ? settings.Coordinated.HoldActions : settings.Coordinated.TapActions)[CoordinatedHandChord.ThreeFingers]=HandGestureAction.OpenConfig;
            var (engine,output)=Create(settings); Frame(engine,Contacts(3),1); Check(Frame(engine,Contacts(3),1.02,TrackpadSide.Right),"Both chord did not reserve");
            if (hold) for (int i=1;i<=11;i++) { Frame(engine,Contacts(3),1.02+i*.05); Frame(engine,Contacts(3),1.021+i*.05,TrackpadSide.Right); }
            double end=hold ? 1.6 : 1.08;
            Frame(engine,[],end); Frame(engine,[],end+.01,TrackpadSide.Right);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.OpenConfig}),"Both tap/hold did not fire once");
            (engine,output)=Create(settings,true); Frame(engine,Contacts(3),1); Frame(engine,Contacts(3),1.02,TrackpadSide.Right); Frame(engine,[],1.08); Frame(engine,[],1.09,TrackpadSide.Right);
            Check(output.Actions.Count==0,"same physical pad formed a Both gesture");
        }
        var corners=new HandGestureContact[] { new(1,10,10),new(2,10,100),new(3,150,10),new(4,150,100) };
        var cornerSettings=Empty(); cornerSettings.Left.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.OpenConfig };
        var (cornerEngine,cornerOutput)=Create(cornerSettings);
        for (int i=0;i<=11;i++) Frame(cornerEngine,corners,1+i*.05);
        Frame(cornerEngine,[],1.6); Check(cornerOutput.Actions.Count==1,"per-pad four-corner hold failed");
        // Default Scroll must not steal a stationary corner chord on sub-2mm jitter.
        cornerSettings.Left.FourFingerMove=HandGestureAction.Scroll;
        (cornerEngine,cornerOutput)=Create(cornerSettings);
        for (int i=0;i<=11;i++) Frame(cornerEngine,corners.Select(c=>c with { X=c.X+i*.03 }).ToArray(),1+i*.05);
        Check(cornerOutput.Actions.Count==1,"minor corner jitter acquired ordinary movement before the Hold");
        Frame(cornerEngine,[],1.6);
        cornerSettings.Left.TwoFingerTap=HandGestureAction.PrimaryClick;
        (cornerEngine,cornerOutput)=Create(cornerSettings);
        Frame(cornerEngine,corners.Take(2).ToArray(),1); Frame(cornerEngine,corners,1.02); Frame(cornerEngine,[],1.06);
        Check(cornerOutput.Actions.Count==0,"unfinished corner Hold fell back to a tap from its forming cohort");
        foreach (var chord in Enum.GetValues<CoordinatedHandChord>().Where(c=>c is not (CoordinatedHandChord.ThreeFingers or CoordinatedHandChord.FourFingers)))
        {
            var settings=Empty(); settings.Coordinated.HoldActions[chord]=HandGestureAction.OpenConfig;
            HandGestureContact[] placement(bool leftHand)
            {
                bool outer=chord is CoordinatedHandChord.OuterCorners or CoordinatedHandChord.TopOuter or CoordinatedHandChord.BottomOuter;
                double x=leftHand==outer ? 10 : 150;
                return chord is CoordinatedHandChord.OuterCorners or CoordinatedHandChord.InnerCorners
                    ? [new(1,x,10),new(2,x,100)] : [new(1,x,chord is CoordinatedHandChord.TopOuter or CoordinatedHandChord.TopInner ? 10 : 100)];
            }
            var (engine,output)=Create(settings);
            for (int i=0;i<=11;i++) { Frame(engine,placement(true),1+i*.05); Frame(engine,placement(false),1.001+i*.05,TrackpadSide.Right); }
            Frame(engine,[],1.6); Frame(engine,[],1.61,TrackpadSide.Right);
            Check(output.Actions.Count==1,"coordinated corner geometry/hold failed: "+chord);
        }
        {
            var settings=Empty(); settings.Coordinated.TapActions[CoordinatedHandChord.ThreeFingers]=HandGestureAction.Copy;
            var (engine,output)=Create(settings); Frame(engine,Contacts(3),1); Frame(engine,Contacts(3),1.01,TrackpadSide.Right);
            Frame(engine,Contacts(2),1.04); Frame(engine,Contacts(3),1.05); Frame(engine,[],1.08); Frame(engine,[],1.09,TrackpadSide.Right);
            Check(output.Actions.Count==0,"coordinated tap accepted rejoining after partial lift");
        }
        {
            var settings=Empty(); settings.Coordinated.HoldActions[CoordinatedHandChord.ThreeFingers]=HandGestureAction.OpenConfig;
            settings.Right.TwoFingerTap=HandGestureAction.PrimaryClick;
            var (engine,output)=Create(settings); Frame(engine,Contacts(3),1); Frame(engine,Contacts(3),1.01,TrackpadSide.Right);
            engine.Tick(1.3,true); Frame(engine,[],1.31,TrackpadSide.Right);
            Frame(engine,Contacts(2),1.32,TrackpadSide.Right); Frame(engine,[],1.37,TrackpadSide.Right);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.PrimaryClick}),"stale/disconnected coordinated pad kept the healthy pad reserved");
        }

        var saved=Empty(); saved.Left.HoldActions=new() { [5]=HandGestureAction.Copy }; saved.Left.HoldThresholds=new() { [5]=750 };
        saved.Coordinated.HoldActions[CoordinatedHandChord.InnerCorners]=HandGestureAction.OpenConfig;
        saved.Left.DirectionalMovement=new() { [HandGestureTrigger.TwoFingerMove]=new() { Enabled=true,Actions=new() { [HandMovementDirection.Up]=HandGestureAction.Paste } } };
        var bundle=AppleMagicTouchstreamProfileBundle.Create(new() { HandGesturesV1=saved },KeymapStore.LoadBundledDefault());
        var roundtrip=JsonSerializer.Deserialize<AppleMagicTouchstreamProfileBundle>(bundle.SerializeToJson())!;
        Check(roundtrip.TryLoadPortableProfile(out var restored,out _,out _) && restored.HandGesturesV1.Left.Hold(5)==HandGestureAction.Copy
            && restored.HandGesturesV1.Left.HoldMilliseconds(5)==750 && restored.HandGesturesV1.Coordinated.Action(CoordinatedHandChord.InnerCorners,true)==HandGestureAction.OpenConfig,"new settings did not survive portable export");
        var clone=saved.Clone(); clone.Left.DirectionalMovement![HandGestureTrigger.TwoFingerMove].Actions[HandMovementDirection.Up]=HandGestureAction.None;
        Check(saved.Left.DirectionalMovement[HandGestureTrigger.TwoFingerMove].Get(HandMovementDirection.Up)==HandGestureAction.Paste,"directional settings clone shared dictionaries");

        var keymap=KeymapStore.LoadBundledDefault(); keymap.SetActiveLayout("touchstream");
        var left=TouchStreamLayoutDefinition.Build(true,keymap); var right=TouchStreamLayoutDefinition.Build(false,keymap);
        Check(left.Rects.Sum(r=>r.Length)==43 && right.Rects.Sum(r=>r.Length)==45,"TouchStream trace lost keys");
        Check(left.Labels[0][0]=="Esc" && right.Labels[0][0]=="F8" && left.Rects[0][0].Width>right.Rects[0][0].Width,"TouchStream was mirrored instead of independently traced");
        Check(!TrackpadLayoutPreset.TouchStream.AllowsColumnSettings && TrackpadLayoutPreset.Selectable.Contains(TrackpadLayoutPreset.TouchStream),"TouchStream picker/column policy failed");
        foreach (var row in left.Rects.Concat(right.Rects)) foreach (var rect in row)
            Check(rect.Width>0 && rect.Height>0 && rect.Contains(rect.CenterX,rect.CenterY),"invalid TouchStream rotated hit region");
        foreach (var layout in new[] {left,right})
        {
            var view=new TouchView { Width=400,Height=300,Layout=layout };
            view.Measure(new(400,300)); view.Arrange(new System.Windows.Rect(0,0,400,300));
            var key=layout.Rects[0][0]; var pad=view.PadBounds;
            var point=new System.Windows.Point(pad.Left+key.CenterX*pad.Width,pad.Top+key.CenterY*pad.Height);
            Check(MainWindow.TryHitSelectionAtPoint(view,layout,[],point,out int row,out int column,out _) && row==0 && column==0,
                "visible TouchStream key center disagreed with inspector selection hit testing");
        }
        foreach (string assignment in new[] {"Ctrl+Shift+A","Hyper","RightAlt+Left","Ctrl","F12"})
        {
            var plan=WindowsGestureShortcutPlan.ForAssignment(assignment); var held=new HashSet<ushort>();
            foreach (var edge in plan) Check(edge.Up ? held.Remove(edge.Key) : held.Add(edge.Key),"custom shortcut has unbalanced edges");
            Check(plan.Length>0 && held.Count==0,"custom shortcut left keys held");
        }
        var custom=Empty(); custom.Left.Set(HandGestureTrigger.FiveFingerTap,HandGestureAction.Custom);
        custom.Left.CustomActions=new() { [nameof(HandGestureTrigger.FiveFingerTap)]="Hyper" };
        var (customEngine,customOutput)=Create(custom); Frame(customEngine,Contacts(5),1); Frame(customEngine,[],1.05);
        Check(customOutput.Assignments.SequenceEqual(new[]{"Hyper"}) && customOutput.Actions.Count==0,"custom gesture bypassed semantic assignment dispatch");
        var customBundle=AppleMagicTouchstreamProfileBundle.Create(new() { HandGesturesV1=custom },keymap);
        Check(customBundle.TryLoadPortableProfile(out var customRestored,out _,out _) && customRestored.HandGesturesV1.Left.CustomActions![nameof(HandGestureTrigger.FiveFingerTap)]=="Hyper","custom assignment did not round-trip");
        var singlePad=Empty(); singlePad.Right.Set(HandGestureTrigger.FiveFingerTap,HandGestureAction.Custom);
        singlePad.Right.CustomActions=new() { [nameof(HandGestureTrigger.FiveFingerTap)]="Hyper" };
        singlePad.Right.HoldActions=new() { [5]=HandGestureAction.Copy }; singlePad.Right.HoldThresholds=new() { [5]=800 };
        singlePad.Right.DirectionalMovement=new() { [HandGestureTrigger.TwoFingerMove]=new() { Enabled=true,Actions=new() { [HandMovementDirection.Up]=HandGestureAction.Paste } } };
        var merged=singlePad.For(TrackpadSide.Left,true);
        Check(merged.Get(HandGestureTrigger.FiveFingerTap)==HandGestureAction.Custom && merged.CustomActions![nameof(HandGestureTrigger.FiveFingerTap)]=="Hyper"
            && merged.Hold(5)==HandGestureAction.Copy && merged.HoldMilliseconds(5)==800
            && merged.Directional(HandGestureTrigger.TwoFingerMove)?.Get(HandMovementDirection.Up)==HandGestureAction.Paste,
            "same-device fallback lost new binding metadata");
        var invalidCustom=Empty(); invalidCustom.Left.Set(HandGestureTrigger.FiveFingerTap,HandGestureAction.Custom);
        var (invalidEngine,invalidOutput)=Create(invalidCustom);
        Check(!Frame(invalidEngine,Contacts(5),1),"unusable custom assignment reserved keyboard input");
        Frame(invalidEngine,[],1.05); Check(invalidOutput.Assignments.Count==0,"invalid custom assignment reached output");
        var uiSettings=new UserSettings(); var ui=new HandGesturePanel(uiSettings,()=>{});
        ui.SelectSlot(nameof(HandGestureTrigger.TwoFingerTap));
        var searchCombo=FindCombos(ui).Single(c=>Equals(c.Tag,HandGestureTrigger.TwoFingerTap));
        ui.FilterActionOptions(searchCombo,"paste");
        Check(searchCombo.Items.Count==1 && uiSettings.HandGesturesV1.Left.TwoFingerTap==HandGestureAction.PrimaryClick,
            "searching actions changed the live binding or failed to filter");
        searchCombo.SelectedIndex=0;
        Check(uiSettings.HandGesturesV1.Left.TwoFingerTap==HandGestureAction.Paste && uiSettings.HandGesturesV1.Right.TwoFingerTap==HandGestureAction.PrimaryClick,
            "choosing a search result did not respect the selected hand");
        MacGoldPreview.RenderIfRequested();
    }
    private static IEnumerable<System.Windows.Controls.ComboBox> FindCombos(object root)
    {
        if (root is System.Windows.Controls.ComboBox combo) yield return combo;
        IEnumerable<object> children=root switch
        {
            System.Windows.Controls.Panel panel=>panel.Children.Cast<object>(),
            System.Windows.Controls.ContentControl content when content.Content!=null=>[content.Content],
            System.Windows.Controls.Decorator decorator when decorator.Child!=null=>[decorator.Child],
            _=>[]
        };
        foreach (var child in children) foreach (var found in FindCombos(child)) yield return found;
    }
}
