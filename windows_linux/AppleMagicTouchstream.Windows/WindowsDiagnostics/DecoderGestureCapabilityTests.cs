using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AppleMagicTouchstream;

internal static class DecoderGestureCapabilityTests
{
    private static void Check(bool pass,string message) { if(!pass) throw new InvalidOperationException(message); }
    internal static void Run()
    {
        var capabilities=new DecoderGestureCapabilities();
        Check(capabilities.FingerClassification(TrackpadSide.Left)==null,"New connection assumed a decoder capability");
        foreach(var kind in new[]{TrackpadReportKind.PtpNative,TrackpadReportKind.PtpEmbedded,TrackpadReportKind.AppleNineByte})
        {
            capabilities.Observe(TrackpadSide.Left,kind);
            Check(capabilities.FingerClassification(TrackpadSide.Left)==false,"Old/Apple decoder advertised finger classification");
        }
        capabilities.Observe(TrackpadSide.Right,TrackpadReportKind.PtpExtended);
        Check(capabilities.FingerClassification(TrackpadSide.Right)==true && capabilities.FingerClassification(TrackpadSide.Left)==false,"Capability crossed independent pad routes");
        capabilities.Reset(TrackpadSide.Left);
        Check(capabilities.FingerClassification(TrackpadSide.Left)==null && capabilities.FingerClassification(TrackpadSide.Right)==true,"Disconnect cleared the other pad's capability");
        capabilities.Reset(); Check(capabilities.FingerClassification(TrackpadSide.Right)==null,"Refresh retained a stale decoder capability");

        var settings=new UserSettings(); int edits=0;
        settings.HandGesturesV1.Left.HoldActions=new() { [6]=HandGestureAction.Copy };
        settings.HandGesturesV1.Left.DirectionalMovement=new() { [HandGestureTrigger.ThumbTwoMove]=new() {
            Actions=new() { [HandMovementDirection.UpLeft]=HandGestureAction.Paste } } };
        var panel=new HandGesturePanel(settings,()=>edits++); panel.SelectPage("thumb");
        string saved=JsonSerializer.Serialize(settings.HandGesturesV1);
        Button Card(string key)=>HandGestureTests.Controls<Button>(panel).Single(c=>Equals(c.Tag,key));
        bool HasActionEditor()=>HandGestureTests.Controls<SearchableActionComboBox>(panel).Any(c=>c.PickerTitle=="Gesture Action");
        panel.SetFingerClassification(false,true);
        foreach(string slot in new[]{"ThumbTwoTap","Hold6","ThumbTwoMove/UpLeft","ThumbTwoMove/UpRight","ThumbTwoMove/DownLeft","ThumbTwoMove/DownRight"})
        {
            Check(!Card(slot).IsEnabled && Card(slot).Opacity<.5 && ToolTipService.GetShowOnDisabled(Card(slot)),"Unsupported thumb card remained actionable or lacked an explanation");
            panel.SelectSlot(slot); Check(!HasActionEditor(),"Unsupported thumb assignment remained editable");
        }
        Check(HandGestureTests.Controls<TextBlock>(panel).Any(c=>Equals(c.Tag,"FingerClassificationUnavailable") && c.Text.Contains("Saved assignments are preserved")),"Unavailable page explanation missing");
        panel.MirrorEdits=true;
        panel.EditingScope=HandGestureScope.Right; panel.SelectPage("thumb");
        Check(Card("ThumbTwoTap").IsEnabled && HasActionEditor(),"Left decoder disabled the supported Right pad with Mirror Edit");
        panel.EditingScope=HandGestureScope.Left;
        foreach(int count in Enumerable.Range(2,4))
        {
            panel.SelectPage(count+"-shape");
            foreach(bool right in new[]{false,true})
            {
                string rotation=PerHandGestureSettings.Rotation(count,right)!.Value.ToString();
                Check(!Card(rotation).IsEnabled,"Unsupported rotation remained enabled");
            }
            Check(!Card(PerHandGestureSettings.Pinch(count)!.Value.ToString()).IsEnabled
                && !Card(PerHandGestureSettings.Pinch(count,true)!.Value.ToString()).IsEnabled,"Unsupported pinch/spread remained enabled");
            Check(!HasActionEditor(),"Unsupported shape inspector remained editable");
        }
        panel.SelectPage("3-main");
        Check(Card("ThreeFingerMove").IsEnabled && Card("ThreeFingerTap").IsEnabled && Card("Hold3").IsEnabled,"Anatomy gate disabled ordinary three-finger inputs");
        panel.EditingScope=HandGestureScope.Both; panel.SelectPage("both-ThreeFingers");
        Check(Card("ThreeFingers/Tap").IsEnabled && HasActionEditor(),"Anatomy gate disabled coordinated inputs");
        panel.EditingScope=HandGestureScope.Left; panel.SelectPage("thumb");
        panel.SetFingerClassification(true,false);
        Check(Card("Hold6").IsEnabled && HasActionEditor(),"Switching to extended reports did not re-enable thumb gestures");
        panel.SetFingerClassification(null,null);
        Check(Card("Hold6").IsEnabled && HasActionEditor(),"Unknown/disconnected device blocked offline assignment editing");
        Check(edits==0 && saved==JsonSerializer.Serialize(settings.HandGesturesV1),"Capability display changed or discarded saved assignments");

        if(Environment.GetEnvironmentVariable("APPLEMAGICTOUCHSTREAM_CAPABILITY_PREVIEW_DIR") is {} directory)
        {
            // Load the real theme into a plain Window: never construct MainWindow,
            // attach devices, show a window or start the runtime for visual QA.
            if(Environment.GetEnvironmentVariable("APPLEMAGICTOUCHSTREAM_PREVIEW_XAML") is {} source)
            {
                string xaml=File.ReadAllText(source).Replace("x:Class=\"AppleMagicTouchstream.MainWindow\"","")
                    .Replace("clr-namespace:AppleMagicTouchstream\"","clr-namespace:AppleMagicTouchstream;assembly=AppleMagicTouchstream\"");
                var theme=(Window)XamlReader.Parse(xaml); panel.Resources=theme.Resources;
            }
            panel.Background=new SolidColorBrush(Color.FromRgb(16,18,20));
            Directory.CreateDirectory(directory); panel.SetFingerClassification(false,true);
            foreach(string page in new[]{"thumb","3-shape"})
            {
                panel.SelectPage(page);
                panel.Measure(new Size(1240,900)); panel.Arrange(new Rect(0,0,1240,900)); panel.UpdateLayout();
                var bitmap=new RenderTargetBitmap(1240,900,96,96,PixelFormats.Pbgra32); bitmap.Render(panel);
                var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var file=File.Create(Path.Combine(directory,$"unsupported-{page}.png")); encoder.Save(file);
            }
        }
        Console.WriteLine("Decoder gesture capabilities passed: detected formats, handed/reset state, disabled thumb/shape cards, preserved assignments and offline editing. No native input.");
    }
}
