using System.Reflection;

namespace AppleMagicTouchstream;

internal static class HyperModifierTests
{
    public static bool Run(out string failure)
    {
        try
        {
            void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
            var semantic = EngineActionResolver.ResolveActionLabel("Hyper").SemanticAction;
            Require(semantic.Kind == DispatchSemanticKind.Modifier && semantic.Modifiers == DispatchShortcutHelper.HyperModifiers,"Hyper is not a modifier action.");
            Require(DispatchShortcutHelper.FormatShortcut(semantic.Modifiers,"") == "Hyper","Hyper label expanded.");
            using var output = new SendInputDispatcher();
            output.SetPhysicalOutputSuppressed(true);
            var counts = (int[])typeof(SendInputDispatcher).GetField("_modifierRefCounts",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(output)!;
            void Emit(bool down, DispatchSemanticAction action) => output.Dispatch(new DispatchEvent(0,down ? DispatchEventKind.ModifierDown : DispatchEventKind.ModifierUp,0,DispatchMouseButton.None,0,DispatchEventFlags.None,TrackpadSide.Left,action.Label,action));
            foreach (string standalone in new[] { "Shift","LShift","Ctrl","LCtrl","Alt","LAlt","AltGr","Win","RShift","RCtrl","RWin" })
            {
                var single = EngineActionResolver.ResolveActionLabel(standalone).SemanticAction;
                Emit(true,single); Emit(true,semantic); Emit(false,semantic);
                int index = standalone switch {
                    "RShift" => 0xA1, "RCtrl" => 0xA3, "RWin" => 0x5C, "AltGr" => 0xA5,
                    _ => standalone.Contains("Shift") ? 0x10 : standalone.Contains("Ctrl") ? 0x11
                        : standalone.Contains("Alt") ? 0x12 : 0x5B
                };
                Require(counts[index] == 1,"Hyper released a separately held modifier: " + standalone);
                Emit(false,single);
                Require(counts.All(c=>c == 0),"Modifier remained stuck: " + standalone);
                Emit(true,semantic); Emit(true,single); Emit(false,single);
                Require(new[] { 0x10,0x11,0x12,0x5B }.All(i=>counts[i] == 1),"Standalone release broke Hyper: " + standalone);
                Emit(false,semantic);
                Require(counts.All(c=>c == 0),"Hyper remained stuck: " + standalone);
            }
            Emit(true,semantic); Emit(true,semantic); Emit(false,semantic);
            Require(new[] { 0x10,0x11,0x12,0x5B }.All(i=>counts[i] == 1),"Two Hyper owners did not share modifiers.");
            output.Dispose();
            Require(counts.All(c=>c == 0),"Dispatcher disposal left modifiers held.");
            failure = string.Empty;
            return true;
        }
        catch (Exception error) { failure = error.Message; return false; }
    }
}
