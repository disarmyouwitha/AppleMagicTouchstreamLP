using System.Collections;
using System.ComponentModel;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AppleMagicTouchstream;

// Exercises real templates and catalogs, without constructing MainWindow or
// starting hooks, devices, takeover, or native input.
internal static class ActionPickerTests
{
    private static void Check(bool pass,string message) { if(!pass) throw new InvalidOperationException(message); }
    private static List<SearchableActionComboBox.Choice> Results(SearchableActionComboBox picker)=>picker.ResultsView!.Cast<SearchableActionComboBox.Choice>().ToList();
    private static string Value(object item)=>TypeDescriptor.GetProperties(item)["Value"]!.GetValue(item)!.ToString()!;
    internal static void Run()
    {
        var settings=new UserSettings(); int edits=0; var panel=new HandGesturePanel(settings,()=>edits++);
        panel.MirrorEdits=false; panel.SelectSlot(nameof(HandGestureTrigger.TwoFingerTap));
        var gesture=HandGestureTests.Controls<SearchableActionComboBox>(panel).Single(c=>Equals(c.Tag,HandGestureTrigger.TwoFingerTap));
        Layout(gesture); gesture.PrepareResults();
        Check(Results(gesture).Select(c=>c.Category).Distinct().Count()>=4,"Gesture actions were not categorized");
        Check(Results(gesture).Single(c=>c.IsCurrent).Title=="Primary Click","Current action checkmark missing");
        var selected=gesture.SelectedItem;
        var search=(TextBox)gesture.Template.FindName("PART_Search",gesture);
        var list=(ListBox)gesture.Template.FindName("PART_Results",gesture);
        // Real TextChanged and ListBox highlight events must not bubble into
        // the editor's live ComboBox selection handler.
        search.Text="  kEyBoArD PaStE  ";
        Check(Results(gesture).Count==1 && Results(gesture)[0].Title=="Paste","Search did not match category/title case-insensitively");
        Check(ReferenceEquals(gesture.SelectedItem,selected) && edits==0,"Search/highlighting changed the live gesture binding");
        search.Text="does-not-exist";
        Check(Results(gesture).Count==0 && gesture.ResultCountText=="0 actions" && edits==0,"Empty search results changed the assignment");
        gesture.PrepareResults();
        Check(ReferenceEquals(gesture.SelectedItem,selected) && edits==0 && search.Text=="","Reopening/cancelling search changed the assignment or retained the query");
        gesture.MoveHighlight(1); gesture.MoveHighlight(8); gesture.MoveHighlight(-1);
        Check(ReferenceEquals(gesture.SelectedItem,selected) && edits==0,"Browsing highlighted results committed an action");
        search.Text="Ctrl+V";
        Check(Results(gesture).Count==1 && Results(gesture)[0].Title=="Paste","Shortcut alias was not searchable");
        Check(gesture.Choose(Results(gesture).Single()),"Gesture result did not commit");
        Check(settings.HandGesturesV1.Left.TwoFingerTap==HandGestureAction.Paste && settings.HandGesturesV1.Right.TwoFingerTap==HandGestureAction.PrimaryClick && edits==1,"Choosing a result changed the wrong hand or saved twice");

        // Keyboard Primary/Hold use the existing complete catalog and semantic
        // values. A separate result view preserves selections filtered out by a query.
        var catalog=(IEnumerable)typeof(MainWindow).GetMethod("BuildKeyActionOptions",BindingFlags.NonPublic|BindingFlags.Static)!.Invoke(null,null)!;
        var source=new ListCollectionView(catalog.Cast<object>().ToList());
        source.Filter=item=>!GeminiPRPacket.TryResolve(Value(item),out _);
        var keyboard=new SearchableActionComboBox { PickerTitle="Primary Action",ItemsSource=source,DisplayMemberPath="Display",SelectedValuePath="Value",SelectedValue="None" };
        Layout(keyboard); int changed=0; keyboard.SelectionChanged+=(_,_)=>changed++;
        keyboard.PrepareResults();
        Check(Results(keyboard).Select(c=>c.Category).Distinct().Count()>=7,"Keyboard action categories missing");
        Check(Results(keyboard).All(c=>!GeminiPRPacket.TryResolve(Value(c.Item),out _)),"Ordinary keyboard search exposed STENO keys");
        keyboard.SetQuery("Hyper");
        Check(Results(keyboard).Count==1 && changed==0 && Equals(keyboard.SelectedValue,"None"),"Keyboard search changed the stored key or lost Hyper");
        keyboard.Choose(Results(keyboard).Single()); Check(Equals(keyboard.SelectedValue,"Hyper") && changed==1,"Keyboard chooser lost its semantic value");
        keyboard.SetQuery("Navigation Enter"); Check(Results(keyboard).Count==1 && changed==1,"Keyboard category search changed the selection");
        keyboard.PrepareResults(); Check(Equals(keyboard.SelectedValue,"Hyper") && changed==1,"Dismiss/reopen reset a keyboard mapping");
        source.Filter=item=>Value(item)=="None" || GeminiPRPacket.TryResolve(Value(item),out _);
        keyboard.PrepareResults();
        Check(Results(keyboard).Count>1 && Results(keyboard).All(c=>Value(c.Item)=="None" || GeminiPRPacket.TryResolve(Value(c.Item),out _)),"STENO picker lost its source eligibility filter");

        // Both shortcut builders use searchable key pickers, retaining None for
        // modifier-only/Hyper combinations and all supported shortcut key labels.
        var builder=new GestureActionEditor("Ctrl+C",_=>{});
        var key=HandGestureTests.Controls<SearchableActionComboBox>(builder).Single();
        Layout(key); key.PrepareResults(); Check(Equals(key.SelectedItem,"C"),"Shortcut builder did not restore its key");
        key.SetQuery("function F12"); Check(Results(key).Count==1,"Function keys are not searchable by category");
        key.Choose(Results(key).Single()); Check(key.Text=="F12","Shortcut chooser did not update the apply value");
        key.SetQuery("None"); key.Choose(Results(key).Single()); Check(key.Text=="None","Modifier-only key selection was lost");
        foreach(string name in new[]{"KeymapPrimaryCombo","KeymapHoldCombo","GestureShortcutKeyCombo"})
            Check(typeof(MainWindow).GetField(name,BindingFlags.NonPublic|BindingFlags.Public|BindingFlags.Instance)!.FieldType==typeof(SearchableActionComboBox),name+" did not use the shared picker");

        if(Environment.GetEnvironmentVariable("APPLEMAGICTOUCHSTREAM_MENU_PREVIEW_DIR") is {} directory)
        {
            Directory.CreateDirectory(directory);
            gesture.PrepareResults(); Render(gesture,Path.Combine(directory,"gesture-menu.png"));
            gesture.SetQuery("paste"); Render(gesture,Path.Combine(directory,"gesture-search.png"));
            gesture.SetQuery("no-such-action"); Render(gesture,Path.Combine(directory,"empty-search.png"));
            source.Filter=item=>!GeminiPRPacket.TryResolve(Value(item),out _);
            keyboard.PrepareResults(); Render(keyboard,Path.Combine(directory,"keyboard-menu.png"));
            keyboard.SetQuery("modifiers"); Render(keyboard,Path.Combine(directory,"keyboard-search.png"));
        }
        Console.WriteLine("Action picker tests passed: categorized catalogs, search/empty results, selection isolation, explicit commit, handed bindings, STENO filters and shortcut keys. No native input.");
    }
    private static void Layout(SearchableActionComboBox picker)
    { picker.Measure(new Size(340,32)); picker.Arrange(new Rect(0,0,340,32)); picker.ApplyTemplate(); picker.UpdateLayout(); }
    private static void Render(SearchableActionComboBox picker,string path)
    {
        var popup=(Popup)picker.Template.FindName("PART_Popup",picker);
        var content=(FrameworkElement)popup.Child;
        content.Measure(new Size(460,480)); content.Arrange(new Rect(0,0,460,480)); content.UpdateLayout();
        var bitmap=new RenderTargetBitmap(460,480,96,96,PixelFormats.Pbgra32); bitmap.Render(content);
        var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var file=File.Create(path); encoder.Save(file);
    }
}
