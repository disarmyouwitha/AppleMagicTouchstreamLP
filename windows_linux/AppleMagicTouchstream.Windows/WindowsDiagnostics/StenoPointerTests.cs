using System.Diagnostics;
namespace AppleMagicTouchstream;

// Actor integration: mouse wins cancel the whole pending chord and remain
// cancelled through both-pad all-up. No devices, native hooks or output.
internal static class StenoPointerTests
{
    private static void Check(bool condition,string message){if(!condition)throw new InvalidOperationException(message);}
    private sealed class Output:IHandGestureOutput
    {
        internal readonly List<bool> Buttons=new();internal int Clicks,Moves;
        public void Move(double x,double y){Check(double.IsFinite(x)&&double.IsFinite(y),"nonfinite pointer");Moves++;}
        public void Scroll(double x,double y){}public void PrimaryButton(bool down)=>Buttons.Add(down);
        public void Tap(HandGestureAction action){Check(action==HandGestureAction.PrimaryClick,"unexpected force click");Clicks++;}
        public void Zoom(double value){}public void ForceFeedback(TrackpadSide side){}
    }
    private sealed class Runtime:IHandGestureRuntime
    {
        private readonly StenoPointerEngine _pointer;internal readonly Output Output=new();
        internal Runtime(){_pointer=new(Output);_pointer.Configure(2);}
        public bool Process(TrackpadSide side,in InputFrame frame,ushort x,ushort y,long timestamp)=>throw new InvalidOperationException("STENO entered ordinary recognition");
        public bool ProcessStenoPointer(TrackpadSide side,in InputFrame frame,ushort x,ushort y,long timestamp)
        {
            Span<HandGestureContact> contacts=stackalloc HandGestureContact[InputFrame.MaxContacts];int count=WindowsHandGestures.ReadContacts(in frame,x,y,contacts,out _);double time=timestamp/(double)Stopwatch.Frequency;
            return _pointer.Process(side,contacts[..count],time,time,true);
        }
        public void Tick(){}public void Dispose(){}
    }
    internal static void Run()
    {
        var map=KeymapStore.LoadBundledDefault();var preset=TrackpadLayoutPreset.Steno;map.SetActiveLayout(preset.Name);
        var layout=StenoLayoutDefinition.Build(preset,true,[],map,0);var target=layout.Rects[1][1];
        var core=TouchProcessorFactory.CreateDefault(map,preset);core.UseUnifiedInputPolicy();
        using var queue=new DispatchEventQueue();var runtime=new Runtime();using var actor=new TouchProcessorActor(core,dispatchQueue:queue,handGestures:runtime);
        InputFrame Frame(int n,int delta=0,int force=0)
        {
            var frame=new InputFrame {ContactCount=(byte)n};for(int i=0;i<n;i++)frame.SetContact(i,new() {Id=(uint)i+1,X=(ushort)(target.CenterX*7612+delta+i*300),Y=(ushort)(target.CenterY*5065),Flags=3,Pressure=(byte)force,HasForceData=force>0});return frame;
        }
        void Post(TrackpadSide side,InputFrame frame,double time){actor.Post(side,in frame,7612,5065,(long)(time*Stopwatch.Frequency));Check(actor.WaitForIdle(),"actor did not drain");}
        Post(TrackpadSide.Left,Frame(2),1);Post(TrackpadSide.Left,Frame(2,180),1.02);Post(TrackpadSide.Right,Frame(1),1.03);Post(TrackpadSide.Right,Frame(0),1.04);Post(TrackpadSide.Left,Frame(0),1.05);
        Check(runtime.Output.Moves>0 && !queue.TryDequeue(out _,0),"mouse acquisition leaked a chord");
        Post(TrackpadSide.Left,Frame(1),2);Post(TrackpadSide.Left,Frame(0),2.05);
        Check(queue.TryDequeue(out var stroke,0) && stroke.Kind==DispatchEventKind.StenoStroke,"fresh stationary stroke lost");Check(!queue.TryDequeue(out _,0),"stationary stroke duplicated");
        Post(TrackpadSide.Left,Frame(1,force:130),3);Post(TrackpadSide.Right,Frame(2),3.01);Post(TrackpadSide.Right,Frame(2,180),3.02);Post(TrackpadSide.Left,Frame(0),3.03);Post(TrackpadSide.Right,Frame(0),3.04);
        Check(runtime.Output.Buttons.SequenceEqual(new[]{true,false}) && !queue.TryDequeue(out _,0),"force drag was unbalanced or emitted steno");
        Post(TrackpadSide.Right,Frame(2,force:130),4);Post(TrackpadSide.Right,Frame(0),4.05);Check(runtime.Output.Clicks==1 && !queue.TryDequeue(out _,0),"2F force did not cancel stroke");
        Post(TrackpadSide.Left,Frame(1),5);Post(TrackpadSide.Right,Frame(1),5.01);Post(TrackpadSide.Left,Frame(1,force:130),5.02);Post(TrackpadSide.Left,Frame(0),5.04);Post(TrackpadSide.Right,Frame(0),5.05);
        Check(queue.TryDequeue(out stroke,0) && stroke.Kind==DispatchEventKind.StenoStroke && runtime.Output.Buttons.Count==2,"pending two-hand chord lost priority to force");
    }
}
