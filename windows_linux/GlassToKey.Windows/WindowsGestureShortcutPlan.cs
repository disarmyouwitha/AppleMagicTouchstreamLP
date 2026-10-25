namespace GlassToKey;

// Value-only plans: constructing/testing these never posts input. Windows shell
// equivalents are intentional; there is no claim of native App Exposé parity.
internal static class WindowsGestureShortcutPlan
{
    internal readonly record struct Edge(ushort Key, bool Up);
    internal static Edge[] For(HandGestureAction action)
    {
        ushort key = action switch
        {
            HandGestureAction.NotificationCenter => 0x4E, // Win+N (Windows 11)
            HandGestureAction.TaskView => 0x09, // Win+Tab
            HandGestureAction.ShowDesktop => 0x44, // Win+D
            _ => 0
        };
        if (action == HandGestureAction.StartMenu) return [new(0x5B,false),new(0x5B,true)];
        return key == 0 ? [] : [new(0x5B,false),new(key,false),new(key,true),new(0x5B,true)];
    }
}
