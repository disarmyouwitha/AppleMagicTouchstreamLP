using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows.Controls;

namespace AppleMagicTouchstream;

internal static class SettingsPersistenceTests
{
    private static void Check(bool condition,string message) { if(!condition) throw new InvalidOperationException(message); }
    public static void Run()
    {
        string root=Path.Combine(Path.GetTempPath(),"AppleMagicTouchstream-settings-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var settings=new UserSettings { HoldDurationMs=310,HapticsStrength=0x00026C20,MemorySaverEnabled=true,HoldRepeatEnabled=true,
                LeftDevicePath="left-pad",RightDevicePath="right-pad",RunAtStartup=true,StartInTrayOnLaunch=true,
                DecoderProfilesByDevicePath=new() { ["left-pad"]="official" } };
            foreach(var hand in new[] {settings.HandGesturesV1.Left,settings.HandGesturesV1.Right})
            {
                for(int count=2;count<=5;count++)
                    foreach(bool spread in new[] {false,true}) hand.Set(PerHandGestureSettings.Pinch(count,spread)!.Value,HandGestureAction.None);
                hand.NaturalScrolling=false; hand.PointerSensitivity=.8; hand.ScrollSensitivity=1.4; hand.ZoomSensitivity=.6;
                hand.ThreeFingerTap=HandGestureAction.SecondaryClick;
                hand.HoldActions=new() { [4]=HandGestureAction.Custom }; hand.HoldThresholds=new() { [4]=875 };
                hand.CustomActions=new() { ["Hold4"]="Hyper",["TwoFingerMove/Up"]="Ctrl+C" }; hand.HeldShortcuts.Add("Hold4");
                hand.DirectionalMovement=new() { [HandGestureTrigger.TwoFingerMove]=new() { Enabled=true,
                    Actions=new() { [HandMovementDirection.Up]=HandGestureAction.Custom },RepeatMilliseconds=new() { [HandMovementDirection.Up]=175 } } };
                hand.CornerHoldActions=new() { [HandCornerChord.OuterCorners]=HandGestureAction.None };
                hand.CornerHoldThresholds=new() { [HandCornerChord.OuterCorners]=900 };
            }
            settings.HandGesturesV1.Coordinated.HoldActions[CoordinatedHandChord.ThreeFingers]=HandGestureAction.Custom;
            settings.HandGesturesV1.Coordinated.CustomActions["ThreeFingers/Hold"]="Shift";
            settings.HandGesturesV1.Coordinated.HeldShortcuts.Add("ThreeFingers/Hold");
            settings.HandGesturesV1.Coordinated.HoldThresholds[CoordinatedHandChord.ThreeFingers]=650;
            settings.HandGesturesV1.Coordinated.TapActions[CoordinatedHandChord.FourFingers]=HandGestureAction.Paste;
            WindowsInputPolicy.NormalizeLegacyModes(settings); settings.NormalizeRanges();
            string path=Path.Combine(root,"settings.json");
            Check(settings.TrySave(path,out string error),"Saving settings failed: "+error);
            var loaded=UserSettings.Load(path);
            Check(JsonSerializer.Serialize(loaded)==JsonSerializer.Serialize(settings),"Restart changed saved settings");
            foreach(var hand in new[] {loaded.HandGesturesV1.Left,loaded.HandGesturesV1.Right})
                for(int count=2;count<=5;count++) foreach(bool spread in new[] {false,true})
                    Check(hand.Get(PerHandGestureSettings.Pinch(count,spread)!.Value)==HandGestureAction.None,"Disabled pinch/spread returned after restart");

            var keymap=KeymapStore.LoadBundledDefault();
            var bundle=AppleMagicTouchstreamProfileBundle.Create(settings,keymap);
            var flags=System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Static;
            var host=typeof(MainWindow).GetMethod("BuildWindowsHostExtension",flags)!.Invoke(null,new object[] {settings})!;
            bundle.SetHostExtension("windows",host);
            string exportPath=Path.Combine(root,"export.json"); File.WriteAllText(exportPath,bundle.SerializeToJson());
            Check(AppleMagicTouchstreamProfileBundle.TryParse(File.ReadAllText(exportPath),out var imported,out error),error);
            Check(imported.TryLoadPortableProfile(out var importedSettings,out _,out error),error);
            var target=new UserSettings(); target.CopyFrom(importedSettings); WindowsInputPolicy.NormalizeLegacyModes(target);
            Check(JsonSerializer.Serialize(target)==JsonSerializer.Serialize(AppleMagicTouchstreamProfileBundle.CreatePortableSettingsSnapshot(settings)),
                "Export/import omitted settings or gesture metadata");
            typeof(MainWindow).GetMethod("ApplyWindowsHostExtension",flags)!.Invoke(null,new object[] {imported,target});
            Check(JsonSerializer.Serialize(target)==JsonSerializer.Serialize(settings),"Windows device/startup settings did not round-trip through the host extension");
            Check(target.TrySave(path,out error),error);
            Check(JsonSerializer.Serialize(UserSettings.Load(path))==JsonSerializer.Serialize(target),"Imported settings did not survive restart");
            string malformed=bundle.SerializeToJson().Replace("\"Settings\": {","\"Settings\": \"invalid\", \"Unused\": {");
            Check(AppleMagicTouchstreamProfileBundle.IsProfileBundle(malformed),"Malformed settings bundle could fall back to keymap-only success");
            Check(!AppleMagicTouchstreamProfileBundle.TryParse(malformed,out _,out _),"Invalid settings bundle was accepted");
            Check(!AppleMagicTouchstreamProfileBundle.IsProfileBundle(keymap.SerializeToJson()),"Legacy keymap was mistaken for a settings bundle");
            string keymapOnly=JsonSerializer.Serialize(new { KeymapJson=keymap.SerializeToJson() });
            Check(!AppleMagicTouchstreamProfileBundle.IsProfileBundle(keymapOnly)
                && !AppleMagicTouchstreamProfileBundle.TryParse(keymapOnly,out _,out _)
                && keymap.TryImportFromJson(keymapOnly,out _),"Legacy keymap wrapper could reset gesture settings to defaults");

            string previous=File.ReadAllText(path);
            using(var locked=File.Open(path,FileMode.Open,FileAccess.Read,FileShare.None))
                Check(!new UserSettings().TrySave(path,out error) && error.Length>0,"Save failure was hidden");
            Check(File.ReadAllText(path)==previous,"Failed save destroyed the previous settings");
            Check(!Directory.EnumerateFiles(root,"*.tmp").Any(),"Failed save left a partial settings file");

            var uiSettings=new UserSettings(); HandGesturePanel? panel=null;
            panel=new HandGesturePanel(uiSettings,()=> { Check(uiSettings.TrySave(path,out string saveError),saveError); WindowsInputPolicy.NormalizeLegacyModes(uiSettings); panel!.Refresh(uiSettings); });
            panel.SetDeviceSelection(null,"right-pad",selectActiveScope:true);
            Check(panel.EditingScope==HandGestureScope.Right,"Single right-pad editor opened on Left");
            panel.SelectPage("2-shape");
            var combo=HandGestureTests.Controls<ComboBox>(panel).Single(c=>Equals(c.Tag,HandGestureTrigger.TwoFingerPinch));
            combo.SelectedIndex=0;
            loaded=UserSettings.Load(path);
            Check(loaded.HandGesturesV1.Right.Get(HandGestureTrigger.TwoFingerPinch)==HandGestureAction.None
                && loaded.HandGesturesV1.Left.Get(HandGestureTrigger.TwoFingerPinch)==HandGestureAction.Zoom,"Pinch edit was not saved on the selected pad");
            panel.SelectPage("4-main"); panel.SelectSlot(nameof(HandGestureTrigger.FourFingerMove));
            var natural=HandGestureTests.Controls<CheckBox>(panel).Single(c=>Equals(c.Content,"Natural scrolling"));
            natural.IsChecked=false; natural.RaiseEvent(new System.Windows.RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
            Check(!UserSettings.Load(path).HandGesturesV1.Right.NaturalScrolling,"Natural scrolling edit did not persist");

            var devices=new ObservableCollection<HidDeviceInfo> { new("None",null) };
            var disconnected=SavedDeviceSelection.Resolve(devices,"right-pad");
            Check(!disconnected.IsNone && disconnected.Path=="right-pad","Disconnected saved device was cleared");
            Check(ReferenceEquals(disconnected,SavedDeviceSelection.Resolve(devices,"right-pad")) && devices.Count==2,"Disconnected placeholder duplicated");
            Check(SavedDeviceSelection.Resolve(devices,null).IsNone,"Explicit None was not retained");
            var connected=new HidDeviceInfo("Connected pad","right-pad"); devices.Clear(); devices.Add(new("None",null)); devices.Add(connected);
            Check(ReferenceEquals(connected,SavedDeviceSelection.Resolve(devices,"right-pad")),"Reconnected device was not resolved");

            var restore=new MouseTakeoverStartupRestore(); long now=Stopwatch.Frequency;
            restore.Begin(false); Check(!restore.Due(now),"First launch restored takeover without opt-in");
            restore.Begin(true); Check(restore.Due(now) && restore.Pending,"Saved takeover did not attempt restore");
            Check(!restore.Due(now+Stopwatch.Frequency) && restore.Due(now+2*Stopwatch.Frequency),"Delayed-device retries were lost or unbounded");
            restore.Cancel(); Check(!restore.Pending && !restore.Due(now+10*Stopwatch.Frequency),"Activation/emergency cancellation rearmed startup takeover");
        }
        finally
        {
            foreach(string file in Directory.EnumerateFiles(root)) File.Delete(file);
            Directory.Delete(root);
        }
    }
}
