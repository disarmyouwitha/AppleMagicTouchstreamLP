param([ValidateRange(1,10)][int]$SecondsPerInterface = 2, [string]$OutputPath, [switch]$Prompt)
$ErrorActionPreference = 'Stop'
if (-not $OutputPath) { $OutputPath = Join-Path $PWD ('usb-vendor-read-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log') }
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
# Ordinary HID read handles only: no feature/output requests or device/configuration writes.
$metadata = & (Join-Path $PSScriptRoot 'Read-RawInputMetadata.ps1') | ConvertFrom-Json
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class UsbVendorReadAccess
{
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool CancelIoEx(SafeFileHandle handle,IntPtr overlapped);
    static void Write(StreamWriter log,string value) { log.WriteLine(DateTime.UtcNow.ToString("O")+" "+value); }
    public static void Read(string path,int size,int seconds,StreamWriter log) {
        Write(log,"OPEN_REQUEST path="+path+" access=GENERIC_READ share=READ_WRITE reportBytes="+size);
        using(var handle=CreateFileW(path,0x80000000,3,IntPtr.Zero,3,0x40000000,IntPtr.Zero)) {
            if(handle.IsInvalid) {Write(log,"OPEN_FAILED error="+Marshal.GetLastWin32Error());return;}
            Write(log,"OPEN_OK");
            using(var stream=new FileStream(handle,FileAccess.Read,size,true)) {
                var clock=Stopwatch.StartNew(); int count=0;
                while(clock.Elapsed.TotalSeconds<seconds && count<1000) {
                    var bytes=new byte[size]; var pending=stream.ReadAsync(bytes,0,bytes.Length);
                    int remaining=Math.Max(1,(int)((seconds-clock.Elapsed.TotalSeconds)*1000));
                    if(!pending.Wait(remaining)) {
                        bool cancelled=CancelIoEx(handle,IntPtr.Zero);
                        int error=cancelled?0:Marshal.GetLastWin32Error();
                        Write(log,"READ_TIMEOUT cancelSent="+cancelled+" cancelError="+error);
                        try {if(!pending.Wait(3000)) throw new IOException("Cancellation did not complete within deadline");}
                        catch(AggregateException ex) {Write(log,"CANCEL_COMPLETION "+ex.GetBaseException().GetType().Name);}
                        break;
                    }
                    int n=pending.Result;
                    if(n==0) {Write(log,"READ_EOF");break;}
                    count++; Write(log,"FRAME n="+count+" size="+n+" hex="+BitConverter.ToString(bytes,0,n).Replace("-",""));
                }
                Write(log,"READ_END frames="+count+" elapsed="+clock.Elapsed.TotalSeconds.ToString("F3",System.Globalization.CultureInfo.InvariantCulture));
            }
        }
    }
}
'@
if ($Prompt) {
    Write-Host 'Direct HID reads only. Native input stays enabled; no device commands are sent.'
    Write-Host "Move one, two, then three fingers repeatedly throughout the capture ($SecondsPerInterface seconds per channel)."
    [void](Read-Host 'Press Enter when ready')
}
$log = [System.IO.StreamWriter]::new([System.IO.FileStream]::new($OutputPath,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read))
$log.AutoFlush = $true
try {
    foreach ($device in @($metadata | Where-Object { $_.path -match 'VID_05AC&PID_(0324|0265)&MI_0[23]#' -and $_.caps.inputReportBytes -gt 0 })) {
        Write-Host "Reading $($device.caps.inputReportBytes)-byte vendor channel for up to $SecondsPerInterface seconds. Keep moving fingers."
        [UsbVendorReadAccess]::Read($device.path,[int]$device.caps.inputReportBytes,$SecondsPerInterface,$log)
    }
} finally { $log.Dispose() }
Write-Host "Read-only HID access log: $OutputPath"
