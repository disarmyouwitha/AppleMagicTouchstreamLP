using System.Runtime.InteropServices;
using System.Diagnostics;
namespace AppleMagicTouchstream;

internal sealed partial class SendInputDispatcher
{
    private sealed class GestureLease
    { public readonly ushort[] Keys=new ushort[16]; public int Count; public long Generation; }
    private readonly GestureLease[] _gestureLeases=[new(),new(),new(),new()];
    private readonly int[] _gestureKeyRefCounts=new int[256];
    private struct KeyboardOwner { public bool Active; public ulong Token; public ushort Key; }
    private readonly KeyboardOwner[] _keyboardOwners=new KeyboardOwner[128];
    private readonly int[] _keyboardKeyRefCounts=new int[256];
    private readonly long[] _lastNativeDownTicks=new long[256];
    private int RegisterKeyboardOwner(ulong token,ushort key)
    {
        int free=-1;
        for(int i=0;i<_keyboardOwners.Length;i++)
        {
            if(_keyboardOwners[i].Active) { if(_keyboardOwners[i].Token==token && _keyboardOwners[i].Key==key) return 0; }
            else if(free<0) free=i;
        }
        if(free<0) return -1;
        _keyboardOwners[free]=new() { Active=true,Token=token,Key=key }; _keyboardKeyRefCounts[key]++; return 1;
    }
    private bool RemoveKeyboardOwner(ulong token,ushort key)
    {
        for(int i=0;i<_keyboardOwners.Length;i++) if(_keyboardOwners[i].Active && _keyboardOwners[i].Token==token && _keyboardOwners[i].Key==key)
        { _keyboardOwners[i]=default; _keyboardKeyRefCounts[key]--; return true; }
        return false;
    }
    private readonly bool[] _gestureBorrowedKeys=new bool[256], _borrowedModifiers=new bool[256];
    private int _gestureReleaseRequested;
    private bool _requireCheckedKeyboardOutput;
    internal WindowsGestureKeyboardSession? GestureKeyboardSession { get; set; }
    internal Action<ushort,bool>? KeyEdgeObserver { get; set; }
    internal Func<ushort,bool>? PhysicalKeyProbe { get; set; }
    internal void RequestGestureKeyboardRelease()=>Interlocked.Exchange(ref _gestureReleaseRequested,1);
    private static bool IsModifier(ushort key)=>key is 0x10 or 0x11 or 0x12 or 0x5B or 0x5C or >=0xA0 and <=0xA5;
    private bool PhysicalKeyDown(ushort key)=>PhysicalKeyProbe?.Invoke(key) ?? GestureKeyboardSession?.PhysicalKeyDown(key)==true;
    private bool ExistingPhysicalKey(ushort key)=>PhysicalKeyProbe!=null || GestureKeyboardSession?.PhysicalTrackingAvailable==true
        ? PhysicalKeyDown(key) : !_suppressPhysicalOutput && (GestureGetAsyncKeyState(key)&0x8000)!=0;
    private void ConsumeGestureKeyboardRelease()
    {
        if(GestureKeyboardSession is {} session && !session.IsEligible) session.ReleaseAll();
        if(Interlocked.Exchange(ref _gestureReleaseRequested,0)==0) return;
        try { ReleaseGestureLeases(); } catch { RequestGestureKeyboardRelease(); throw; }
    }
    private void ReleaseGestureLeases() { foreach(var lease in _gestureLeases) ReleaseGestureLease(lease); }
    private void ReleaseGestureLease(GestureLease lease)
    {
        bool previous=_requireCheckedKeyboardOutput; _requireCheckedKeyboardOutput=true;
        try
        {
        while(lease.Count>0)
        {
            ushort key=lease.Keys[lease.Count-1];
            if(IsModifier(key)) HandleModifierUp(key);
            else
            {
                if(_gestureKeyRefCounts[key]==1 && !_keyDown[key] && !_tapHeldDown[key] && !_gestureBorrowedKeys[key] && !PhysicalKeyDown(key)) SendKeyboard(key,true);
                if(_gestureKeyRefCounts[key]>0) _gestureKeyRefCounts[key]--;
                if(_gestureKeyRefCounts[key]==0) _gestureBorrowedKeys[key]=false;
            }
            lease.Count--;
        }
        }
        finally { _requireCheckedKeyboardOutput=previous; }
    }
    private void HandleGestureKeyboard(in DispatchEvent e)
    {
        int owner=(int)e.RepeatToken-1; if((uint)owner>=_gestureLeases.Length) return;
        var lease=_gestureLeases[owner];
        if(e.Kind==DispatchEventKind.GestureShortcutUp)
        { try { if(lease.Generation==e.GestureGeneration) ReleaseGestureLease(lease); } catch(Exception error) { GestureKeyboardSession?.ReportFault(error.Message); RequestGestureKeyboardRelease(); throw; } return; }
        if(GestureKeyboardSession?.Accepts(e)!=true) return;
        ReleaseGestureLease(lease); lease.Generation=e.GestureGeneration;
        var plan=WindowsGestureShortcutPlan.ForAssignment(e.DispatchLabel);
        bool previous=_requireCheckedKeyboardOutput; _requireCheckedKeyboardOutput=true;
        try
        {
            foreach(var edge in plan)
            {
                if(edge.Up) continue; ushort key=edge.Key;
                lease.Keys[lease.Count++]=key;
                if(IsModifier(key)) HandleModifierDown(key);
                else
                {
                    bool alreadyOwned=_gestureKeyRefCounts[key]>0 || _keyDown[key] || _tapHeldDown[key];
                    if(_gestureKeyRefCounts[key]++==0 && !alreadyOwned)
                    { _gestureBorrowedKeys[key]=ExistingPhysicalKey(key); if(!_gestureBorrowedKeys[key]) SendKeyboard(key,false); }
                }
            }
            if(e.Kind==DispatchEventKind.GestureShortcutTap) ReleaseGestureLease(lease);
        }
        catch(Exception error) { GestureKeyboardSession?.ReportFault(error.Message); RequestGestureKeyboardRelease(); throw; }
        finally { _requireCheckedKeyboardOutput=previous; }
    }
    private void MaintainBorrowedKeys()
    {
        if(_suppressPhysicalOutput) return;
        for(int key=0;key<256;key++)
        {
            // Allow inserted input to reach the OS before repairing a later
            // physical key-up; do not duplicate a just-posted held key-down.
            if(Stopwatch.GetTimestamp()-_lastNativeDownTicks[key]<Stopwatch.Frequency*.02) continue;
            if(_modifierRefCounts[key]>0 && !PhysicalKeyDown((ushort)key) && (GestureGetAsyncKeyState(key)&0x8000)==0)
            { SendKeyboard((ushort)key,false); _borrowedModifiers[key]=false; }
            if((_gestureKeyRefCounts[key]>0 || _keyboardKeyRefCounts[key]>0) && !PhysicalKeyDown((ushort)key) && (GestureGetAsyncKeyState(key)&0x8000)==0)
            { SendKeyboard((ushort)key,false); _gestureBorrowedKeys[key]=false; }
        }
    }
    [DllImport("user32.dll",EntryPoint="GetAsyncKeyState")] private static extern short GestureGetAsyncKeyState(int key);
}
