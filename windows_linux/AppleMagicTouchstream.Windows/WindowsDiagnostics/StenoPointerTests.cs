using System.Diagnostics;

namespace AppleMagicTouchstream;

internal static class StenoPointerTests
{
    private sealed class Output : IHandGestureOutput
    {
        public int Moves;
        public void Move(double x,double y) { Check(double.IsFinite(x)&&double.IsFinite(y),"nonfinite pointer output"); Moves++; }
        public void Scroll(double x,double y)=>throw new InvalidOperationException("STENO scrolled");
        public void PrimaryButton(bool down)=>throw new InvalidOperationException("STENO clicked");
        public void Tap(HandGestureAction action)=>throw new InvalidOperationException("STENO tapped");
        public void Zoom(double scale)=>throw new InvalidOperationException("STENO zoomed");
        public void ForceFeedback(TrackpadSide side)=>throw new InvalidOperationException("STENO force clicked");
    }
    private static void Check(bool condition,string reason) { if(!condition) throw new InvalidOperationException(reason); }
    private static HandGestureContact[] Contacts(int count,double dx=0)=>Enumerable.Range(0,count).Select(i=>new HandGestureContact((uint)(i+1),40+20*i+dx,40)).ToArray();
    private static bool Process(StenoPointerEngine engine,HandGestureContact[] contacts,double time,bool eligible=true)=>engine.Process(TrackpadSide.Left,contacts,time,time,eligible);
    public static void Run()
    {
        foreach(int fingers in new[] { 1,2 })
        {
            var output=new Output(); var pointer=new StenoPointerEngine(output); pointer.Configure(fingers);
            Check(!Process(pointer,Contacts(fingers),1),"pointer claimed on landing");
            Check(!Process(pointer,Contacts(fingers,.4),1.02),"stationary jitter stole chord");
            Check(Process(pointer,Contacts(fingers,3),1.04) && output.Moves>0,"configured pointer did not acquire");
            int moves=output.Moves;
            Check(Process(pointer,Contacts(fingers,4),1.06) && output.Moves>moves,"pointer did not continue");
            Check(Process(pointer,[],1.08),"pointer ownership was lost before all-up");
            Check(!Process(pointer,Contacts(fingers),1.1),"new stationary chord retained pointer ownership");
            Process(pointer,[],1.12);
            // A larger chord must not turn into the pointer during partial lift.
            Process(pointer,Contacts(fingers+1),2); Process(pointer,Contacts(fingers),2.02);
            Check(!Process(pointer,Contacts(fingers,5),2.04),"partial chord lift acquired pointer"); Process(pointer,[],2.06);
            // Changing fingers mid-cycle waits for all-up.
            Process(pointer,Contacts(fingers),3); pointer.Configure(fingers==1 ? 2 : 1);
            Check(!Process(pointer,Contacts(fingers==1 ? 2 : 1,6),3.02),"setting change acquired held contacts"); Process(pointer,[],3.04);
            pointer.Configure(fingers); Process(pointer,Contacts(fingers),4);
            Check(!Process(pointer,Contacts(fingers,4),4.3),"stale cycle acquired pointer"); Process(pointer,[],4.32);
            Process(pointer,Contacts(fingers),5,false);
            Check(!Process(pointer,Contacts(fingers,5),5.02),"takeover re-enable acquired held contacts"); Process(pointer,[],5.04);
            // Ordinary translation resumes after cancelled cycle lifts.
            Process(pointer,Contacts(fingers),6); Check(Process(pointer,Contacts(fingers,3),6.02),"pointer failed after cancellation");
        }
        var recorder=new Output(); var pair=new StenoPointerEngine(recorder);
        Process(pair,Contacts(2),1);
        Check(!Process(pair,[new(1,46,40),new(2,60,40)],1.02),"one settling finger stole two-finger chord"); Process(pair,[],1.04);
        Process(pair,Contacts(2),2);
        Check(!Process(pair,[new(1,36,40),new(2,64,40)],2.02),"spread became pointer movement");
        Check(recorder.Moves==0,"unclaimed pair generated pointer output");
        var settings=new UserSettings { StenoPointerFingerCount=1 };
        Check(settings.Clone().StenoPointerFingerCount==1,"pointer preference lost during clone");
        var bundle=AppleMagicTouchstreamProfileBundle.Create(settings,KeymapStore.LoadBundledDefault());
        Check(bundle.TryLoadPortableProfile(out var imported,out _,out _) && imported.StenoPointerFingerCount==1,"pointer preference lost during export/import");
        settings.StenoPointerFingerCount=9; settings.NormalizeRanges(); Check(settings.StenoPointerFingerCount==2,"invalid pointer preference accepted");
        RunActor(1); RunActor(2);
    }
    private sealed class Runtime : IHandGestureRuntime
    {
        private readonly StenoPointerEngine _pointer;
        public Runtime(int fingers) { _pointer=new(new Output()); _pointer.Configure(fingers); }
        public bool Process(TrackpadSide side,in InputFrame frame,ushort x,ushort y,long timestamp)=>throw new InvalidOperationException("STENO entered ordinary gestures");
        public bool ProcessStenoPointer(TrackpadSide side,in InputFrame frame,ushort x,ushort y,long timestamp)
        {
            Span<HandGestureContact> contacts=stackalloc HandGestureContact[InputFrame.MaxContacts];
            int count=WindowsHandGestures.ReadContacts(in frame,x,y,contacts,out _);
            double time=timestamp/(double)Stopwatch.Frequency;
            return _pointer.Process(side,contacts[..count],time,time,true);
        }
        public void Tick() { }
        public void Dispose() { }
    }
    private static void RunActor(int fingers)
    {
        var map=KeymapStore.LoadBundledDefault(); map.SetActiveLayout(TrackpadLayoutPreset.Steno.Name);
        var core=TouchProcessorFactory.CreateDefault(map,TrackpadLayoutPreset.Steno); core.UseUnifiedInputPolicy();
        using var queue=new DispatchEventQueue(); using var actor=new TouchProcessorActor(core,dispatchQueue:queue,handGestures:new Runtime(fingers));
        InputFrame frame(int n,int dx=0)=>new() { ContactCount=(byte)n,
            Contact0=new() { Id=1,X=(ushort)(2300+dx),Y=1500,Flags=(byte)(n>0 ? 3 : 0) },
            Contact1=new() { Id=2,X=(ushort)(3300+dx),Y=1500,Flags=(byte)(n>1 ? 3 : 0) } };
        void post(TrackpadSide side,InputFrame payload,double time) { actor.Post(side,in payload,7612,5065,(long)(time*Stopwatch.Frequency)); Check(actor.WaitForIdle(),"actor did not drain"); }
        // A pointer on one pad cancels the entire two-hand chord, including
        // the other pad's later release. No mouse frames may reach Plover.
        post(TrackpadSide.Right,frame(1),1); post(TrackpadSide.Left,frame(fingers),1.02);
        post(TrackpadSide.Left,frame(fingers,180),1.04); post(TrackpadSide.Left,frame(0),1.06);
        post(TrackpadSide.Right,frame(0),1.08);
        Check(!queue.TryDequeue(out _,0),"pointer movement leaked a steno stroke");
        // A stationary single-finger stroke stays valid in either mode.
        post(TrackpadSide.Left,frame(1),2); post(TrackpadSide.Left,frame(0),2.05);
        Check(queue.TryDequeue(out var stroke,0) && stroke.Kind==DispatchEventKind.StenoStroke,"stationary one-finger stroke was lost");
        Check(!queue.TryDequeue(out _,0),"stationary stroke emitted twice");
    }
}
