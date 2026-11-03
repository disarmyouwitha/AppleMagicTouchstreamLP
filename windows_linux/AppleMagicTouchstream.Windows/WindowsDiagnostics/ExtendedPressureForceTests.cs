using System.Buffers.Binary;
using System.Diagnostics;
using System.Windows.Controls;

namespace AppleMagicTouchstream;

// Feed actual extended report bytes through decoding/projection into production
// recognizers. All output is recording-only, never native input or haptics.
internal static class ExtendedPressureForceTests
{
    private sealed class Output : IHandGestureOutput
    {
        internal readonly List<HandGestureAction> Actions=[];
        internal readonly List<bool> Buttons=[];
        internal int Feedback;
        public void Move(double x,double y) { }
        public void Scroll(double x,double y) { }
        public void PrimaryButton(bool down)=>Buttons.Add(down);
        public void Tap(HandGestureAction action)=>Actions.Add(action);
        public void Zoom(double delta) { }
        public void ForceFeedback(TrackpadSide side)=>Feedback++;
    }
    private static void Check(bool pass,string message) { if(!pass) throw new InvalidOperationException(message); }
    private static InputFrame Decode(int count,int pressure,ushort x=2300,ushort y=1500,bool clicked=false)
    {
        byte[] packet=new byte[112]; packet[0]=5; packet[108]=(byte)count; packet[111]=(byte)(clicked ? 1:0);
        for(int i=0;i<count;i++)
        {
            int offset=1+i*21; packet[offset]=3;
            BinaryPrimitives.WriteUInt32LittleEndian(packet.AsSpan(offset+1),(uint)(20+i));
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+5),(ushort)(x+i*300));
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+7),y);
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+9),400);
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+11),500);
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+13),(ushort)pressure);
            packet[offset+15]=40;packet[offset+16]=90;packet[offset+17]=45;
            packet[offset+18]=4;packet[offset+19]=(byte)(i+1);packet[offset+20]=4;
        }
        // Deliberately unrelated to per-contact pressure. Neither button state,
        // raw Size/State nor aggregate force may substitute for the pressure.
        BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(109),1200);
        var info=new RawInputDeviceInfo(0x05ac,RawInputInterop.ProductIdMt2UsbC,0x0d,5);
        Check(ExtendedPtpReportDecoder.TryDecode(packet,in info,Stopwatch.GetTimestamp(),out var result),"Extended pressure fixture failed decoding");
        return result.Frame;
    }
    private static HandGestureContact[] Contacts(int count,int pressure,bool clicked=false)
    {
        var frame=Decode(count,pressure,clicked:clicked); var contacts=new HandGestureContact[5];
        int actual=HandGestureContactAdapter.ReadContacts(frame,7612,5065,contacts,out _);
        return contacts[..actual];
    }
    private static HandGestureSettings Empty()
    {
        var settings=new HandGestureSettings();
        foreach(var hand in new[]{settings.Left,settings.Right})
        {
            foreach(var trigger in Enum.GetValues<HandGestureTrigger>()) hand.Set(trigger,HandGestureAction.None);
            hand.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.None };
        }
        settings.Coordinated.HoldActions=new() { [CoordinatedHandChord.OuterCorners]=HandGestureAction.None };
        return settings;
    }
    internal static void Run()
    {
        foreach(var side in new[]{TrackpadSide.Left,TrackpadSide.Right})
        {
            Keyboard(side,false); Keyboard(side,true); Independent(side); Steno(side);
        }
        Coordinated(); Settings();
        Console.WriteLine("Extended pressure force passed: decoded 0–255 pressure, keyboard/custom Force Instead of Hold (including zero), 1–5F Force, Both force, configurable STENO and range/UI policy. No native input.");
    }
    private static void Keyboard(TrackpadSide side,bool custom)
    {
        var map=KeymapStore.LoadBundledDefault(); map.CustomButtons.Clear();
        string key=GridKeyPosition.StorageKey(side,0,0);
        map.Mappings[0][key]=new() {Primary=new() {Label="A"},Hold=new() {Label="B"},HoldForceThreshold=130};
        var layout=new KeyLayout([new NormalizedRect[]{new(.2,.2,.2,.2)}],[new string[]{"A"}]);
        if(custom)
        {
            map.CustomButtons[0]=[new() {Id="pressure-custom",Side=side,Rect=new(.2,.2,.2,.2),Primary=new() {Label="A"},Hold=new() {Label="B"},HoldForceThreshold=130}];
            layout=new KeyLayout([new NormalizedRect[]{new(.6,.6,.1,.1)}],[new string[]{"None"}]);
        }
        var core=TouchProcessorFactory.CreateDefault(map);core.UseHandGestureRecognition();core.UseUnifiedInputPolicy();
        core.ConfigureLayouts(layout,layout); core.Configure(core.CurrentConfig with {HoldDurationMs=100,HoldRepeatEnabled=false});
        Check(custom || map.ResolveMapping(0,key,"A").HoldForceThreshold==130,"Force test lost its threshold while selecting the layout");
        var bindings=BindingIndex.Build(layout,side,0,map);
        Check(bindings.Bindings[bindings.HitTest(2300.0/7612,1500.0/5065).BindingIndex].Mapping.HoldForceThreshold==130,"Force test did not bind its pressure threshold");
        var events=new DispatchEvent[128];
        void frame(int pressure,double time,bool up=false,bool hasPressure=true)
        {
            var input=Decode(up ? 0:1,pressure);
            if(!up && !hasPressure) input.Contact0=input.Contact0 with {HasForceData=false,Telemetry=null};
            core.ProcessFrame(side,in input,7612,5065,(long)(time*Stopwatch.Frequency));
        }
        foreach(var sample in new[]{(0,1.0),(0,1.1),(0,1.2),(129,1.21)})
        {
            frame(sample.Item1,sample.Item2); int pending=core.DrainDispatchEvents(events);
            Check(!events.Take(pending).Any(e=>e.Kind is DispatchEventKind.KeyTap or DispatchEventKind.KeyDown),$"Reported zero/below-threshold pressure fell back to timed Hold ({side}, custom={custom}, sample={sample}; {string.Join(",",events.Take(pending).Select(e=>e.Kind+"/"+e.VirtualKey))})");
        }
        frame(130,1.22);frame(200,1.23);frame(0,1.24,true);
        int count=core.DrainDispatchEvents(events);
        Check(events.Take(count).Count(e=>e.Kind==DispatchEventKind.KeyTap && e.VirtualKey==0x42)==1
            && !events.Take(count).Any(e=>e.Kind==DispatchEventKind.KeyTap && e.VirtualKey==0x41),"Force Instead of Hold did not fire exactly the Hold action at the configured threshold");
        void threshold(int value)
        {
            if(custom) map.CustomButtons[0][0].HoldForceThreshold=value; else map.Mappings[0][key].HoldForceThreshold=value;
            core.ConfigureKeymap(map);
        }
        threshold(600);frame(255,2);frame(255,2.11);frame(0,2.12,true);
        count=core.DrainDispatchEvents(events);
        Check(!events.Take(count).Any(e=>e.Kind==DispatchEventKind.KeyTap && e.VirtualKey==0x42),"Extended pressure was inflated to reach an Apple phase-scale threshold");
        threshold(0);frame(0,3);frame(0,3.11);frame(0,3.12,true);
        count=core.DrainDispatchEvents(events);
        Check(events.Take(count).Count(e=>e.Kind==DispatchEventKind.KeyTap && e.VirtualKey==0x42)==1,"Threshold zero failed to preserve timed Hold");
        threshold(130);frame(0,4,hasPressure:false);frame(0,4.11,hasPressure:false);frame(0,4.12,true);
        count=core.DrainDispatchEvents(events);
        Check(events.Take(count).Count(e=>e.Kind==DispatchEventKind.KeyTap && e.VirtualKey==0x42)==1,"Genuinely unavailable pressure lost legacy timed Hold fallback");
    }
    private static void Independent(TrackpadSide side)
    {
        for(int count=1;count<=5;count++)
        {
            var settings=Empty(); var hand=side==TrackpadSide.Left ? settings.Left:settings.Right;
            hand.Set(PerHandGestureSettings.Force(count)!.Value,HandGestureAction.Copy);
            var output=new Output();var engine=WindowsHandGestures.CreateRecognizer(output);engine.Configure(settings,false);
            engine.Process(side,[],.9,.9,true);
            engine.Process(side,Contacts(count,0,true),1,1,true);
            engine.Process(side,Contacts(count,129,true),1.01,1.01,true);
            Check(output.Actions.Count==0,"Button/aggregate force/Size/State activated a force gesture below its pressure threshold");
            engine.Process(side,Contacts(count,130),1.02,1.02,true);engine.Process(side,Contacts(count,255),1.03,1.03,true);
            engine.Process(side,[],1.04,1.04,true);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Copy}) && output.Feedback==1,"1–5-finger force failed with extended pressure or repeated within a cycle");
        }
    }
    private static void Steno(TrackpadSide side)
    {
        foreach(int threshold in new[]{1,80,200,255})
        {
            var output=new Output();var engine=new StenoPointerEngine(output);engine.Configure(2,forceThreshold:threshold);
            engine.Process(side,Contacts(1,threshold-1,true),1,1,true);
            Check(output.Buttons.Count==0,"STENO ignored its configured pressure threshold");
            engine.Process(side,Contacts(1,threshold),1.01,1.01,true);
            Check(output.Buttons.SequenceEqual(new[]{true}),"STENO failed to acquire at its configured extended-pressure threshold");
            engine.Process(side,[],1.02,1.02,true);
            Check(output.Buttons.SequenceEqual(new[]{true,false}),"STENO force drag did not release on all-up");
        }
    }
    private static void Coordinated()
    {
        foreach(int count in new[]{3,4})
        {
            var settings=new CoordinatedGestureSettings(); settings.HoldActions[CoordinatedHandChord.OuterCorners]=HandGestureAction.None;
            var chord=count==3 ? CoordinatedHandChord.ThreeFingers:CoordinatedHandChord.FourFingers;
            settings.ForceActions[chord]=HandGestureAction.Paste;
            var output=new Output();var engine=new CoordinatedHandGestureEngine();engine.Configure(settings,true);
            engine.Process(TrackpadSide.Left,[],.9,true,false,output);engine.Process(TrackpadSide.Right,[],.91,true,false,output);
            engine.Process(TrackpadSide.Left,Contacts(count,129,true),1,true,false,output);
            engine.Process(TrackpadSide.Right,Contacts(count,129,true),1.01,true,false,output);
            Check(output.Actions.Count==0,"Both force used a button/aggregate instead of reported contact pressure");
            engine.Process(TrackpadSide.Left,Contacts(count,130),1.02,true,false,output);
            engine.Process(TrackpadSide.Right,Contacts(count,130),1.03,true,false,output);
            Check(output.Actions.SequenceEqual(new[]{HandGestureAction.Paste}) && output.Feedback==2,"Both force failed with extended pressure");
        }
    }
    private static void Settings()
    {
        var capabilities=new DecoderGestureCapabilities();
        capabilities.Observe(TrackpadSide.Left,TrackpadReportKind.PtpExtended,TrackpadDecoderProfile.Legacy);
        capabilities.Observe(TrackpadSide.Right,TrackpadReportKind.PtpNative,TrackpadDecoderProfile.Legacy);
        Check(capabilities.ForceMaximum(TrackpadSide.Left)==255 && capabilities.ForceMaximum(TrackpadSide.Right)==0,"Legacy profile hid extended pressure capability");
        capabilities.Observe(TrackpadSide.Right,TrackpadReportKind.PtpEmbedded,TrackpadDecoderProfile.Official);
        Check(capabilities.ForceMaximum(TrackpadSide.Right)==ForceNormalizer.Max && capabilities.FingerClassification(TrackpadSide.Right)==false,"Apple pressure/phase compatibility or anatomy changed");
        var settings=new UserSettings {StenoForceThreshold=500,ForceMin=80,ForceCap=90}; WindowsInputPolicy.NormalizeLegacyModes(settings);
        Check(settings.StenoForceThreshold==255 && settings.ForceMin==0 && settings.ForceCap==255,"STENO pressure range or retired global force policy is wrong");
        var panel=new StenoConnectionPanel();panel.Configure(settings);
        Check(HandGestureTests.Controls<Slider>(panel).Any(s=>s.Maximum==255 && s.Value==255),"STENO UI allows an unreachable pressure threshold");
        Check(WindowsForceSettings.SupportText(255,600).Contains("cannot trigger") && WindowsForceSettings.SupportText(0,130).Contains("timed Hold"),"Per-key pressure support/range explanation is missing");
        var frame=Decode(1,255);Check(frame.Contact0.HasForceData && frame.Contact0.ForceNorm==255 && frame.Contact0.Phase8==0,"Raw vendor state contaminated the extended pressure scale");
        capabilities.Reset();Check(capabilities.ForceMaximum(TrackpadSide.Left)==null,"Device reset retained an old force range");
    }
}
