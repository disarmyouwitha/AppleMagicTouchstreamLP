param(
    [ValidateRange(2,30)][int]$Seconds = 30,
    [string]$OutputPath,
    [switch]$NoPrompt,
    [switch]$CompileOnly
)
$ErrorActionPreference = 'Stop'
Write-Host 'Passive USB capture v2 (Windows PowerShell 5.1 compatible)'
# Dedicated process recommended. Observes WM_INPUT; never opens/writes a HID device.
if (-not $OutputPath) { $OutputPath = Join-Path $PWD ('usb-vendor-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log') }
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class UsbVendorReportCapture
{
    [StructLayout(LayoutKind.Sequential)] struct Registration { public ushort Page, Usage; public uint Flags; public IntPtr Target; }
    [StructLayout(LayoutKind.Sequential)] struct Header { public uint Type, Size; public IntPtr Device, WParam; }
    [StructLayout(LayoutKind.Sequential)] struct Point { public int X,Y; }
    [StructLayout(LayoutKind.Sequential)] struct Message { public IntPtr HWnd; public uint Id; public UIntPtr WParam; public IntPtr LParam; public uint Time; public Point Pt; public uint Private; }
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate IntPtr WindowProc(IntPtr hwnd,uint msg,UIntPtr wparam,IntPtr lparam);
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct WindowClass {
        public uint Style; public WindowProc Proc; public int ClassExtra,WindowExtra;
        public IntPtr Instance,Icon,Cursor,Background; public string Menu,Name;
    }
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern ushort RegisterClassW(ref WindowClass cls);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateWindowExW(uint ex,string cls,string title,uint style,int x,int y,int w,int h,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr data);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr DefWindowProcW(IntPtr hwnd,uint msg,UIntPtr wp,IntPtr lp);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool UnregisterClassW(string cls,IntPtr instance);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);
    [DllImport("user32.dll",SetLastError=true)] static extern bool RegisterRawInputDevices(Registration[] devices,uint count,uint size);
    [DllImport("user32.dll",SetLastError=true)] static extern uint GetRawInputData(IntPtr raw,uint cmd,IntPtr data,ref uint size,uint header);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetRawInputDeviceInfoW(IntPtr dev,uint cmd,StringBuilder name,ref uint size);
    [DllImport("user32.dll")] static extern bool PeekMessageW(out Message msg,IntPtr hwnd,uint min,uint max,uint remove);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessageW(ref Message msg);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    static readonly WindowProc Callback = OnMessage;
    static StreamWriter Log;
    static Stopwatch Clock;
    static readonly Dictionary<IntPtr,string> Names = new Dictionary<IntPtr,string>();
    static readonly Dictionary<string,long> Counts = new Dictionary<string,long>();
    static Exception Fault;
    static long Bytes;
    static void Write(string text) { Log.WriteLine(DateTime.UtcNow.ToString("O")+" t="+Clock.Elapsed.TotalSeconds.ToString("F3",System.Globalization.CultureInfo.InvariantCulture)+" "+text); }
    static Registration[] Registrations(IntPtr hwnd,uint flags) { return new [] {
        new Registration{Page=0xff00,Usage=3,Flags=flags,Target=hwnd},
        new Registration{Page=0xff00,Usage=0x0d,Flags=flags,Target=hwnd},
        new Registration{Page=0x0d,Usage=5,Flags=flags,Target=hwnd} }; }
    static string Name(IntPtr device) {
        string name;
        if(Names.TryGetValue(device,out name)) return name;
        uint length=0;
        if(GetRawInputDeviceInfoW(device,0x20000007,null,ref length)==uint.MaxValue) throw new Win32Exception();
        var b=new StringBuilder(checked((int)length+1));
        if(GetRawInputDeviceInfoW(device,0x20000007,b,ref length)==uint.MaxValue) throw new Win32Exception();
        name=b.ToString(); Names[device]=name;
        return name;
    }
    static IntPtr OnMessage(IntPtr hwnd,uint msg,UIntPtr wp,IntPtr lp) {
        if(msg==0xff && Fault==null) try { Read(lp); } catch(Exception ex) { Fault=ex; }
        return DefWindowProcW(hwnd,msg,wp,lp);
    }
    static void Read(IntPtr raw) {
        uint header=(uint)Marshal.SizeOf(typeof(Header)), size=0;
        if(GetRawInputData(raw,0x10000003,IntPtr.Zero,ref size,header)!=0) throw new Win32Exception();
        if(size<header+8 || size>1048576) throw new InvalidDataException("Invalid raw packet size");
        IntPtr data=Marshal.AllocHGlobal((int)size);
        try {
            if(GetRawInputData(raw,0x10000003,data,ref size,header)!=size) throw new Win32Exception();
            Header h=Marshal.PtrToStructure<Header>(data);
            if(h.Type!=2) return;
            string name=Name(h.Device);
            if(name.IndexOf("VID_05AC&PID_0324&MI_",StringComparison.OrdinalIgnoreCase)<0 &&
               name.IndexOf("VID_05AC&PID_0265&MI_",StringComparison.OrdinalIgnoreCase)<0) return;
            uint stride=unchecked((uint)Marshal.ReadInt32(data,(int)header));
            uint count=unchecked((uint)Marshal.ReadInt32(data,(int)header+4));
            if(stride==0 || stride>65536 || count==0 || (ulong)header+8+(ulong)stride*count>size) throw new InvalidDataException("Invalid HID report bounds");
            if(!Counts.ContainsKey(name)) { Counts[name]=0; Write("DEVICE handle=0x"+h.Device.ToInt64().ToString("X")+" path="+name); }
            for(uint i=0;i<count;i++) {
                var bytes=new byte[stride];
                Marshal.Copy(IntPtr.Add(data,checked((int)(header+8+i*stride))),bytes,0,bytes.Length);
                Counts[name]++; Bytes+=bytes.Length;
                if(Bytes>16*1024*1024) throw new InvalidDataException("Capture byte limit reached");
                Write("FRAME handle=0x"+h.Device.ToInt64().ToString("X")+" n="+Counts[name]+" size="+stride+" hex="+BitConverter.ToString(bytes).Replace("-",""));
            }
        } finally { Marshal.FreeHGlobal(data); }
    }
    public static void Run(string path,int seconds) {
        if(seconds<2 || seconds>30) throw new ArgumentOutOfRangeException("seconds");
        IntPtr instance=GetModuleHandleW(null), hwnd=IntPtr.Zero;
        string cls="GlassToKeyPassiveVendor"+Guid.NewGuid().ToString("N");
        bool registered=false,created=false;
        Names.Clear(); Counts.Clear(); Fault=null; Bytes=0; Clock=Stopwatch.StartNew();
        using(Log=new StreamWriter(new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read))) {
            Log.AutoFlush=true;
            try {
                var wc=new WindowClass{Proc=Callback,Instance=instance,Name=cls};
                if(RegisterClassW(ref wc)==0) throw new Win32Exception();
                created=true;
                hwnd=CreateWindowExW(0,cls,"Passive USB HID capture",0,0,0,0,0,new IntPtr(-3),IntPtr.Zero,instance,IntPtr.Zero);
                if(hwnd==IntPtr.Zero) throw new Win32Exception();
                if(!RegisterRawInputDevices(Registrations(hwnd,0x100),3,(uint)Marshal.SizeOf(typeof(Registration)))) throw new Win32Exception();
                registered=true; Clock.Restart(); Write("START seconds="+seconds+" mode=passive-raw-input no-device-writes=True");
                string phase="";
                while(Clock.Elapsed.TotalSeconds<seconds && Fault==null) {
                    if((GetAsyncKeyState(0x1b)&0x8000)!=0) { Write("ESCAPE"); break; }
                    double t=Clock.Elapsed.TotalSeconds;
                    string next=t<5?"IDLE":t<12?"ONE_FINGER":t<19?"TWO_FINGERS":t<26?"THREE_FINGERS":"IDLE_END";
                    if(next!=phase) {phase=next; Write("PHASE "+phase); Console.WriteLine(phase);}
                    Message msg;
                    int processed=0;
                    while(processed++<256 && PeekMessageW(out msg,IntPtr.Zero,0,0,1)) DispatchMessageW(ref msg);
                    Thread.Sleep(2);
                }
                if(Fault!=null) throw Fault;
                foreach(var row in Counts) Write("COUNT frames="+row.Value+" path="+row.Key);
                Write("END devicesWithFrames="+Counts.Count+" payloadBytes="+Bytes);
            } catch(Exception ex) { Write("FAULT "+ex); throw; }
            finally {
                if(registered) RegisterRawInputDevices(Registrations(IntPtr.Zero,1),3,(uint)Marshal.SizeOf(typeof(Registration)));
                if(hwnd!=IntPtr.Zero) DestroyWindow(hwnd);
                if(created) UnregisterClassW(cls,instance);
            }
        }
    }
}
'@
if ($CompileOnly) { Write-Host 'Passive capture compiled successfully; no registrations or capture started.'; return }
Write-Host "Passive USB capture ($Seconds seconds). Native input remains enabled. Escape stops early."
Write-Host '0-5s: hands off. 5-12s: move one finger. 12-19s: move two fingers. 19-26s: move three fingers. 26-30s: hands off.'
Write-Host "Log: $OutputPath"
if (-not $NoPrompt) { [void](Read-Host 'Press Enter when ready') }
[UsbVendorReportCapture]::Run($OutputPath,$Seconds)
Write-Host "Capture finished: $OutputPath"
