param([string]$OutputPath, [switch]$ReadEngineProperties)
$ErrorActionPreference = 'Stop'
# Metadata queries only. No registration, input capture, device open, or feature write.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class TrackpadMetadataResearch
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Device { public IntPtr Handle; public uint Type; }
    [DllImport("user32.dll", SetLastError=true)]
    private static extern uint GetRawInputDeviceList([Out] Device[] devices, ref uint count, uint size);
    [DllImport("user32.dll", EntryPoint="GetRawInputDeviceInfoW", SetLastError=true)]
    private static extern uint Info(IntPtr device, uint command, IntPtr data, ref uint size);
    [DllImport("user32.dll", EntryPoint="GetRawInputDeviceInfoW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern uint Name(IntPtr device, uint command, StringBuilder data, ref uint size);
    [DllImport("hid.dll")]
    private static extern int HidP_GetCaps(IntPtr preparsed, IntPtr caps);
    [DllImport("hid.dll")]
    private static extern int HidP_GetValueCaps(int type, IntPtr caps, ref ushort length, IntPtr preparsed);
    [DllImport("user32.dll", ExactSpelling=true, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetExtendedPointerDeviceProperty(IntPtr device, [In,Out] int[] property);

    private static object ReadExtended(IntPtr device)
    {
        // The inspected getter copies exactly 20 bytes; these selectors are handled by its validator.
        // No setter, registration, feature report, or IOCTL is issued here.
        var rows = new List<object>();
        try {
            for(int selector=0;selector<8;selector++) {
                int[] property = { selector,0,0,0,0 };
                bool ok = GetExtendedPointerDeviceProperty(device,property);
                rows.Add(new Dictionary<string,object> {
                    {"selector",selector},{"ok",ok},{"error",ok ? 0 : Marshal.GetLastWin32Error()},
                    {"values",new int[] {property[1],property[2],property[3],property[4]}}
                });
            }
        } catch(EntryPointNotFoundException) {
            return new Dictionary<string,object> {{"unavailable",true}};
        }
        return rows;
    }

    private static Dictionary<string,object> QueryInfo(IntPtr handle, uint suppliedSize)
    {
        IntPtr buffer = Marshal.AllocHGlobal(32);
        try {
            Marshal.Copy(new byte[32], 0, buffer, 32);
            Marshal.WriteInt32(buffer, (int)suppliedSize);
            uint size = suppliedSize;
            uint result = Info(handle, 0x2000000b, buffer, ref size);
            int error = result == uint.MaxValue ? Marshal.GetLastWin32Error() : 0;
            var answer = new Dictionary<string,object> {
                {"suppliedSize", suppliedSize}, {"result", result}, {"error", error}, {"returnedSize", size}
            };
            if (result != uint.MaxValue) {
                uint type = (uint)Marshal.ReadInt32(buffer,4);
                answer["type"] = type;
                if (type == 2) {
                    answer["vid"] = ((uint)Marshal.ReadInt32(buffer,8)).ToString("X4");
                    answer["pid"] = ((uint)Marshal.ReadInt32(buffer,12)).ToString("X4");
                    answer["usagePage"] = ((ushort)Marshal.ReadInt16(buffer,20)).ToString("X4");
                    answer["usage"] = ((ushort)Marshal.ReadInt16(buffer,22)).ToString("X4");
                }
            }
            return answer;
        } finally { Marshal.FreeHGlobal(buffer); }
    }

    private static Dictionary<string,object> QueryCaps(IntPtr handle)
    {
        uint size = 0;
        uint result = Info(handle, 0x20000005, IntPtr.Zero, ref size);
        if (result == uint.MaxValue || size == 0)
            return new Dictionary<string,object> {{"preparsedResult",result},{"preparsedBytes",size},
                {"preparsedError", result == uint.MaxValue ? Marshal.GetLastWin32Error() : 0}};
        IntPtr data = Marshal.AllocHGlobal(checked((int)size));
        IntPtr caps = Marshal.AllocHGlobal(64);
        try {
            if (Info(handle, 0x20000005, data, ref size) == uint.MaxValue)
                return new Dictionary<string,object> {{"preparsedError", Marshal.GetLastWin32Error()}};
            int status = HidP_GetCaps(data,caps);
            var answer = new Dictionary<string,object> {{"preparsedBytes",size},{"status",status.ToString("X8")}};
            if (status == 0x00110000) {
                answer["usage"] = ((ushort)Marshal.ReadInt16(caps,0)).ToString("X4");
                answer["usagePage"] = ((ushort)Marshal.ReadInt16(caps,2)).ToString("X4");
                answer["inputReportBytes"] = (ushort)Marshal.ReadInt16(caps,4);
                answer["outputReportBytes"] = (ushort)Marshal.ReadInt16(caps,6);
                answer["featureReportBytes"] = (ushort)Marshal.ReadInt16(caps,8);
                answer["inputValueCaps"] = (ushort)Marshal.ReadInt16(caps,48);
                ushort count = (ushort)Marshal.ReadInt16(caps,48);
                IntPtr values = Marshal.AllocHGlobal(count * 72);
                try {
                    int valueStatus = HidP_GetValueCaps(0,values,ref count,data);
                    answer["valueCapsStatus"] = valueStatus.ToString("X8");
                    var items = new List<object>();
                    if(valueStatus == 0x00110000) for(int i=0;i<count;i++) {
                        IntPtr v = IntPtr.Add(values,i*72);
                        items.Add(new Dictionary<string,object> {
                            {"usagePage",((ushort)Marshal.ReadInt16(v,0)).ToString("X4")},
                            {"reportId",Marshal.ReadByte(v,2)},
                            {"linkCollection",(ushort)Marshal.ReadInt16(v,6)},
                            {"isRange",Marshal.ReadByte(v,12)!=0},
                            {"bitSize",(ushort)Marshal.ReadInt16(v,18)},
                            {"reportCount",(ushort)Marshal.ReadInt16(v,20)},
                            {"logicalMin",Marshal.ReadInt32(v,40)},
                            {"logicalMax",Marshal.ReadInt32(v,44)},
                            {"usageOrMin",((ushort)Marshal.ReadInt16(v,56)).ToString("X4")}
                        });
                    }
                    answer["inputValues"] = items;
                } finally { Marshal.FreeHGlobal(values); }
            }
            return answer;
        } finally { Marshal.FreeHGlobal(caps); Marshal.FreeHGlobal(data); }
    }

    public static object[] Read(bool readEngineProperties)
    {
        uint count=0, stride=(uint)Marshal.SizeOf(typeof(Device));
        if (GetRawInputDeviceList(null,ref count,stride)==uint.MaxValue) throw new Win32Exception();
        Device[] devices=new Device[count];
        uint found=GetRawInputDeviceList(devices,ref count,stride);
        if(found==uint.MaxValue) throw new Win32Exception();
        var output=new List<object>();
        for(int i=0;i<found;i++) {
            uint length=0;
            if(Info(devices[i].Handle,0x20000007,IntPtr.Zero,ref length)==uint.MaxValue) continue;
            var name=new StringBuilder((int)length+1);
            if(Name(devices[i].Handle,0x20000007,name,ref length)==uint.MaxValue) continue;
            string path=name.ToString();
            if(path.IndexOf("PID&0324",StringComparison.OrdinalIgnoreCase)<0 &&
               path.IndexOf("PID_0324",StringComparison.OrdinalIgnoreCase)<0 &&
               path.IndexOf("PID&0265",StringComparison.OrdinalIgnoreCase)<0 &&
               path.IndexOf("PID_0265",StringComparison.OrdinalIgnoreCase)<0) continue;
            var row = new Dictionary<string,object> {
                {"path",path},{"rawType",devices[i].Type},
                {"legacy24",QueryInfo(devices[i].Handle,24)},
                {"native32",QueryInfo(devices[i].Handle,32)},
                {"caps",devices[i].Type == 2 ? QueryCaps(devices[i].Handle) :
                    new Dictionary<string,object> {{"notRequested","Not a RIM_TYPEHID input collection"}}}
            };
            if(readEngineProperties && devices[i].Type==2)
                row["engineProperties"] = ReadExtended(devices[i].Handle);
            output.Add(row);
        }
        return output.ToArray();
    }
}
'@
$json = ConvertTo-Json -InputObject @([TrackpadMetadataResearch]::Read($ReadEngineProperties.IsPresent)) -Depth 8
if ($OutputPath) { [System.IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath), $json) }
$json
