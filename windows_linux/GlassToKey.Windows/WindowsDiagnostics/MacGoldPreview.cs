using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace GlassToKey;

// Optional offline visual QA. Parses a plain Window instead of constructing
// MainWindow, so this cannot start ingestion, hooks, takeover or native output.
internal static class MacGoldPreview
{
    public static void RenderIfRequested()
    {
        string? source=Environment.GetEnvironmentVariable("GLASSTOKEY_PREVIEW_XAML");
        string? directory=Environment.GetEnvironmentVariable("GLASSTOKEY_PREVIEW_DIR");
        if (string.IsNullOrEmpty(source) || string.IsNullOrEmpty(directory)) return;
        Directory.CreateDirectory(directory);
        string xaml=File.ReadAllText(source).Replace("x:Class=\"GlassToKey.MainWindow\"","")
            .Replace("clr-namespace:GlassToKey\"","clr-namespace:GlassToKey;assembly=GlassToKey.Windows\"");
        foreach (var (name,width,height,gestures,both,touchstream) in new[] {
            ("keyboard",1240,780,false,false,false),("gestures",1240,900,true,false,false),
            ("both",1240,900,true,true,false),("compact",900,640,true,false,false),
            ("held-shortcut",1440,1000,true,false,false),("typing-tuning",1240,900,false,false,false),
            ("touchstream",1440,900,false,false,true) })
        {
            var window=(Window)XamlReader.Parse(xaml);
            ((Image)window.FindName("AppHandImage")).Source=ApplicationHandIcon.CreateImage();
            var settings=new UserSettings();
            var panel=new HandGesturePanel(settings,()=>{});
            ((Grid)window.FindName("HandGesturePanelHost")).Children.Add(panel);
            if (both) panel.EditingScope=HandGestureScope.Both;
            if(name=="held-shortcut")
            {
                settings.HandGesturesV1.Left.HoldActions=new() { [2]=HandGestureAction.Custom };
                settings.HandGesturesV1.Left.CustomActions=new() { ["Hold2"]="Hyper" }; settings.HandGesturesV1.Left.HeldShortcuts.Add("Hold2");
                panel.Refresh(settings); panel.SelectSlot("Hold2");
            }
            ((TabControl)window.FindName("SettingsTabs")).SelectedIndex=gestures ? 0 : 1;
            if(name=="typing-tuning")
            {
                DependencyObject? current=(DependencyObject)window.FindName("HoldDurationBox");
                while(current!=null && current is not Expander) current=LogicalTreeHelper.GetParent(current);
                if(current is Expander expander) expander.IsExpanded=true;
            }
            var preset=touchstream ? TrackpadLayoutPreset.TouchStream : TrackpadLayoutPreset.SixByThree;
            var keymap=KeymapStore.LoadBundledDefault(); keymap.SetActiveLayout(preset.Name);
            foreach (bool mirrored in new[] {true,false})
            {
                var surface=(TouchView)window.FindName(mirrored ? "LeftSurface" : "RightSurface");
                surface.State=new(); surface.Layout=LayoutBuilder.BuildLayout(preset,160,114.9,18,17,ColumnLayoutDefaults.DefaultSettings(preset.Columns),keymap,mirrored);
                surface.Side=mirrored ? TrackpadSide.Left : TrackpadSide.Right; surface.ShowTouchStreamReference=touchstream;
                surface.LabelMatrix=surface.Layout.Labels.Select((row,r)=>row.Select((label,c)=>
                {
                    var mapping=keymap.ResolveMapping(0,GridKeyPosition.StorageKey(surface.Side,r,c),label);
                    return touchstream && mapping.Primary.Label=="None" ? label : mapping.Primary.Label;
                }).ToArray()).ToArray();
                surface.EmptyMessage="";
            }
            foreach (string device in new[] {"LeftDeviceCombo","RightDeviceCombo"})
            { var combo=(ComboBox)window.FindName(device); combo.Items.Add(device.StartsWith("Left") ? "Left Magic Trackpad" : "Right Magic Trackpad"); combo.SelectedIndex=0; }
            var layoutCombo=(ComboBox)window.FindName("LayoutPresetCombo"); layoutCombo.Items.Add(preset.DisplayName); layoutCombo.SelectedIndex=0;
            var root=(FrameworkElement)window.Content; window.Content=null;
            root.Resources=window.Resources; root.Width=width; root.Height=height;
            if (root is Panel surfaceRoot) surfaceRoot.Background=new SolidColorBrush(Color.FromRgb(16,18,20));
            root.Measure(new(width,height)); root.Arrange(new Rect(0,0,width,height)); root.UpdateLayout();
            var tabs=(TabControl)window.FindName("SettingsTabs");
            if(!Equals(((TabItem)tabs.Items[0]).Header,"_Gestures") || !Equals(((TabItem)tabs.Items[1]).Header,"_Keyboard")) throw new InvalidOperationException("Workspace tab order differs from Mac");
            if(((Grid)window.FindName("KeyboardWorkspace")).Visibility!=(gestures ? Visibility.Collapsed : Visibility.Visible)
                || ((Grid)window.FindName("GestureWorkspace")).Visibility!=(gestures ? Visibility.Visible : Visibility.Collapsed))
                throw new InvalidOperationException("Workspace switch left the visualizer or gesture inspector in the wrong frame");
            if(gestures && (panel.ActualWidth<width-80 || panel.ColumnDefinitions[2].ActualWidth<240 || panel.ColumnDefinitions[4].ActualWidth<260))
                throw new InvalidOperationException("Gesture workspace is not a full-width three-column layout");
            foreach(string retired in new[] {"TypingGraceBox","DragCancelBox","IntentMoveBox","IntentVelocityBox"})
                if(window.FindName(retired)!=null) throw new InvalidOperationException("Retired typing tuning control survived: "+retired);
            var bitmap=new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32); bitmap.Render(root);
            using var output=File.Create(Path.Combine(directory,name+".png"));
            var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); encoder.Save(output);
            window.Close();
        }
    }
}
