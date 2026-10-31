using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Text;

namespace AppleMagicTouchstream;

// Pure engine/recording tests plus a private ephemeral loopback socket. Never
// opens the live Plover endpoint, hooks devices or injects keyboard input.
internal static class StenoTests
{
    private static void Check(bool value,string message) { if(!value) throw new InvalidOperationException(message); }
    private static long At(double time)=>(long)(time*Stopwatch.Frequency);
    private static ulong Bit(StenoKey key)=>1UL<<(int)key;
    private static InputFrame Point(double x,double y,uint id=1)
    {
        var frame=new InputFrame { ContactCount=1 };
        frame.SetContact(0,new(id,(ushort)Math.Round(x*7612),(ushort)Math.Round(y*5065),3)); return frame;
    }
    private static InputFrame Contact(TrackpadLayoutPreset preset,TrackpadSide side,StenoKey key)
    {
        var layout=LayoutBuilder.BuildLayout(preset,160,114.9,18,17,ColumnLayoutDefaults.DefaultSettings(6),side==TrackpadSide.Left);
        for(int r=0;r<layout.Labels.Length;r++) for(int c=0;c<layout.Labels[r].Length;c++)
            if(layout.Labels[r][c]==GeminiPRPacket.Label(key)) return Point(layout.Rects[r][c].CenterX,layout.Rects[r][c].CenterY);
        throw new InvalidOperationException("Missing steno key: "+key);
    }
    private static void Frame(TouchProcessorCore core,TrackpadSide side,in InputFrame frame,double time)=>core.ProcessFrame(side,in frame,7612,5065,At(time));
    private static DispatchEvent[] Drain(TouchProcessorCore core)
    { var buffer=new DispatchEvent[128]; return buffer[..core.DrainDispatchEvents(buffer)]; }
    private static TouchProcessorCore Core(TrackpadLayoutPreset preset,out KeymapStore map)
    {
        map=KeymapStore.LoadBundledDefault(); map.SetActiveLayout(preset.Name);
        var core=TouchProcessorFactory.CreateDefault(map,preset); core.UseHandGestureRecognition(); core.UseUnifiedInputPolicy(); core.SetDiagnosticsEnabled(true);
        return core;
    }
    public static void Run()
    {
        Span<byte> bytes=stackalloc byte[6];
        foreach(var (key,expected) in new[] {
            (StenoKey.Fn,"C00000000000"),(StenoKey.S1,"804000000000"),(StenoKey.TL,"801000000000"),
            (StenoKey.A,"800020000000"),(StenoKey.E,"800000080000"),(StenoKey.ZR,"800000000001") })
        { GeminiPRPacket.Write(Bit(key),bytes); Check(Convert.ToHexString(bytes)==expected,"Gemini PR wire vector: "+key); }
        GeminiPRPacket.Write(GeminiPRPacket.KeyMask,bytes); Check(Convert.ToHexString(bytes)=="FF7F7F7F7F7F","Gemini PR full mask");
        foreach(var key in Enum.GetValues<StenoKey>())
        {
            Check(GeminiPRPacket.TryResolve(GeminiPRPacket.Label(key),out var resolved) && key==resolved,"steno action identity failed");
            GeminiPRPacket.Write(Bit(key),bytes);
            Check(bytes.ToArray().Sum(b=>System.Numerics.BitOperations.PopCount((uint)b))==2,"wire key occupied the wrong number of bits");
        }
        Check(GeminiPRPacket.Label(StenoKey.Fn)=="STN_FN" && !GeminiPRPacket.TryResolve("STN_42",out _),"invalid steno action accepted");

        foreach(var preset in new[] { TrackpadLayoutPreset.Steno,TrackpadLayoutPreset.StenoVoyager })
        {
            Check(WindowsInputPolicy.SelectableLayouts.Contains(preset) && TrackpadLayoutPreset.ResolveByNameOrDefault(preset.Name)==preset,"steno preset is unavailable");
            var core=Core(preset,out var map);
            foreach(var side in new[] { TrackpadSide.Left,TrackpadSide.Right })
            {
                var layout=LayoutBuilder.BuildLayout(preset,160,114.9,18,17,ColumnLayoutDefaults.DefaultSettings(6),side==TrackpadSide.Left);
                Check(layout.IsSteno && layout.Rects.Length==4,"steno layout shape changed");
                for(int r=0;r<layout.Rects.Length;r++)
                { Check(layout.Rects[r].Length==layout.Labels[r].Length,"steno labels and geometry diverged");
                  foreach(var rect in layout.Rects[r]) Check(rect.X>=0 && rect.Y>=0 && rect.X+rect.Width<=1.001 && rect.Y+rect.Height<=1.001,"steno key is outside pad"); }
            }
            var left=Contact(preset,TrackpadSide.Left,StenoKey.TL); var right=Contact(preset,TrackpadSide.Right,StenoKey.FR); var up=new InputFrame();
            Frame(core,TrackpadSide.Left,left,1); Frame(core,TrackpadSide.Right,right,1.05); Frame(core,TrackpadSide.Left,up,1.1);
            Check(Drain(core).Length==0,"steno emitted before both pads lifted");
            Frame(core,TrackpadSide.Right,up,1.15); var events=Drain(core);
            Check(events.Length==1 && events[0].Kind==DispatchEventKind.StenoStroke && events[0].StenoMask==(Bit(StenoKey.TL)|Bit(StenoKey.FR)),"both-pad chord failed");
            Check(events[0].DispatchLabel==GeminiPRPacket.RecordingLabel(events[0].StenoMask) && core.StenoOutput.IsCurrent(events[0].StenoGeneration),"steno recording/generation missing");
            Frame(core,TrackpadSide.Right,up,1.2); Check(Drain(core).Length==0,"all-up duplicated stroke");
            // A contact between keys still keeps the shared chord open.
            Frame(core,TrackpadSide.Left,left,2); Frame(core,TrackpadSide.Right,Point(.99,.99),2.02);
            Frame(core,TrackpadSide.Left,up,2.04); Check(Drain(core).Length==0,"off-key contact failed to retain stroke");
            Frame(core,TrackpadSide.Right,up,2.06); Check(Drain(core).Single().StenoMask==Bit(StenoKey.TL),"off-key contact changed stroke");
            // Geometry/mappings and variants survive the full settings bundle.
            map.Mappings[0][GridKeyPosition.StorageKey(TrackpadSide.Left,1,1)]=new() { Primary=new() { Label="STN_FN" } };
            var bundle=AppleMagicTouchstreamProfileBundle.Create(new UserSettings { LayoutPresetName=preset.Name },map);
            Check(bundle.TryLoadPortableProfile(out var settings,out var imported,out _) && settings.LayoutPresetName==preset.Name,"steno profile failed to round-trip");
            imported.SetActiveLayout(preset.Name);
            Check(imported.ResolveMapping(0,GridKeyPosition.StorageKey(TrackpadSide.Left,1,1),"None").Primary.Label=="STN_FN","steno assignment was lost on import");
        }
        var basic=TrackpadLayoutPreset.Steno; var engine=Core(basic,out _); var empty=new InputFrame();
        Frame(engine,TrackpadSide.Left,Point(.305,.42),1); Frame(engine,TrackpadSide.Left,empty,1.1);
        Check(Drain(engine).Single().StenoMask==(Bit(StenoKey.TL)|Bit(StenoKey.KL)),"one fingertip could not chord an upper/lower seam");
        foreach(string reason in new[] { "stale","invalid","overflow","reset","layer","disconnect" })
        {
            engine=Core(basic,out _); var touch=Contact(basic,TrackpadSide.Left,StenoKey.TL);
            Frame(engine,TrackpadSide.Left,touch,1);
            if(reason=="stale") Frame(engine,TrackpadSide.Left,touch,1.3);
            if(reason=="invalid") { var invalid=touch; invalid.Contact0=invalid.Contact0 with { X=ushort.MaxValue }; Frame(engine,TrackpadSide.Left,invalid,1.05); }
            if(reason=="overflow") { var overflow=touch; overflow.ContactCount=6; Frame(engine,TrackpadSide.Left,overflow,1.05); }
            if(reason=="reset") engine.ResetState();
            if(reason=="layer") engine.SetPersistentLayer(1);
            if(reason=="disconnect") engine.RemoveStenoDevice(TrackpadSide.Left);
            Frame(engine,TrackpadSide.Left,empty,1.4);
            Check(Drain(engine).All(e=>e.Kind!=DispatchEventKind.StenoStroke),"cancelled stroke emitted: "+reason);
            Frame(engine,TrackpadSide.Left,touch,1.5); Frame(engine,TrackpadSide.Left,empty,1.6);
            Check(Drain(engine).Single().StenoMask==Bit(StenoKey.TL),"fresh chord failed after cancellation: "+reason);
        }
        engine=Core(basic,out _); var held=Contact(basic,TrackpadSide.Left,StenoKey.TL);
        Frame(engine,TrackpadSide.Left,held,1);
        var normal=new KeyLayout([[new(0,0,1,1)]],[["A"]]);
        engine.ConfigureLayouts(normal,normal); Drain(engine);
        Frame(engine,TrackpadSide.Left,held,1.05); Frame(engine,TrackpadSide.Left,empty,1.1);
        Check(Drain(engine).Length==0,"leaving STENO typed held contacts");
        Frame(engine,TrackpadSide.Left,held,1.2); Frame(engine,TrackpadSide.Left,empty,1.25);
        Check(Drain(engine).Any(e=>e.Kind==DispatchEventKind.KeyTap),"ordinary typing did not resume after STENO");
        // An invalid frame must invalidate strokes already waiting on the output pump.
        engine=Core(basic,out _);
        Frame(engine,TrackpadSide.Left,held,2); Frame(engine,TrackpadSide.Left,empty,2.1);
        var queued=Drain(engine).Single();
        var bad=held; bad.Contact0=bad.Contact0 with { X=ushort.MaxValue };
        Frame(engine,TrackpadSide.Left,bad,2.2);
        Check(!engine.StenoOutput.IsCurrent(queued.StenoGeneration),"invalid input retained queued stroke generation");
        RunFeedback(); RunActor(); RunConnection();
    }
    private static void RunFeedback()
    {
        var preset=TrackpadLayoutPreset.Steno;
        var left=Contact(preset,TrackpadSide.Left,StenoKey.TL); var right=Contact(preset,TrackpadSide.Right,StenoKey.FR); var up=new InputFrame();
        foreach(var mode in Enum.GetValues<StenoHapticMode>())
        {
            var core=Core(preset,out _); core.Configure(TouchProcessorConfig.Default with { StenoHaptics=mode }); core.SetHapticsOnKeyDispatchEnabled(true);
            Frame(core,TrackpadSide.Left,left,1); var landing=Drain(core);
            Check(landing.Count(e=>e.Kind==DispatchEventKind.StenoHaptic)==(mode==StenoHapticMode.KeyContact ? 1 : 0),"steno contact feedback mode failed");
            Frame(core,TrackpadSide.Left,left,1.02); Check(Drain(core).Length==0,"held key repeated feedback");
            Frame(core,TrackpadSide.Right,right,1.04); Drain(core);
            Frame(core,TrackpadSide.Left,up,1.06); Check(Drain(core).Length==0,"feedback sent before chord release");
            Frame(core,TrackpadSide.Right,up,1.08); var released=Drain(core);
            Check(released.Count(e=>e.Kind==DispatchEventKind.StenoStroke)==1,"feedback altered steno wire output");
            var feedback=released.Where(e=>e.Kind==DispatchEventKind.StenoHaptic).ToArray();
            Check(feedback.Length==(mode==StenoHapticMode.ChordRelease ? 2 : 0),"release feedback did not cover participating pads");
            if(feedback.Length>0)
            {
                Check(feedback.Select(e=>e.Side).Distinct().Count()==2,"release feedback used only the last-lifted pad");
                core.ResetState(); Check(feedback.All(e=>!core.StenoOutput.IsCurrent(e.StenoGeneration)),"feedback escaped cancellation generation");
            }
            core.SetHapticsOnKeyDispatchEnabled(false);
            Frame(core,TrackpadSide.Left,left,2); Frame(core,TrackpadSide.Left,up,2.05);
            Check(Drain(core).All(e=>e.Kind!=DispatchEventKind.StenoHaptic),"master haptic disable ignored");
        }
        var cancelled=Core(preset,out _); cancelled.Configure(TouchProcessorConfig.Default with { StenoHaptics=StenoHapticMode.ChordRelease }); cancelled.SetHapticsOnKeyDispatchEnabled(true);
        Frame(cancelled,TrackpadSide.Left,left,1); cancelled.ClaimStenoPointer(); Frame(cancelled,TrackpadSide.Left,up,1.05);
        Check(Drain(cancelled).Length==0,"pointer acquisition emitted release feedback or a stroke");
        var settings=new UserSettings { StenoHaptics=StenoHapticMode.ChordRelease };
        Check(settings.Clone().StenoHaptics==StenoHapticMode.ChordRelease,"haptic preference lost on clone");
        var bundle=AppleMagicTouchstreamProfileBundle.Create(settings,KeymapStore.LoadBundledDefault());
        Check(bundle.TryLoadPortableProfile(out var imported,out _,out _) && imported.StenoHaptics==StenoHapticMode.ChordRelease,"haptic preference lost on export/import");
        settings.StenoHaptics=(StenoHapticMode)100; settings.NormalizeRanges(); Check(settings.StenoHaptics==StenoHapticMode.KeyContact,"invalid haptic preference accepted");
        var combo=new ExplicitSelectionComboBox(); Check(!combo.IsTextSearchEnabled,"Plover type-search remained enabled"); combo.Items.Add("STENO"); combo.Items.Add("TouchStream"); combo.SelectedIndex=0;
        var wheel=new System.Windows.Input.MouseWheelEventArgs(System.Windows.Input.Mouse.PrimaryDevice,0,-120) { RoutedEvent=System.Windows.Input.Mouse.PreviewMouseWheelEvent };
        combo.RaiseEvent(wheel); Check(wheel.Handled && combo.SelectedIndex==0,"closed settings wheel changed selection");
        var text=new System.Windows.Input.TextCompositionEventArgs(System.Windows.Input.Keyboard.PrimaryDevice,
            new System.Windows.Input.TextComposition(System.Windows.Input.InputManager.Current,combo,"TouchStream")) { RoutedEvent=System.Windows.Input.TextCompositionManager.PreviewTextInputEvent };
        combo.RaiseEvent(text); Check(text.Handled && combo.SelectedIndex==0,"Plover text changed closed settings selection");
    }
    private sealed class NoGestures : IHandGestureRuntime
    {
        public bool SupportsKeyboardProposals=>true;
        public bool Process(TrackpadSide side,in InputFrame frame,ushort x,ushort y,long time)=>throw new InvalidOperationException("STENO entered ordinary gesture recognition");
        public void Tick() { }
        public void Dispose() { }
    }
    private static void RunActor()
    {
        var core=Core(TrackpadLayoutPreset.Steno,out _); using var queue=new DispatchEventQueue();
        using var actor=new TouchProcessorActor(core,dispatchQueue:queue,handGestures:new NoGestures());
        var contact=Contact(TrackpadLayoutPreset.Steno,TrackpadSide.Left,StenoKey.TL); var up=new InputFrame();
        actor.Post(TrackpadSide.Left,in contact,7612,5065,At(1)); actor.Post(TrackpadSide.Left,in up,7612,5065,At(1.1)); actor.WaitForIdle();
        Check(queue.TryDequeue(out var stroke,0) && stroke.Kind==DispatchEventKind.StenoStroke,"actor failed to publish steno stroke");
        Check(!queue.TryDequeue(out _,0),"actor emitted ordinary keyboard events in STENO");
    }
    private static void RunConnection()
    {
        var state=new StenoOutputState(); state.Configure(true);
        using var connection=new WindowsStenoConnection(0);
        Check(!connection.Status.Enabled,"creating a Steno connection opened a live port");
        connection.Configure(true,state,()=>true);
        Check(connection.Status.Enabled,"private test listener failed: "+connection.Status.Error);
        int pulses=0;
        var feedback=new DispatchEvent(Stopwatch.GetTimestamp(),DispatchEventKind.StenoHaptic,0,DispatchMouseButton.None,0,DispatchEventFlags.None,TrackpadSide.Left,"",StenoGeneration:state.Generation);
        Check(connection.TryFeedback(in feedback,_=>pulses++) && pulses==1,"feedback incorrectly required a Plover connection");
        state.Invalidate(); Check(!connection.TryFeedback(in feedback,_=>pulses++) && pulses==1,"cancelled feedback reached hardware callback");
        TcpClient connect()
        {
            var client=new TcpClient(); client.Connect("127.0.0.1",connection.BoundPort); client.ReceiveTimeout=1000;
            var stream=client.GetStream(); stream.Write(Encoding.ASCII.GetBytes("AMT-GEMINIPR/1\n"));
            var ready=new byte[6]; stream.ReadExactly(ready); Check(Encoding.ASCII.GetString(ready)=="READY\n","Plover handshake failed");
            Check(SpinWait.SpinUntil(()=>connection.Status.Connected,2000),"reader was not admitted"); return client;
        }
        DispatchEvent stroke()=>new(Stopwatch.GetTimestamp(),DispatchEventKind.StenoStroke,0,DispatchMouseButton.None,0,DispatchEventFlags.None,TrackpadSide.Left,"",StenoMask:Bit(StenoKey.KL)|Bit(StenoKey.PL)|Bit(StenoKey.HL),StenoGeneration:state.Generation);
        using(var client=connect())
        {
            var packet=stroke(); Check(connection.Send(in packet),"private connection dropped connected stroke");
            var received=new byte[6]; client.GetStream().ReadExactly(received);
            Check(Convert.ToHexString(received)=="800D00000000","transport altered binary Gemini PR/CR bytes");
            state.Invalidate(); Check(!connection.Send(in packet),"invalidated queued stroke escaped lifecycle cancellation");
        }
        Check(SpinWait.SpinUntil(()=>!connection.Status.Connected,2000),"closed reader was retained");
        var dropped=stroke(); Check(!connection.Send(in dropped),"disconnected stroke was buffered");
        using(var client=connect())
        {
            client.ReceiveTimeout=150;
            try { client.GetStream().ReadByte(); throw new InvalidOperationException("old disconnected stroke reached new reader"); }
            catch(IOException) { }
            var fresh=stroke(); Check(connection.Send(in fresh),"reconnected reader did not receive fresh stroke");
            var received=new byte[6]; client.GetStream().ReadExactly(received);
        }
        connection.Configure(false,state,()=>true); Check(!connection.Status.Enabled,"leaving STENO retained the endpoint");
    }
}
