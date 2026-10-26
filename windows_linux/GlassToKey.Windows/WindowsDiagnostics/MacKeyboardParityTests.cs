using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
namespace GlassToKey;

// Deterministic engine/dispatcher contracts. No hooks, devices or native output.
internal static class MacKeyboardParityTests
{
    private static void Check(bool pass,string message) { if(!pass) throw new InvalidOperationException(message); }
    private static long At(double time)=>(long)(time*Stopwatch.Frequency);
    private sealed class Output : IHandGestureOutput
    {
        public readonly List<(int Owner,string? Label)> Held=[];
        public readonly List<string> Assigned=[];
        public int Moves,Taps;
        public void HeldAssignment(int owner,string? label)=>Held.Add((owner,label));
        public void AssignedAction(string label)=>Assigned.Add(label);
        public void Move(double x,double y)=>Moves++;
        public void Tap(HandGestureAction action) { if(action!=HandGestureAction.None) Taps++; }
        public void Scroll(double x,double y) { }
        public void PrimaryButton(bool down) { }
        public void Zoom(double delta) { }
        public void ForceFeedback(TrackpadSide side) { }
    }
    private sealed class Runtime : IHandGestureRuntime
    {
        public readonly Output Output=new();
        public readonly HandGestureEngine Engine;
        private readonly bool[] _priority=new bool[2];
        public bool Enabled=true;
        public bool SupportsKeyboardProposals=>true;
        public Runtime(HandGestureSettings settings) { Engine=new(Output); Engine.Configure(settings,false); }
        public void SetKeyboardPriority(TrackpadSide side,bool priority)=>_priority[(int)side]=priority;
        public HandGestureEvidence Evidence(TrackpadSide side)=>Engine.Evidence(side);
        public bool Process(TrackpadSide side,in InputFrame frame,ushort maxX,ushort maxY,long time)
        {
            Span<HandGestureContact> contacts=stackalloc HandGestureContact[InputFrame.MaxContacts]; int count=0;
            for(int i=0;i<frame.GetClampedContactCount();i++) { var c=frame.GetContact(i); if(c.TipSwitch) contacts[count++]=new(c.Id,c.X*160.0/maxX,c.Y*114.9/maxY); }
            return Engine.Process(side,contacts[..count],time/(double)Stopwatch.Frequency,time/(double)Stopwatch.Frequency,Enabled,keyboardPriority:_priority[(int)side]);
        }
        public void Tick() { }
        public void Cancel(TrackpadSide? side=null) { if(side is {} pad) Engine.Cancel(pad); else Engine.Reset(); }
        public void Dispose()=>Engine.Reset();
    }
    private static HandGestureSettings Empty()
    {
        var settings=new HandGestureSettings();
        foreach(var hand in new[] {settings.Left,settings.Right})
        { foreach(var t in Enum.GetValues<HandGestureTrigger>()) hand.Set(t,HandGestureAction.None); hand.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.None }; }
        settings.Coordinated.HoldActions[CoordinatedHandChord.OuterCorners]=HandGestureAction.None; return settings;
    }
    private sealed class Harness
    {
        public readonly KeymapStore Map=KeymapStore.LoadBundledDefault();
        public readonly KeyLayout Left,Right;
        public readonly TouchProcessorCore Core;
        public readonly Runtime Runtime;
        public readonly GestureKeyboardArbiter Arbiter;
        public Harness(HandGestureSettings gestures,string primary="A",string? hold=null)
        {
            var preset=TrackpadLayoutPreset.SixByThree;
            Left=LayoutBuilder.BuildLayout(preset,160,114.9,18,17,ColumnLayoutDefaults.DefaultSettings(6),true);
            Right=LayoutBuilder.BuildLayout(preset,160,114.9,18,17,ColumnLayoutDefaults.DefaultSettings(6),false);
            Map.Mappings[0][GridKeyPosition.StorageKey(TrackpadSide.Left,0,1)]=new() { Primary=new() { Label=primary },Hold=hold==null ? null : new() { Label=hold } };
            Map.Mappings[0][GridKeyPosition.StorageKey(TrackpadSide.Left,0,2)]=new() { Primary=new() { Label="B" } };
            Map.Mappings[0][GridKeyPosition.StorageKey(TrackpadSide.Right,0,1)]=new() { Primary=new() { Label="Shift" } };
            Core=TouchProcessorFactory.CreateDefault(Map,preset,TouchProcessorConfig.Default with { HoldDurationMs=200,DragCancelMm=.1,TypingGraceMs=9000,IntentMoveMm=.01,IntentVelocityMmPerSec=.01 });
            Core.UseHandGestureRecognition(); Core.UseUnifiedInputPolicy(); Runtime=new(gestures); Arbiter=new(Core,Runtime);
            Frame(0,.9); Frame(0,.901,TrackpadSide.Right);
        }
        public InputFrame Payload(int count,double dx=0,TrackpadSide side=TrackpadSide.Left)
        {
            var frame=new InputFrame { ContactCount=(byte)count }; var layout=side==TrackpadSide.Left ? Left : Right;
            for(int i=0;i<count;i++) { var key=layout.Rects[0][i+1]; frame.SetContact(i,new((uint)i+1,(ushort)((key.CenterX+dx/160)*7612),(ushort)(key.CenterY*5065),3)); }
            return frame;
        }
        public void Frame(int count,double time,TrackpadSide side=TrackpadSide.Left,double dx=0)
        { var frame=Payload(count,dx,side); Arbiter.Process(side,in frame,7612,5065,At(time)); }
        public DispatchEvent[] Drain() { var events=new DispatchEvent[128]; int count=Core.DrainDispatchEvents(events); return events[..count]; }
    }
    public static void Run()
    {
        Arbitration(); HeldRecognition(); SharedOutput(); DirectPublication();
        var settings=Empty(); settings.Left.HeldShortcuts.Add("Hold2"); settings.Left.HoldActions=new() { [2]=HandGestureAction.Custom }; settings.Left.CustomActions=new() { ["Hold2"]="Hyper" };
        settings.Coordinated.HeldShortcuts.Add("OuterCorners/Hold"); settings.Coordinated.CustomActions["OuterCorners/Hold"]="Ctrl+A";
        settings.Coordinated.HoldActions[CoordinatedHandChord.OuterCorners]=HandGestureAction.Custom;
        var restored=JsonSerializer.Deserialize<HandGestureSettings>(JsonSerializer.Serialize(settings))!.Clone();
        Check(restored.Left.HeldShortcuts.Contains("Hold2") && restored.Coordinated.HeldShortcuts.Contains("OuterCorners/Hold"),"held shortcut settings did not round-trip");
        restored.Left.HeldShortcuts.Clear(); Check(settings.Left.HeldShortcuts.Count==1,"held shortcut clone shared a mutable set");
        string? built=null; var editor=new GestureActionEditor("RightAlt+Left",value=>built=value);
        HandGestureTests.Controls<System.Windows.Controls.Button>(editor).Single(b=>Equals(b.Content,"Apply")).RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        Check(built!=null && DispatchShortcutHelper.TryReadShortcut(built,out var modifiers,out string key) && modifiers==DispatchModifierFlags.RightAlt && key=="Left","inline builder lost right-side modifier semantics");
    }
    private static void Arbitration()
    {
        var settings=Empty(); settings.Left.TwoFingerMove=HandGestureAction.Pointer;
        var h=new Harness(settings); h.Frame(2,1); Check(h.Drain().Length==0,"unresolved proposal typed early");
        h.Frame(1,1.04); h.Frame(1,1.06,dx:2); h.Frame(0,1.08);
        var events=h.Drain(); Check(events.Count(e=>e.Kind==DispatchEventKind.KeyTap)==2,"never-activated rollover did not resolve to typing");
        Check(h.Runtime.Output.Moves==0,"typing rollover resurrected gesture motion");

        h=new(settings); h.Frame(2,1); h.Frame(2,1.02,dx:1); h.Frame(0,1.04);
        Check(h.Runtime.Output.Moves>0 && h.Drain().Length==0,"winning movement replayed discarded keyboard proposals");

        settings=Empty(); settings.Left.TwoFingerTap=HandGestureAction.PrimaryClick;
        h=new(settings); h.Frame(2,1); h.Frame(0,1.04);
        Check(h.Runtime.Output.Taps==1 && h.Drain().Length==0,"terminal gesture tap also emitted keyboard taps");

        settings=Empty(); settings.Left.TwoFingerMove=HandGestureAction.Pointer;
        h=new(settings,"Hyper"); h.Frame(1,1); h.Frame(2,1.02); h.Frame(2,1.04,dx:1); h.Frame(0,1.06);
        events=h.Drain(); Check(h.Runtime.Output.Moves==0 && events.Count(e=>e.Kind==DispatchEventKind.ModifierDown)==1
            && events.Count(e=>e.Kind==DispatchEventKind.ModifierUp)==1,"established Hyper lost same-pad keyboard priority");

        h=new(settings,"A","Hyper"); h.Frame(1,1);
        for(int i=1;i<=5;i++) h.Frame(1,1+i*.05);
        h.Frame(2,1.27,dx:1); h.Frame(0,1.3);
        Check(h.Runtime.Output.Moves==0 && h.Drain().Any(e=>e.Kind==DispatchEventKind.ModifierDown),"committed key Hold did not retain keyboard priority");

        h=new(settings,"MO(1)"); h.Frame(1,1); h.Frame(2,1.02,dx:1); h.Frame(0,1.04);
        Check(h.Runtime.Output.Moves==0 && !h.Core.Snapshot(At(1.05)).MomentaryLayerActive,"MO chord was stolen or left active");

        foreach(int invalidation in Enumerable.Range(0,4))
        {
            h=new(settings); h.Frame(2,1);
            if(invalidation==0) h.Core.SetPersistentLayer(1);
            if(invalidation==1) h.Core.ResetState();
            if(invalidation==2) h.Runtime.Engine.Configure(settings,false);
            if(invalidation==3) h.Arbiter.Tick(At(1.2));
            h.Frame(0,invalidation==3 ? 1.21 : 1.05);
            Check(h.Drain().Length==0,"invalid/stale proposal fell back to typing: "+invalidation);
        }
        h=new(settings); h.Frame(2,1);
        for(int i=1;i<=GestureKeyboardArbiter.Capacity;i++) h.Frame(2,1+i*.001);
        h.Frame(0,2.04); Check(h.Drain().Length==0,"proposal overflow emitted stale keyboard actions");
        h=new(settings); h.Frame(2,1); var duplicate=h.Payload(2); duplicate.SetContact(1,duplicate.GetContact(0));
        h.Arbiter.Process(TrackpadSide.Left,in duplicate,7612,5065,At(1.02)); h.Frame(0,1.04);
        Check(h.Drain().Length==0,"duplicate IDs escaped proposal cancellation");

        // Preserve the modifier state at an earlier partial lift when replay is
        // delayed by a viable tap, and the other pad releases its Shift meanwhile.
        settings=Empty(); settings.Left.TwoFingerTap=HandGestureAction.PrimaryClick;
        h=new(settings); h.Frame(1,.99,TrackpadSide.Right); h.Frame(2,1.01); h.Frame(1,1.04);
        h.Frame(0,1.06,TrackpadSide.Right); h.Frame(1,1.09); h.Frame(1,1.13); h.Frame(0,1.14);
        events=h.Drain(); Check(events.Any(e=>e.Kind==DispatchEventKind.KeyTap && e.SemanticAction.Label=="B" && (e.SemanticAction.Modifiers&DispatchModifierFlags.Shift)!=0),
            "deferred partial-lift tap lost its original other-pad modifier snapshot");

        // Retired movement/grace values cannot turn unreserved Windows typing
        // into mouse intent or suppress an in-key tap after a small excursion.
        h=new(Empty()); h.Frame(1,1); h.Frame(1,1.04,dx:3); h.Frame(0,1.08);
        Check(h.Drain().Count(e=>e.Kind==DispatchEventKind.KeyTap)==1,"retired drag/intent gates still suppress typing");
        h.Frame(0,1.09); Check(h.Core.Snapshot(At(1.09)).IntentMode==IntentMode.Idle,"retired typing grace remains active");
        h=new(Empty()); h.Frame(1,1); h.Frame(1,1.1); h.Frame(1,1.2); h.Frame(0,1.25);
        Check(h.Drain().Length==0,"timed-out unassigned Hold became a late tap");
    }
    private static void HeldRecognition()
    {
        foreach(bool both in new[] {false,true})
        {
            var settings=Empty();
            if(both)
            { settings.Coordinated.HoldActions[CoordinatedHandChord.ThreeFingers]=HandGestureAction.Custom; settings.Coordinated.CustomActions["ThreeFingers/Hold"]="Hyper"; settings.Coordinated.HeldShortcuts.Add("ThreeFingers/Hold"); }
            else { settings.Left.HoldActions=new() { [2]=HandGestureAction.Custom }; settings.Left.CustomActions=new() { ["Hold2"]="Hyper" }; settings.Left.HeldShortcuts.Add("Hold2"); }
            var h=new Harness(settings); h.Runtime.Output.Held.Clear();
            for(int i=0;i<=11;i++) { h.Frame(both ? 3 : 2,1+i*.05); if(both) h.Frame(3,1.001+i*.05,TrackpadSide.Right); }
            int owner=both ? 2 : 0;
            Check(h.Runtime.Output.Held.Count(e=>e.Owner==owner && e.Label=="Hyper")==1,"gesture Hold did not acquire its keys once");
            h.Frame(0,1.6); if(both) { Check(h.Runtime.Output.Held.Last(e=>e.Owner==2).Label=="Hyper","Both Hold released while the other hand remained down"); h.Frame(0,1.61,TrackpadSide.Right); }
            Check(h.Runtime.Output.Held.Last(e=>e.Owner==owner).Label==null,"gesture Hold did not release on all-up");
        }
        var held=Empty(); held.Left.HoldActions=new() { [2]=HandGestureAction.Custom }; held.Left.CustomActions=new() { ["Hold2"]="Ctrl+A" }; held.Left.HeldShortcuts.Add("Hold2");
        foreach(bool stale in new[] {false,true})
        {
            var h=new Harness(held); for(int i=0;i<=11;i++) h.Frame(2,1+i*.05);
            if(stale) h.Runtime.Engine.Tick(1.8,true); else h.Runtime.Engine.Configure(held,false);
            Check(h.Runtime.Output.Held.Last(e=>e.Owner==0).Label==null,"stale/configuration change left gesture keys held");
        }
    }
    private static void SharedOutput()
    {
        using var queue=new DispatchEventQueue(); using var output=new SendInputDispatcher(); output.SetPhysicalOutputSuppressed(true);
        var edges=new List<(ushort Key,bool Up)>(); output.KeyEdgeObserver=(key,up)=>edges.Add((key,up));
        bool eligible=true; var session=new WindowsGestureKeyboardSession(queue,output,()=>eligible); session.Heartbeat();
        var counts=(int[])typeof(SendInputDispatcher).GetField("_modifierRefCounts",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(output)!;
        void Drain() { while(queue.TryDequeue(out var e,0)) output.Dispatch(e); }
        void Modifier(bool down,string label)
        { var action=EngineActionResolver.ResolveActionLabel(label).SemanticAction; output.Dispatch(new(Stopwatch.GetTimestamp(),down ? DispatchEventKind.ModifierDown : DispatchEventKind.ModifierUp,0,DispatchMouseButton.None,0,DispatchEventFlags.None,TrackpadSide.Right,label,action)); }
        session.SetHeld(0,"Hyper"); Drain(); Modifier(true,"Ctrl"); session.SetHeld(1,"Ctrl+A"); Drain(); session.SetHeld(0,null); Drain(); Modifier(false,"Ctrl");
        Check(counts[0x11]==1 && !edges.Any(e=>e.Key==0x11 && e.Up),"a gesture released another owner's Ctrl");
        session.SetHeld(1,null); Drain(); Check(counts.All(c=>c==0) && edges.Count(e=>e.Key==0x11 && e.Up)==1,"final owner did not release shared modifiers once");
        session.SetHeld(0,"Ctrl"); Drain(); bool failRelease=true;
        output.KeyEdgeObserver=(key,up)=> { if(key==0x11 && up && failRelease) { failRelease=false; throw new InvalidOperationException("injected output failure"); } };
        session.SetHeld(0,null); try { Drain(); } catch(InvalidOperationException) { }
        output.Tick(Stopwatch.GetTimestamp()); Check(counts[0x11]==0,"failed gesture release was not retried on the output pump");
        bool reported=false; try { session.ThrowIfFaulted(); } catch(InvalidOperationException) { reported=true; }
        Check(reported,"keyboard output fault did not reach the live gesture fault boundary");
        output.KeyEdgeObserver=(key,up)=>edges.Add((key,up));
        foreach(bool keyboardFirst in new[] {false,true})
        {
            edges.Clear(); var semantic=EngineActionResolver.ResolveActionLabel("A").SemanticAction;
            void Key(bool down)=>output.Dispatch(new(Stopwatch.GetTimestamp(),down ? DispatchEventKind.KeyDown : DispatchEventKind.KeyUp,0x41,DispatchMouseButton.None,42,DispatchEventFlags.None,TrackpadSide.Right,"A",semantic));
            if(keyboardFirst) Key(true); session.SetHeld(0,"A"); Drain(); if(!keyboardFirst) Key(true);
            if(keyboardFirst) { Key(false); session.SetHeld(0,null); Drain(); } else { session.SetHeld(0,null); Drain(); Key(false); }
            Check(edges.SequenceEqual(new[] {((ushort)0x41,false),((ushort)0x41,true)}),"plain held key owners did not share key-down/up");
        }
        edges.Clear(); var a=EngineActionResolver.ResolveActionLabel("A").SemanticAction;
        void KeyboardOwner(bool down,ulong token)=>output.Dispatch(new(Stopwatch.GetTimestamp(),down ? DispatchEventKind.KeyDown : DispatchEventKind.KeyUp,0x41,DispatchMouseButton.None,token,DispatchEventFlags.None,TrackpadSide.Left,"A",a));
        KeyboardOwner(true,41); KeyboardOwner(true,42); KeyboardOwner(false,41);
        Check(edges.Count==1,"one keyboard owner released another keyboard owner's held key"); KeyboardOwner(false,42);
        Check(edges.SequenceEqual(new[] {((ushort)0x41,false),((ushort)0x41,true)}),"two keyboard owners did not balance their key");
        edges.Clear(); output.PhysicalKeyProbe=key=>key==0x11; session.SetHeld(0,"Ctrl"); Drain(); session.SetHeld(0,null); Drain();
        Check(edges.Count==0,"borrowed physical Ctrl was synthesized or released"); output.PhysicalKeyProbe=null;
        session.SetHeld(0,"Hyper"); session.ReleaseAll(); Drain(); output.Tick(Stopwatch.GetTimestamp());
        Check(counts.All(c=>c==0),"queued stale acquisition survived generation invalidation");
        session.SetHeld(0,"Hyper"); Drain(); Modifier(true,"Shift"); eligible=false; output.Tick(Stopwatch.GetTimestamp());
        Check(counts[0x10]==1 && counts[0x11]==0 && counts[0x12]==0 && counts[0x5B]==0,"eligibility cleanup released keyboard-owned Shift or retained gesture keys");
        Modifier(false,"Shift"); Check(counts.All(c=>c==0),"output cleanup left modifiers stuck");
    }
    private sealed class Sink : IEngineDispatchSink
    {
        public readonly List<DispatchEvent> Events=[];
        public bool TryPublish(in DispatchEvent e) { Events.Add(e); return true; }
    }
    private static void DirectPublication()
    {
        var settings=Empty(); settings.Left.TwoFingerMove=HandGestureAction.Pointer;
        var h=new Harness(settings); var sink=new Sink(); h.Core.SetDispatchSink(sink);
        for(int i=0;i<600;i++)
        {
            var frame=h.Payload(2); var contact=frame.GetContact(1); frame.SetContact(1,new((uint)i+2,contact.X,contact.Y,3));
            h.Arbiter.Process(TrackpadSide.Left,in frame,7612,5065,At(1+i*.001));
        }
        h.Frame(0,1.61);
        Check(sink.Events.Count(e=>e.Kind==DispatchEventKind.KeyTap)==600 && h.Drain().Length==0,
            "live event publication still depended on the 512-event diagnostic ring");
        h.Core.SetDispatchSink(null);

        h=new Harness(settings);
        using(var queue=new DispatchEventQueue(64))
        using(var actor=new TouchProcessorActor(h.Core,dispatchQueue:queue,handGestures:h.Runtime))
        {
            long start=Stopwatch.GetTimestamp();
            for(int i=0;i<600;i++)
            {
                var frame=h.Payload(2); var contact=frame.GetContact(1); frame.SetContact(1,new((uint)i+2,contact.X,contact.Y,3));
                Check(actor.Post(TrackpadSide.Left,in frame,7612,5065,start+i),"actor unexpectedly overflowed before publication test");
            }
            var up=new InputFrame(); actor.Post(TrackpadSide.Left,in up,7612,5065,start+601);
            Check(actor.WaitForIdle(5000),"publication overflow test did not finish");
            var events=new List<DispatchEvent>(); while(queue.TryDequeue(out var e,0)) events.Add(e);
            Check(queue.Drops>0 && events.Any(e=>e.Kind==DispatchEventKind.ReleaseAllKeyboard) && actor.Snapshot().TouchStateCount==0,
                "output queue overflow did not cancel publication and enqueue cleanup");
        }
        h=new Harness(settings);
        using(var queue=new DispatchEventQueue())
        using(var actor=new TouchProcessorActor(h.Core,dispatchQueue:queue,handGestures:h.Runtime))
        {
            long now=Stopwatch.GetTimestamp(); var right=h.Payload(1,side:TrackpadSide.Right); var stale=h.Payload(1);
            actor.Post(TrackpadSide.Right,in right,7612,5065,now);
            actor.Post(TrackpadSide.Left,in stale,7612,5065,now-Stopwatch.Frequency/2);
            Check(actor.WaitForIdle(5000),"stale-frame actor test did not finish");
            Check(actor.Snapshot().MomentaryLayerActive==false && h.Core.KeyboardChordOwnsCycle(TrackpadSide.Right),"stale left input cancelled a healthy right keyboard chord");
            var up=new InputFrame(); actor.Post(TrackpadSide.Left,in up,7612,5065,Stopwatch.GetTimestamp()); actor.Post(TrackpadSide.Right,in up,7612,5065,Stopwatch.GetTimestamp()+1);
            Check(actor.WaitForIdle(5000),"stale-frame cleanup did not finish");
            var events=new List<DispatchEvent>(); while(queue.TryDequeue(out var e,0)) events.Add(e);
            Check(events.Count(e=>e.Kind==DispatchEventKind.ModifierDown)==1 && events.Count(e=>e.Kind==DispatchEventKind.ModifierUp)==1
                && events.All(e=>e.Kind!=DispatchEventKind.KeyTap),"stale input emitted typing or lost independent modifier cleanup");
        }
    }
}
