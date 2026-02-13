using System;
using System.Runtime.InteropServices;

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

        MonitorEnumProc callback = (hMonitor, _, _, _) =>
        {
            AdjustPhysicalMonitors(hMonitor, direction);
            return true;
        };

        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
        GC.KeepAlive(callback);
    }

    private static void AdjustPhysicalMonitors(IntPtr hMonitor, int direction)
    {
        if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, out uint count) || count == 0)
        {
            return;
        }

        PHYSICAL_MONITOR[] monitors = new PHYSICAL_MONITOR[count];
        if (!GetPhysicalMonitorsFromHMONITOR(hMonitor, count, monitors))
        {
            return;
        }

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

                SetMonitorBrightness(handle, (uint)target);
            }
        }
        finally
        {
            DestroyPhysicalMonitors(count, monitors);
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
