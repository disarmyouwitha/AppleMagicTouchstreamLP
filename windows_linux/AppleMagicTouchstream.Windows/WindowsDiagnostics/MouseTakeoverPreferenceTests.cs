using System.IO;

namespace AppleMagicTouchstream;

internal static class MouseTakeoverPreferenceTests
{
    public static void Run()
    {
        string path=Path.Combine(Path.GetTempPath(),"AppleMagicTouchstream-takeover-"+Guid.NewGuid().ToString("N")+".json");
        void Check(bool condition,string message) { if(!condition) throw new InvalidOperationException(message); }
        try
        {
            var preference=new MouseTakeoverPreference(path);
            Check(!preference.Enabled && !File.Exists(path),"First launch must stay off without creating an opt-in");
            preference.SetEnabled(true);
            preference=new MouseTakeoverPreference(path);
            Check(preference.Enabled,"Saved opt-in was lost on restart");
            // Do not call Start: no hooks, hotkey registration or takeover in tests.
            using(var hook=new GlobalMouseInputHook())
            using(var controller=new MouseTakeoverController(hook,()=>true,preference))
            {
                Check(!controller.Enabled,"Loading an opt-in activated before startup preflight");
                controller.Release("Off · sleep");
                Check(new MouseTakeoverPreference(path).Enabled,"Lifecycle release erased the opt-in");
                controller.Release("Off · Ctrl+Alt+R released",forgetPreference:true);
                Check(!new MouseTakeoverPreference(path).Enabled,"Emergency release did not persist off");
                preference.SetEnabled(true);
                controller.SetEnabled(false);
                Check(!new MouseTakeoverPreference(path).Enabled,"Unchecking did not persist off");
                preference.SetEnabled(true);
            }
            Check(new MouseTakeoverPreference(path).Enabled,"Normal shutdown erased the opt-in");
            File.WriteAllText(path,"invalid preference");
            Check(!new MouseTakeoverPreference(path).Enabled,"Malformed opt-in must default off");
        }
        finally
        {
            File.Delete(path); File.Delete(path+".tmp");
        }
    }
}
