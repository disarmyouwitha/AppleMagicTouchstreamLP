using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AppleMagicTouchstream;

// Builds the real WPF workspace without creating a Window, runtime or hooks.
internal static class ShapeGestureInterfaceTests
{
    private static void Check(bool pass,string message) { if(!pass) throw new InvalidOperationException(message); }
    internal static void Run()
    {
        var settings=new UserSettings(); var panel=new HandGesturePanel(settings,()=>{});
        ComboBox Action(HandGestureTrigger trigger)=>HandGestureTests.Controls<ComboBox>(panel).Single(c=>Equals(c.Tag,trigger));
        ComboBox Repeat()=>HandGestureTests.Controls<ComboBox>(panel).Single(c=>Equals(c.Tag,"ShapeRepeatMode"));
        void SelectAction(HandGestureTrigger trigger,HandGestureAction value) { var combo=Action(trigger); combo.SelectedValuePath="Action"; combo.SelectedValue=value; }
        panel.MirrorEdits=false;
        foreach(var scope in new[]{HandGestureScope.Left,HandGestureScope.Right})
        foreach(int count in Enumerable.Range(2,4))
        {
            panel.EditingScope=scope; panel.SelectPage(count+"-shape");
            var titles=HandGestureTests.Controls<TextBlock>(panel).Select(t=>t.Text).ToArray();
            Check(new[]{"Pinch","Spread","Rotate Left","Rotate Right","Hold","Lift"}.All(titles.Contains),$"Shape cards missing on {scope}/{count}");
            foreach(bool right in new[]{false,true})
            {
                var trigger=PerHandGestureSettings.Rotation(count,right)!.Value; panel.SelectSlot(trigger.ToString());
                SelectAction(trigger,HandGestureAction.Back);
                var repeat=Repeat(); repeat.SelectedValuePath="Mode"; repeat.SelectedValue=HandShapeRepeatMode.Timed;
                var hand=scope==HandGestureScope.Left ? settings.HandGesturesV1.Left : settings.HandGesturesV1.Right;
                Check(hand.Get(trigger)==HandGestureAction.Back && hand.ShapeRepeat(trigger).Mode==HandShapeRepeatMode.Timed,$"Shape action/repeat failed on {scope}/{count}/{right}");
                Check(HandGestureTests.Controls<TextBlock>(panel).Any(t=>t.Text=="Repeat interval (ms)"),"Timed repeat interval field missing");
            }
        }
        var selected=HandGestureTrigger.FiveFingerRotateRight;
        panel.EditingScope=HandGestureScope.Left; panel.SelectPage("5-shape"); panel.SelectSlot(selected.ToString());
        panel.MirrorEdits=true;
        var both=Repeat(); both.SelectedValuePath="Mode"; both.SelectedValue=HandShapeRepeatMode.Motion;
        Check(settings.HandGesturesV1.Left.ShapeRepeat(selected).Mode==HandShapeRepeatMode.Motion && settings.HandGesturesV1.Right.ShapeRepeat(selected).Mode==HandShapeRepeatMode.Motion,"Mirror Edit did not copy repeat behavior");
        panel.MirrorEdits=false; var one=Repeat(); one.SelectedValuePath="Mode"; one.SelectedValue=HandShapeRepeatMode.Once;
        Check(settings.HandGesturesV1.Right.ShapeRepeat(selected).Mode==HandShapeRepeatMode.Motion,"Single-hand edit changed the other pad");
        panel.MirrorEdits=true; Check(Repeat().SelectedIndex==0,"Different per-hand repeat settings did not show Mixed");
        SelectAction(selected,HandGestureAction.None);
        Check(!HandGestureTests.Controls<ComboBox>(panel).Any(c=>Equals(c.Tag,"ShapeRepeatMode")),"Disabled shape exposed an active repeat control");
        panel.SelectSlot(nameof(HandGestureTrigger.FiveFingerPinch));
        Check(!HandGestureTests.Controls<ComboBox>(panel).Any(c=>Equals(c.Tag,"ShapeRepeatMode")),"Continuous Zoom exposed shortcut repeats");
        SelectAction(HandGestureTrigger.FiveFingerPinch,HandGestureAction.Copy);
        Check(Repeat()!=null,"Pinch shortcut did not expose repeat behavior");

        // Persistence through the complete settings bundle, with independent
        // handed values and the same-device fallback's selected repeat config.
        var path=Path.Combine(Path.GetTempPath(),"AMT-shape-"+Guid.NewGuid().ToString("N")+".json");
        try
        {
            Check(settings.TrySave(path,out var error),error);
            var loaded=UserSettings.Load(path);
            Check(loaded.HandGesturesV1.Right.ShapeRepeat(selected).Mode==HandShapeRepeatMode.Motion,"Repeat behavior lost on settings save/load");
            var keymap=KeymapStore.LoadBundledDefault(); var bundle=AppleMagicTouchstreamProfileBundle.Create(settings,keymap);
            Check(AppleMagicTouchstreamProfileBundle.TryParse(bundle.SerializeToJson(),out var imported,out error),error);
            Check(imported.TryLoadPortableProfile(out var importedSettings,out _,out error),error);
            Check(importedSettings.HandGesturesV1.Right.ShapeRepeat(selected).Mode==HandShapeRepeatMode.Motion,"Repeat behavior lost on settings export/import");
        }
        finally { if(File.Exists(path)) File.Delete(path); }

        if(Environment.GetEnvironmentVariable("APPLEMAGICTOUCHSTREAM_SHAPE_PREVIEW_DIR") is {} directory)
        {
            Directory.CreateDirectory(directory); panel.MirrorEdits=true;
            panel.SelectPage("5-shape"); panel.SelectSlot(nameof(HandGestureTrigger.FiveFingerRotateRight));
            SelectAction(HandGestureTrigger.FiveFingerRotateRight,HandGestureAction.Back);
            var repeat=Repeat(); repeat.SelectedValuePath="Mode"; repeat.SelectedValue=HandShapeRepeatMode.Timed;
            foreach(int width in new[]{1380,1100})
            {
                panel.Measure(new Size(width,950)); panel.Arrange(new Rect(0,0,width,950)); panel.UpdateLayout();
                var bitmap=new RenderTargetBitmap(width,950,96,96,PixelFormats.Pbgra32); bitmap.Render(panel);
                var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var file=File.Create(Path.Combine(directory,$"shape-gestures-{width}.png")); encoder.Save(file);
            }
        }
    }
}
