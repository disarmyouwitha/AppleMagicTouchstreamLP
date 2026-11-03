using System.Text.Json;

namespace AppleMagicTouchstream;

// Pure model/runtime checks shared by --selftest and the portable offline runner.
internal static class MacMotionTests
{
    private static void Check(bool value,string message) { if(!value) throw new InvalidOperationException(message); }
    private static void Near(double actual,double expected,string message)=>Check(Math.Abs(actual-expected)<1e-9,message+$": {actual} != {expected}");
    private static JsonDocument Fixture(string suffix)
    {
        var assembly=typeof(MacMotionTests).Assembly;
        using var stream=assembly.GetManifestResourceStream(assembly.GetManifestResourceNames().Single(n=>n.EndsWith(suffix,StringComparison.Ordinal)))!;
        return JsonDocument.Parse(stream);
    }
    private sealed class Output:IHandGestureOutput
    {
        public readonly List<(double X,double Y)> Scrolls=new(),Moves=new();
        public readonly List<bool> Buttons=new();
        public int Taps;
        public void Move(double x,double y)=>Moves.Add((x,y));
        public void Scroll(double x,double y)=>Scrolls.Add((x,y));
        public void PrimaryButton(bool down)=>Buttons.Add(down);
        public void Tap(HandGestureAction action)=>Taps++;
        public void Zoom(double scale) { }
        public void ForceFeedback(TrackpadSide side) { }
    }
    private static HandGestureContact[] Contacts(int count,double offset=0)=>Enumerable.Range(0,count).Select(i=>new HandGestureContact((uint)i+1,20+i*16+offset,50+offset)).ToArray();
    public static void Run()
    {
        using(var fixture=Fixture("AppleScrollAccelerationVectors.json"))
        {
            var profile=new ApplePointerProfile { Resolution=400,Acceleration=.5,Curves=fixture.RootElement.GetProperty("curves").Deserialize<ApplePointerCurve[]>()! };
            var axis=new AppleScrollAxis(profile);
            foreach(var vector in fixture.RootElement.GetProperty("vectors").EnumerateArray())
                Near(axis.Points(vector.GetProperty("t").GetDouble(),vector.GetProperty("counts").GetDouble()) ?? double.NaN,vector.GetProperty("expected").GetDouble(),"Mac scroll golden vector");
            axis.Reset();
            Near(axis.Points(1,.01)!.Value,new AppleScrollAxis(profile).Points(1,.01)!.Value,"reset retained old scroll history");
            Check(axis.Points(1,.01)==null,"non-increasing scroll time was accepted");
            Check(axis.Points(2,double.NaN)==null,"non-finite scroll counts were accepted");
            Check(axis.Points(2,1e6)==null,"unbounded scroll output was accepted");
            var reverse=new AppleScrollAxis(profile); reverse.Points(1,8);
            var smallPrior=new AppleScrollAxis(profile); smallPrior.Points(1,.001);
            Near(reverse.Points(1.01,-.1)!.Value,smallPrior.Points(1.01,-.1)!.Value,"direction reversal retained old history");
            reverse.Points(1.02,8);
            Near(reverse.Points(2,-.1)!.Value,new AppleScrollAxis(profile).Points(2,-.1)!.Value,"idle gap retained old history");
            var unaccelerated=new AppleScrollAxis(profile with { Acceleration=-1 });
            Near(unaccelerated.Points(1,3)!.Value,3,"disabled acceleration changed counts");
        }
        using(var fixture=Fixture("CapturedMacMotionVectors.json"))
        foreach(var run in fixture.RootElement.GetProperty("runs").EnumerateArray())
        {
            var side=run.GetProperty("side").GetString()=="left" ? TrackpadSide.Left : TrackpadSide.Right;
            var captured=CapturedMacMotionProfiles.For(side);
            var pointer=new ApplePointerAccelerator(captured.Pointer);
            var scroll=new AppleScrollAccelerator(captured.Scroll);
            double gain=run.GetProperty("sensitivity").GetDouble();
            foreach(var vector in run.GetProperty("vectors").EnumerateArray())
            {
                double t=vector.GetProperty("t").GetDouble(),x=vector.GetProperty("x").GetDouble(),y=vector.GetProperty("y").GetDouble();
                var p=pointer.Millimetres(t,x,y,gain)!.Value;
                var s=scroll.Millimetres(t,x,y,gain,captured.Scroll.Natural)!.Value;
                Near(p.X,vector.GetProperty("pointerX").GetDouble(),"captured Mac production pointer X");
                Near(p.Y,vector.GetProperty("pointerY").GetDouble(),"captured Mac production pointer Y");
                Near(s.X,vector.GetProperty("scrollX").GetDouble(),"captured Mac production scroll X");
                Near(s.Y,vector.GetProperty("scrollY").GetDouble(),"captured Mac production scroll Y");
            }
        }
        foreach(var side in new[] {TrackpadSide.Left,TrackpadSide.Right})
        {
            var captured=CapturedMacMotionProfiles.For(side);
            var p=captured.Scroll;
            var a=new AppleScrollAccelerator(p); var b=new AppleScrollAccelerator(p);
            var positive=a.Millimetres(1,.001,-.001,1,true)!.Value;
            var negative=b.Millimetres(1,.001,-.001,1,false)!.Value;
            Check(positive.X>0 && positive.Y<0 && Math.Abs(positive.X)<1,"fine scroll fractions disappeared");
            Near(positive.X,-negative.X,"horizontal natural direction"); Near(positive.Y,-negative.Y,"vertical natural direction");
            a.Millimetres(1.01,0,.3,1,true);
            Near(a.Millimetres(1.02,.001,0,1,true)!.Value.X,b.Millimetres(1.02,.001,0,1,true)!.Value.X,"axis histories contaminated each other");
            a.Reset();
            Near(a.Millimetres(2,.01,.02,1,true)!.Value.Y,new AppleScrollAccelerator(p).Millimetres(2,.01,.02,1,true)!.Value.Y,"two-axis reset");
            var asymmetric=new AppleScrollAccelerator(p with { Horizontal=p.Horizontal with { Resolution=200 },Vertical=p.Vertical with { AlgorithmRate=90 } });
            var output=asymmetric.Millimetres(1,.01,.01,1,true)!.Value;
            Near(output.X,new AppleScrollAxis(p.Horizontal with { Resolution=200 }).Points(1,.01*200/25.4)!.Value,"horizontal profile was ignored");
            Near(output.Y,new AppleScrollAxis(p.Vertical with { AlgorithmRate=90 }).Points(1,.01*p.Vertical.Resolution/25.4)!.Value,"vertical profile/rate was ignored");
        }
        var saved=new HandGestureSettings();
        saved.Left.PointerSensitivity=1.25; saved.Left.ScrollSensitivity=.75;
        saved.Right.PointerSensitivity=.5; saved.Right.ScrollSensitivity=1.5; saved.Right.NaturalScrolling=false;
        var effective=CapturedMacMotionProfiles.Effective(saved);
        Check(effective.Left.PointerResponse==HandPointerResponse.ImportedApple && effective.Left.ImportedScrollProfile!=null,"captured response not selected");
        Check(effective.Right.PointerResponse==HandPointerResponse.ImportedApple && effective.Right.ImportedScrollProfile!=null,"captured response is not the default on both hands");
        Near(effective.Right.PointerSensitivity,.5,"configuration discarded independent pointer gain");
        Near(effective.Right.ScrollSensitivity,1.5,"configuration discarded independent scroll gain");
        Check(effective.Left.NaturalScrolling && !effective.Right.NaturalScrolling,"configuration discarded per-hand scrolling direction");
        Near(effective.Left.ScrollSensitivity,.75,"configuration discarded user gain");
        Check(saved.Left.ImportedScrollProfile==null,"runtime mutated saved settings");
        var restored=JsonSerializer.Deserialize<HandGestureSettings>(JsonSerializer.Serialize(effective))!.Clone();
        Check(restored.Left.ImportedScrollProfile!.Vertical.Resolution==effective.Left.ImportedScrollProfile!.Vertical.Resolution,"profile settings did not round-trip");
        Check(!ReferenceEquals(restored.Left.ImportedScrollProfile!.Vertical.Curves,effective.Left.ImportedScrollProfile!.Vertical.Curves),"profile clone shares mutable array");
        var bundle=AppleMagicTouchstreamProfileBundle.Create(new UserSettings { HandGesturesV1=effective },KeymapStore.LoadBundledDefault());
        var serialized=JsonSerializer.Deserialize<AppleMagicTouchstreamProfileBundle>(bundle.SerializeToJson())!;
        Check(serialized.TryLoadPortableProfile(out var imported,out _,out var error),"full motion settings import failed: "+error);
        Check(imported.HandGesturesV1.Left.ImportedScrollProfile!=null,"full settings export lost captured response");
        Near(imported.HandGesturesV1.Left.ScrollSensitivity,.75,"full settings export lost scroll gain");
        RunEngine();
    }
    private static void RunEngine()
    {
        var saved=new HandGestureSettings();
        var settings=CapturedMacMotionProfiles.Effective(saved);
        var output=new Output(); var engine=new HandGestureEngine(output); engine.Configure(settings,false);
        engine.Process(TrackpadSide.Left,[],.9,.9,true); engine.Process(TrackpadSide.Right,[],.9,.9,true);
        var model=new AppleScrollAccelerator(settings.Left.ImportedScrollProfile!);
        for(int i=0;i<7;i++)
        {
            double time=1+i*.01;
            engine.Process(TrackpadSide.Left,Contacts(4,i*.4),time,time,true);
            if(i==0) continue;
            var expected=model.Millimetres(time,.4,.4,settings.Left.ScrollSensitivity,settings.Left.NaturalScrolling)!.Value;
            Near(output.Scrolls[^1].X,expected.X,"live scroll bypassed model"); Near(output.Scrolls[^1].Y,expected.Y,"live vertical scroll bypassed model");
        }
        int before=output.Scrolls.Count;
        engine.Process(TrackpadSide.Left,[],1.07,1.07,true); engine.Tick(1.08,true);
        Check(output.Scrolls.Count>before,"accelerated scrolling did not coast");
        before=output.Scrolls.Count;
        engine.Process(TrackpadSide.Right,Contacts(2),1.081,1.081,true); engine.Tick(1.09,true);
        engine.Process(TrackpadSide.Right,[],1.10,1.10,true);
        Check(output.Scrolls.Count==before && output.Taps==0,"other-pad braking coast clicked or kept scrolling");
        // Reconfiguration and invalid input cannot carry acceleration history/coast.
        engine.Configure(settings,false); engine.Tick(1.11,true);
        Check(output.Scrolls.Count==before,"reconfiguration retained momentum");
        engine.Process(TrackpadSide.Left,[],2,2,true);
        engine.Process(TrackpadSide.Left,Contacts(4),2.01,2.01,true);
        engine.Process(TrackpadSide.Left,Contacts(4,.4),2.02,2.02,true);
        var fresh=new AppleScrollAccelerator(settings.Left.ImportedScrollProfile!).Millimetres(2.02,.4,.4,settings.Left.ScrollSensitivity,settings.Left.NaturalScrolling)!.Value;
        Near(output.Scrolls[^1].X,fresh.X,"new chord retained old scroll history");
        engine.Process(TrackpadSide.Left,[new(1,double.NaN,20)],2.03,2.03,true);
        before=output.Scrolls.Count; engine.Tick(2.04,true);
        Check(output.Scrolls.Count==before,"invalid input retained output");
        // Imported pointer response also serves drag and STENO, without changing acquisition.
        settings.Left.TwoFingerTap=HandGestureAction.None;
        engine.Configure(settings,false); engine.Process(TrackpadSide.Left,[],3,3,true);
        engine.Process(TrackpadSide.Left,Contacts(3),3.01,3.01,true); engine.Process(TrackpadSide.Left,Contacts(3,.4),3.02,3.02,true);
        var pointer=new ApplePointerAccelerator(settings.Left.ImportedPointerProfile!).Millimetres(3.02,.4,.4,settings.Left.PointerSensitivity)!.Value;
        Near(output.Moves[^1].X,pointer.X,"drag uses different pointer acceleration");
        engine.Process(TrackpadSide.Left,[],3.03,3.03,true); Check(output.Buttons.SequenceEqual(new[]{true,false}),"drag release became unbalanced");
        var stenoOutput=new Output(); var steno=new StenoPointerEngine(stenoOutput); steno.Configure(2,settings);
        steno.Process(TrackpadSide.Left,[],4,4,true); steno.Process(TrackpadSide.Left,Contacts(2),4.01,4.01,true);
        steno.Process(TrackpadSide.Left,Contacts(2,2.1),4.02,4.02,true);
        Check(stenoOutput.Moves.Count>0,"STENO did not retain pointer acquisition");
        var stenoExpected=new ApplePointerAccelerator(settings.Left.ImportedPointerProfile!).Millimetres(4.02,2.1,2.1,settings.Left.PointerSensitivity)!.Value;
        Near(stenoOutput.Moves[^1].X,stenoExpected.X,"STENO ignored selected pointer profile");
    }
}
