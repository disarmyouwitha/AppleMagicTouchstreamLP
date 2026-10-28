using System.Runtime.InteropServices;
namespace AppleMagicTouchstream;

// Observation only. No key filtering, text recording, translation or output.
// Injected events never become physical owners of a shortcut's keys.
internal sealed class PhysicalKeyboardTracker : IDisposable
{
    private readonly int[] _down=new int[256];
    private HookProc? _callback;
    private IntPtr _hook;
    public bool Available=>_hook!=IntPtr.Zero;
    public void Install()
    {
        if(Available) return; _callback=Observe;
        for(int key=0;key<256;key++) if(key is not (0x10 or 0x11 or 0x12)) _down[key]=(GetAsyncKeyState(key)&0x8000)!=0 ? 1 : 0;
        _hook=SetWindowsHookEx(13,_callback,GetModuleHandle(null),0);
        if(_hook==IntPtr.Zero) _callback=null;
    }
    public bool IsDown(ushort key)=>key switch
    {
        0x10=>Read(0x10)||Read(0xA0)||Read(0xA1),0x11=>Read(0x11)||Read(0xA2)||Read(0xA3),0x12=>Read(0x12)||Read(0xA4)||Read(0xA5),
        _=>Read(key)
    };
    private bool Read(int key)=>(uint)key<256 && Volatile.Read(ref _down[key])!=0;
    private IntPtr Observe(int code,IntPtr message,IntPtr data)
    {
        if(code>=0)
        {
            var key=Marshal.PtrToStructure<KeyboardData>(data);
            key.Key=key.Key switch { 0x10=>key.Scan==0x36 ? 0xA1u : 0xA0u,0x11=>(key.Flags&1)!=0 ? 0xA3u : 0xA2u,0x12=>(key.Flags&1)!=0 ? 0xA5u : 0xA4u,_=>key.Key };
            if((key.Flags&0x12)==0 && key.Key<256)
            {
                int kind=unchecked((int)(long)message);
                if(kind is 0x100 or 0x104) Volatile.Write(ref _down[key.Key],1);
                else if(kind is 0x101 or 0x105) Volatile.Write(ref _down[key.Key],0);
            }
        }
        return CallNextHookEx(_hook,code,message,data);
    }
    public void Dispose() { if(_hook!=IntPtr.Zero) { UnhookWindowsHookEx(_hook); _hook=IntPtr.Zero; } _callback=null; /* Retain the last physical-owner snapshot for output teardown. */ }
    [StructLayout(LayoutKind.Sequential)] private struct KeyboardData { public uint Key,Scan,Flags,Time; public nuint Extra; }
    private delegate IntPtr HookProc(int code,IntPtr message,IntPtr data);
    [DllImport("user32.dll",SetLastError=true)] private static extern IntPtr SetWindowsHookEx(int type,HookProc callback,IntPtr module,uint thread);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data);
    [DllImport("kernel32.dll",CharSet=CharSet.Auto)] private static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
}
