using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace GlassToKey;

internal static class BrightnessController
{
    private const int StepPercent = 5;

    public static void StepUp()
    {
        Step(direction: 1);
    }

    public static void StepDown()
    {
        Step(direction: -1);
    }

    private static void Step(int direction)
    {
        if (direction == 0)
        {
            return;
        }

        bool adjusted = false;
        MonitorEnumProc callback = (hMonitor, _, _, _) =>
        {
            adjusted |= AdjustPhysicalMonitors(hMonitor, direction);
            return true;
        };

        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
        GC.KeepAlive(callback);

        if (!adjusted)
        {
            _ = TryAdjustInternalDisplayBrightness(direction);
        }
    }

    private static bool AdjustPhysicalMonitors(IntPtr hMonitor, int direction)
    {
        if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, out uint count) || count == 0)
        {
            return false;
        }

        PHYSICAL_MONITOR[] monitors = new PHYSICAL_MONITOR[count];
        if (!GetPhysicalMonitorsFromHMONITOR(hMonitor, count, monitors))
        {
            return false;
        }

        bool adjusted = false;
        try
        {
            for (int i = 0; i < monitors.Length; i++)
            {
                IntPtr handle = monitors[i].hPhysicalMonitor;
                if (!GetMonitorBrightness(handle, out uint min, out uint current, out uint max))
                {
                    continue;
                }

                uint span = max > min ? max - min : 0;
                uint step = Math.Max(1u, (span * (uint)StepPercent + 99u) / 100u);
                int signedStep = direction > 0 ? (int)step : -(int)step;
                int target = Math.Clamp((int)current + signedStep, (int)min, (int)max);
                if ((uint)target == current)
                {
                    continue;
                }

                if (SetMonitorBrightness(handle, (uint)target))
                {
                    adjusted = true;
                }
            }
        }
        finally
        {
            DestroyPhysicalMonitors(count, monitors);
        }

        return adjusted;
    }

    private static bool TryAdjustInternalDisplayBrightness(int direction)
    {
        int step = direction > 0 ? StepPercent : -StepPercent;
        string script =
            "$step = " + step + "; " +
            "$brightness = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue; " +
            "$methods = Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue; " +
            "if ($null -eq $brightness -or $null -eq $methods) { exit 1 }; " +
            "$current = @{}; " +
            "foreach ($b in @($brightness)) { $current[$b.InstanceName] = [int]$b.CurrentBrightness }; " +
            "$changed = $false; " +
            "foreach ($m in @($methods)) { " +
            "if (-not $current.ContainsKey($m.InstanceName)) { continue }; " +
            "$value = $current[$m.InstanceName]; " +
            "$target = [Math]::Min(100, [Math]::Max(0, $value + $step)); " +
            "if ($target -eq $value) { continue }; " +
            "Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{ Timeout = 0; Brightness = [byte]$target } -ErrorAction SilentlyContinue | Out-Null; " +
            "$changed = $true " +
            "}; " +
            "if ($changed) { exit 0 } else { exit 1 }";

        return TryRunPowerShell(script);
    }

    private static bool TryRunPowerShell(string script)
    {
        string encodedScript = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        string arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand " + encodedScript;

        ProcessStartInfo startInfo = new()
        {
            FileName = "powershell.exe",
            Arguments = arguments,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        try
        {
            using Process? process = Process.Start(startInfo);
            if (process is null)
            {
                return false;
            }

            if (!process.WaitForExit(1500))
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // Ignore kill failures; treating this as an unhandled path is enough.
                }

                return false;
            }

            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EnumDisplayMonitors(
        IntPtr hdc,
        IntPtr lprcClip,
        MonitorEnumProc lpfnEnum,
        IntPtr dwData);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint numberOfPhysicalMonitors);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(
        IntPtr hMonitor,
        uint physicalMonitorArraySize,
        [Out] PHYSICAL_MONITOR[] physicalMonitorArray);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool DestroyPhysicalMonitors(
        uint physicalMonitorArraySize,
        [In] PHYSICAL_MONITOR[] physicalMonitorArray);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetMonitorBrightness(
        IntPtr hMonitor,
        out uint minimumBrightness,
        out uint currentBrightness,
        out uint maximumBrightness);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool SetMonitorBrightness(IntPtr hMonitor, uint newBrightness);
}
