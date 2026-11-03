using System.Text.Json;
namespace AppleMagicTouchstream;

internal static class RewriteParityTests
{
    private static void Check(bool value,string why){if(!value)throw new InvalidOperationException(why);}
    private sealed class Output:IHandGestureOutput
    {
        internal readonly List<bool> Buttons=new();internal readonly List<HandGestureAction> Clicks=new();
        internal readonly List<(double X,double Y)> Moves=new(),Scrolls=new();internal int Haptics;
        public void Move(double x,double y)=>Moves.Add((x,y));public void Scroll(double x,double y)=>Scrolls.Add((x,y));
        public void PrimaryButton(bool down)=>Buttons.Add(down);public void Tap(HandGestureAction action)=>Clicks.Add(action);
        public void Zoom(double value){}public void ForceFeedback(TrackpadSide side)=>Haptics++;
    }
    private static HandGestureContact[] Contacts(int n,double x=0,double pressure=0)=>Enumerable.Range(0,n).Select(i=>new HandGestureContact((uint)i+1,20+i*15+x,50+x,Pressure:pressure,HasPressure:pressure>0)).ToArray();
    public static void Run()
    {
        Layouts();LegacyButtons();StenoMouse();BothForce();TextReferences();Console.WriteLine("Rewrite parity: dynamic layouts, stable mirrors/layers/history, STENO force ownership, Both force and reference-only text passed.");
    }
    private static void Layouts()
    {
        var settings=new UserSettings();MacLayoutTemplates.Seed(settings);
        Check(settings.LayoutDocuments["6x3"].IsValid() && settings.LayoutDocuments["6x3"].Keys.Count==40,"Mac 6x3 template did not seed");
        foreach(var preset in WindowsInputPolicy.SelectableLayouts)
        {
            var d=MacLayoutTemplates.Get(preset);Check(d.IsValid(),"invalid template "+preset.Name);
            var clone=JsonSerializer.Deserialize<LayoutDocument>(JsonSerializer.Serialize(d,LayoutDocument.JsonOptions),LayoutDocument.JsonOptions)!;
            Check(clone.IsValid(),"document failed JSON roundtrip");
            var left=clone.Compile(false,preset.IsSteno);var right=clone.Compile(true,preset.IsSteno);
            var map=KeymapStore.LoadBundledDefault();map.SetActiveLayout(preset.Name);
            _=BindingIndex.Build(left,TrackpadSide.Left,0,map);_=BindingIndex.Build(right,TrackpadSide.Right,0,map);
        }
        var doc=new LayoutDocument();var id=doc.AddMirrored(true,1,new(.2,.2,.1,.1),"A");var key=doc.Keys.Single(k=>k.Id==id);var partner=key.MirrorID!.Value;
        var old=doc.Copy();doc.Translate(new HashSet<Guid>{id},.03,.02);doc.MirrorChanges(old,new HashSet<Guid>{id});
        var mirrored=doc.Keys.Single(k=>k.Id==partner);Check(Math.Abs(mirrored.Rect.X-(old.Keys.Single(k=>k.Id==partner).Rect.X-.03))<1e-12,"mirror does not reflect independent delta");
        Check(doc.Hit(true,0,key.Rect.CenterX,key.Rect.CenterY)==null && doc.Hit(true,1,key.Rect.CenterX,key.Rect.CenterY)==id,"layer-aware editor hit failed");
        var layout=doc.Compile(true,false);var map2=KeymapStore.LoadBundledDefault();map2.CustomButtons.Clear();
        Check(BindingIndex.Build(layout,TrackpadSide.Right,0,map2).Bindings.Length==0,"hidden key entered runtime bindings");
        Check(BindingIndex.Build(layout,TrackpadSide.Right,1,map2).Bindings.Length==1,"visible authored key not compiled");
        var history=new LayoutDocumentHistory();history.Record(old);var undo=history.Undo(doc);Check(undo.Keys.Single(k=>k.Id==id).Rect==old.Keys.Single(k=>k.Id==id).Rect,"undo geometry changed binding identity");Check(history.Redo(undo).Keys.Single(k=>k.Id==id).Rect==key.Rect,"redo failed");
        var copied=doc.Duplicate(new HashSet<Guid>{id,partner});Check(copied.Count==2 && doc.IsValid(),"duplicate broke reciprocal IDs");doc.Delete(copied);Check(doc.IsValid(),"delete broke mirrors");
        var saved=new UserSettings {LayoutDocuments=new(){{"6x3",doc}}};Check(saved.Clone().LayoutDocuments["6x3"].Keys[0]!=doc.Keys[0],"settings clone shares mutable draft");
        var bundle=AppleMagicTouchstreamProfileBundle.Create(saved,map2);Check(bundle.TryLoadPortableProfile(out var imported,out _,out _) && imported.LayoutDocuments["6x3"].IsValid(),"settings export lost document");
        var single=MacLayoutTemplates.Get(TrackpadLayoutPreset.StenoSingle);Check(single.Keys.All(k=>k.Right),"Single has left-pad keys");
        var rows=single.Compile(true,true);Check(rows.Rects[1].Length==10 && rows.Rects[2].Length==9 && rows.Rects[3].Length==4,"Single topology wrong");
        Check(Math.Abs(rows.Rects[1][0].Height*114.9-25)<1e-9,"consonant length differs from Mac");
        var rotated=KeyHitGeometry.FromPhysicalRect(new(.4,.4,10.0/160,20.0/114.9) {RotationDegrees=90});
        Check(rotated.Contains(.4+5.0/160+9.0/160,.4+10.0/114.9) && !rotated.Contains(.4+5.0/160,.4+10.0/114.9+6.0/114.9),"rotated physical hit does not match drawn millimeters");
        var bad=doc.Copy();bad.Keys[0].Rect=bad.Keys[0].Rect with {Width=double.NaN};Check(!bad.IsValid(),"invalid geometry accepted");
    }
    private static void LegacyButtons()
    {
        var map=KeymapStore.LoadBundledDefault();map.CustomButtons.Clear();
        map.CustomButtons[2]=new(){new(){Id="old-non-uuid",Side=TrackpadSide.Right,Rect=new(.1,.2,.1,.1),Primary=new(){Label="Space"},Hold=new(){Label="Shift"},HoldForceThreshold=99}};
        var doc=new LayoutDocument();doc.MigrateLegacyButtons(map);doc.MigrateLegacyButtons(map);
        Check(doc.Keys.Count==1 && doc.Keys[0].Visible(2) && !doc.Keys[0].Visible(0),"legacy migration not stable or layer-aware");
        var source=doc.Keys[0];var first=doc.Duplicate(new HashSet<Guid>{source.Id});var duplicate=doc.Duplicate(first);doc.Delete(new HashSet<Guid>(first){source.Id});doc.ApplyMappings(map);
        var target=doc.Keys.Single();var binding=map.Mappings[2][GridKeyPosition.StorageKey(TrackpadSide.Right,target.Row,target.Column)];
        Check(binding.Primary.Label=="Space" && binding.Hold?.Label=="Shift" && binding.HoldForceThreshold==99,"duplicate lost legacy hold/action after deleting source");
        Check(doc.IsValid(),"legacy migration invalid");
        binding.Primary.Label="Enter";doc.ApplyMappings(map);
        Check(map.Mappings[2][GridKeyPosition.StorageKey(TrackpadSide.Right,target.Row,target.Column)].Primary.Label=="Enter","re-applying document overwrote duplicate action edits");
        string capture=System.IO.Path.Combine(System.IO.Path.GetTempPath(),"amt-layout-"+Guid.NewGuid().ToString("N")+".atpcap");
        try {var settings=new UserSettings{LayoutDocuments=new(){{"6x3",doc}}};CaptureProfileSidecar.Write(capture,settings,map);Check(CaptureProfileSidecar.TryRead(capture,out var restored,out _) && restored.LayoutDocuments["6x3"].Keys.Single().Id==target.Id,"capture companion lost authored identity");}
        finally{System.IO.File.Delete(CaptureProfileSidecar.PathFor(capture));}
    }
    private static void StenoMouse()
    {
        var output=new Output();var e=new StenoPointerEngine(output);
        bool frame(TrackpadSide side,int count,double t,double x=0,double pressure=0)=>e.Process(side,Contacts(count,x,pressure),t,t,true);
        frame(TrackpadSide.Left,1,1);frame(TrackpadSide.Left,1,1.01,0,129);Check(output.Buttons.Count==0,"light force started drag");
        frame(TrackpadSide.Left,1,1.02,0,130);Check(output.Buttons.SequenceEqual(new[]{true}),"1F force did not hold button");
        frame(TrackpadSide.Right,2,1.03);frame(TrackpadSide.Right,2,1.04,3);Check(output.Moves.Count>0,"other pad cannot share drag cursor");
        frame(TrackpadSide.Right,1,1.05);frame(TrackpadSide.Left,0,1.06);Check(output.Buttons.SequenceEqual(new[]{true,false}),"last drag owner did not release");frame(TrackpadSide.Right,0,1.07);
        frame(TrackpadSide.Left,2,2,0,130);frame(TrackpadSide.Left,2,2.01,0,180);frame(TrackpadSide.Left,0,2.02);
        frame(TrackpadSide.Right,3,3,0,130);frame(TrackpadSide.Right,0,3.02);
        Check(output.Clicks.SequenceEqual(new[]{HandGestureAction.PrimaryClick,HandGestureAction.SecondaryClick}),"fixed force clicks mismatch");
        frame(TrackpadSide.Left,1,4,0,130);frame(TrackpadSide.Right,1,4.01,0,130);frame(TrackpadSide.Left,0,4.02);
        Check(output.Buttons.Count==3,"one drag owner released another");frame(TrackpadSide.Right,0,4.03);Check(output.Buttons.Count==4 && !output.Buttons[^1],"shared drag did not balance");
        frame(TrackpadSide.Right,4,5,0,130);int before=output.Scrolls.Count;frame(TrackpadSide.Right,1,5.01,.5);frame(TrackpadSide.Right,1,5.02,1);frame(TrackpadSide.Right,0,5.03);e.Tick(5.04,true);
        Check(output.Scrolls.Count>before+2,"latched force scroll/momentum failed");before=output.Scrolls.Count;frame(TrackpadSide.Left,1,5.05);e.Tick(5.06,true);Check(output.Scrolls.Count==before,"other pad did not brake steno momentum");frame(TrackpadSide.Left,0,5.07);
        frame(TrackpadSide.Left,2,6);frame(TrackpadSide.Right,2,6.01);frame(TrackpadSide.Left,2,6.02,4);frame(TrackpadSide.Right,2,6.03,4,130);Check(output.Clicks.Count==2,"two-hand pending chord lost steno priority");frame(TrackpadSide.Left,0,6.04);frame(TrackpadSide.Right,0,6.05);
        frame(TrackpadSide.Left,4,7);frame(TrackpadSide.Left,2,7.01,0,150);Check(output.Clicks.Count==2,"partial lift became force click");frame(TrackpadSide.Left,0,7.02);
        frame(TrackpadSide.Left,1,8,0,130);e.Tick(8.3,true);Check(!output.Buttons[^1],"stale drag retained button");
    }
    private static void BothForce()
    {
        var settings=new CoordinatedGestureSettings();settings.HoldActions[CoordinatedHandChord.OuterCorners]=HandGestureAction.None;settings.ForceActions[CoordinatedHandChord.ThreeFingers]=HandGestureAction.PrimaryClick;
        var output=new Output();var e=new CoordinatedHandGestureEngine();e.Configure(settings,true);
        e.Process(TrackpadSide.Left,[],.9,true,false,output);e.Process(TrackpadSide.Right,[],.91,true,false,output);
        e.Process(TrackpadSide.Left,Contacts(3,0,130),1,true,false,output);e.Process(TrackpadSide.Right,Contacts(3,0,130),1.1,true,false,output);
        Check(output.Clicks.Count==1 && output.Haptics==2,"Both simultaneous force failed");
        e.Process(TrackpadSide.Left,Contacts(1),1.11,true,false,output);e.Process(TrackpadSide.Right,Contacts(4,0,200),1.12,true,false,output);Check(output.Clicks.Count==1,"Both force retriggered during count change");
        e.Process(TrackpadSide.Left,[],1.13,true,false,output);e.Process(TrackpadSide.Right,[],1.14,true,false,output);
        e.Process(TrackpadSide.Left,Contacts(3,0,130),2,true,false,output);e.Process(TrackpadSide.Left,Contacts(3,0,130),2.1,true,false,output);e.Process(TrackpadSide.Left,Contacts(3,0,130),2.2,true,false,output);e.Process(TrackpadSide.Right,Contacts(3,0,130),2.21,true,false,output);
        Check(output.Clicks.Count==1,"late force joined an old high-pressure hand");
        var restored=JsonSerializer.Deserialize<CoordinatedGestureSettings>(JsonSerializer.Serialize(settings))!;Check(restored.Action(CoordinatedHandChord.ThreeFingers,false,true)==HandGestureAction.PrimaryClick,"Both force settings lost");
    }
    private static void TextReferences()
    {
        string label=TextShortcutReference.Label(Guid.NewGuid());Check(TextShortcutReference.TryRead(label,out _) && !TextShortcutReference.TryRead("TEXT_SHORTCUT:password",out _),"invalid text reference handling");
        var action=EngineActionResolver.ResolveActionLabel(label,"None");Check(action.Kind==EngineActionKind.Text && action.SemanticAction.Kind==DispatchSemanticKind.Text,"text not resolved through shared actions");
        Check(!TextShortcutReference.Valid("") && TextShortcutReference.Valid("text\n🙂") && !TextShortcutReference.Valid(new string('x',65537)),"text bounds failed");
        Check(PerHandGestureSettings.IsValidCustom(label),"gesture catalog rejects opaque text");
        var map=KeymapStore.LoadBundledDefault();map.CustomButtons.Clear();map.Mappings.Clear();
        map.Mappings[0]=new(){{GridKeyPosition.StorageKey(TrackpadSide.Left,0,0),new(){Primary=new(){Label=label}}}};
        var layout=new KeyLayout([new NormalizedRect[]{new(.2,.2,.2,.2)}],[new string[]{"None"}]);
        var core=TouchProcessorFactory.CreateDefault(map,TrackpadLayoutPreset.SixByThree);core.UseHandGestureRecognition();core.UseUnifiedInputPolicy();core.SetDiagnosticsEnabled(false);core.ConfigureLayouts(layout,layout);
        var finger=new InputFrame{ContactCount=1,Contact0=new(){Id=1,X=2284,Y=1520,Flags=3}};var up=new InputFrame();long time=System.Diagnostics.Stopwatch.GetTimestamp();
        core.ProcessFrame(TrackpadSide.Left,in finger,7612,5065,time);core.ProcessFrame(TrackpadSide.Left,in up,7612,5065,time+System.Diagnostics.Stopwatch.Frequency/20);
        var events=new DispatchEvent[32];int count=core.DrainDispatchEvents(events);var text=events.Take(count).Single(e=>e.Kind==DispatchEventKind.Text);
        Check(text.DispatchLabel.Length==0 && text.SemanticAction.Label==label,"diagnostics-off text lost its live reference");
    }
}
