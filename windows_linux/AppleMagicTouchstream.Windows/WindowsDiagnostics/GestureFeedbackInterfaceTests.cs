using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AppleMagicTouchstream;

internal static class GestureFeedbackInterfaceTests
{
    private static void Check(bool pass,string message) { if(!pass) throw new InvalidOperationException(message); }
    internal static void Run()
    {
        var panel=new HandGesturePanel(new UserSettings(),()=>{}); panel.SelectSlot("Hold2");
        var picker=HandGestureTests.Controls<SearchableActionComboBox>(panel).Single(c=>c.PickerTitle=="Gesture Action");
        Layout(picker,360,32);
        Check(picker.SelectedActionTitle=="None" && ((TextBlock)picker.Template.FindName("PART_SelectedTitle",picker)).Text=="None","None action rendered ActionOption's diagnostic record instead of its title");
        if(Environment.GetEnvironmentVariable("APPLEMAGICTOUCHSTREAM_FEEDBACK_PREVIEW_DIR") is {} noneDirectory)
        { Directory.CreateDirectory(noneDirectory); Render(picker,360,32,Path.Combine(noneDirectory,"selected-none.png")); }
        picker.SelectedValuePath="Action"; picker.SelectedValue=HandGestureAction.Copy;
        picker=HandGestureTests.Controls<SearchableActionComboBox>(panel).Single(c=>c.PickerTitle=="Gesture Action"); Layout(picker,360,32);
        Check(picker.SelectedActionTitle=="Copy" && ((TextBlock)picker.Template.FindName("PART_SelectedTitle",picker)).Text=="Copy","Action title was stale after rebuilding the editor");
        panel.SetRecognition("3-finger rotate left","2-finger tap");
        var status=HandGestureTests.Controls<TextBlock>(panel).Single(c=>Equals(c.Tag,"RecognizedGestures"));
        Check(status.Visibility==Visibility.Visible && status.Text=="Left · 3-finger rotate left\nRight · 2-finger tap","Gestures workspace did not display independent recognition feedback");
        panel.SetRecognition(null,"2-finger tap");
        Check(status.Text=="Right · 2-finger tap","Expiring one pad's feedback retained its label or removed the other");
        panel.SetRecognition(null,null); Check(status.Visibility==Visibility.Collapsed && status.Text=="","Expired recognition left stale text in the Gestures workspace");
        var metadata=(FrameworkPropertyMetadata)TouchView.RecognizedGestureProperty.GetMetadata(typeof(TouchView));
        Check(metadata.AffectsRender,"Gesture label changes/expiry did not invalidate the visualizer");

        if(Environment.GetEnvironmentVariable("APPLEMAGICTOUCHSTREAM_FEEDBACK_PREVIEW_DIR") is {} directory)
        {
            Directory.CreateDirectory(directory); Render(picker,360,32,Path.Combine(directory,"selected-copy.png"));
            foreach(int width in new[]{1080,680})
            {
                var pads=new Grid { Background=new SolidColorBrush(Color.FromRgb(16,18,20)) };
                pads.ColumnDefinitions.Add(new()); pads.ColumnDefinitions.Add(new());
                foreach(var side in new[]{TrackpadSide.Left,TrackpadSide.Right})
                {
                    var preset=TrackpadLayoutPreset.SixByThree; var keymap=KeymapStore.LoadBundledDefault();
                    var surface=new TouchView { State=new(),Side=side,PeakLabel="130",RecognizedGesture=side==TrackpadSide.Left ? "3-finger rotate left" : "Both · Bottom Outer Corners Hold",
                        Layout=LayoutBuilder.BuildLayout(preset,160,114.9,18,17,ColumnLayoutDefaults.DefaultSettings(preset.Columns),keymap,side==TrackpadSide.Left),EmptyMessage="" };
                    Grid.SetColumn(surface,(int)side); pads.Children.Add(surface);
                }
                Render(pads,width,440,Path.Combine(directory,$"recognized-gestures-{width}.png"));
            }
            panel.SetRecognition("3-finger rotate left","2-finger tap"); Render(panel,1240,850,Path.Combine(directory,"gesture-recognition-sidebar.png"));
        }
    }
    private static void Layout(FrameworkElement element,int width,int height)
    { element.Measure(new Size(width,height)); element.Arrange(new Rect(0,0,width,height)); element.ApplyTemplate(); element.UpdateLayout(); }
    private static void Render(FrameworkElement element,int width,int height,string path)
    {
        Layout(element,width,height); var bitmap=new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32); bitmap.Render(element);
        var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var file=File.Create(path); encoder.Save(file);
    }
}
