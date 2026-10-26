namespace GlassToKey;

// Value-only plans: constructing/testing these never posts input. Windows shell
// equivalents are intentional; there is no claim of native App Exposé parity.
internal static class WindowsGestureShortcutPlan
{
    internal readonly record struct Edge(ushort Key, bool Up);
    internal static Edge[] ForAssignment(string label)
    {
        var keys=new List<ushort>();
        if (DispatchShortcutHelper.TryParseShortcut(label,out var modifiers,out ushort key,out var semantic,out _,out _))
        {
            Span<DispatchSemanticCode> codes=stackalloc DispatchSemanticCode[16];
            int count=DispatchShortcutHelper.CopyModifierSemanticCodes(modifiers,codes);
            for (int i=0;i<count;i++) if (WindowsVirtualKeyMapper.TryMapSemanticCode(codes[i],out ushort vk) && !keys.Contains(vk)) keys.Add(vk);
            if (semantic!=DispatchSemanticCode.None) WindowsVirtualKeyMapper.TryMapSemanticCode(semantic,out key);
            if (key!=0 && !keys.Contains(key)) keys.Add(key);
        }
        else if (DispatchKeyResolver.TryResolveVirtualKey(label,out ushort singleKey)) keys.Add(singleKey);
        var edges=new Edge[keys.Count*2];
        for (int i=0;i<keys.Count;i++) { edges[i]=new(keys[i],false); edges[edges.Length-1-i]=new(keys[i],true); }
        return edges;
    }
    internal static Edge[] For(HandGestureAction action)
    {
        ushort controlKey = action switch { HandGestureAction.Copy => 0x43, HandGestureAction.Paste => 0x56,
            HandGestureAction.Cut => 0x58, HandGestureAction.Undo => 0x5A, HandGestureAction.Redo => 0x59,
            HandGestureAction.SelectAll => 0x41, _ => 0 };
        if (controlKey != 0) return [new(0x11,false),new(controlKey,false),new(controlKey,true),new(0x11,true)];
        if (action is HandGestureAction.Back or HandGestureAction.Forward)
        { ushort arrow = action == HandGestureAction.Back ? (ushort)0x25 : (ushort)0x27;
            return [new(0x12,false),new(arrow,false),new(arrow,true),new(0x12,true)]; }
        ushort key = action switch
        {
            HandGestureAction.NotificationCenter => 0x4E, // Win+N (Windows 11)
            HandGestureAction.TaskView => 0x09, // Win+Tab
            HandGestureAction.ShowDesktop => 0x44, // Win+D
            HandGestureAction.Voice => 0x48, // Windows voice typing, invoked explicitly.
            _ => 0
        };
        if (action == HandGestureAction.StartMenu) return [new(0x5B,false),new(0x5B,true)];
        return key == 0 ? [] : [new(0x5B,false),new(key,false),new(key,true),new(0x5B,true)];
    }
}
