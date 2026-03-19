using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace GlassToKey;

internal static class BrightnessController
{
    private const int NativeStepPercent = 10;
    private const int ScriptStepPercent = 10;
    private static readonly object InternalBrightnessLock = new();
    private static readonly InternalBrightnessHelper InternalBrightnessWorker = new();
    private static bool _internalWorkerRunning;
    private static int _pendingInternalBrightnessDeltaPercent;

    static BrightnessController()
    {
        AppDomain.CurrentDomain.ProcessExit += static (_, _) => InternalBrightnessWorker.Dispose();
        AppDomain.CurrentDomain.DomainUnload += static (_, _) => InternalBrightnessWorker.Dispose();
    }

    public static void StepUp()
    {
        AdjustPhysicalBrightness(direction: 1);
    }

    public static void StepDown()
    {
        AdjustPhysicalBrightness(direction: -1);
    }

    public static void StepScriptUp()
    {
        QueueInternalDisplayBrightnessStep(direction: 1);
    }

    public static void StepScriptDown()
    {
        QueueInternalDisplayBrightnessStep(direction: -1);
    }

    private static void AdjustPhysicalBrightness(int direction)
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
    }

    private static void QueueInternalDisplayBrightnessStep(int direction)
    {
        int deltaPercent = Math.Sign(direction) * ScriptStepPercent;
        if (deltaPercent == 0)
        {
            return;
        }

        bool scheduleWorker = false;
        lock (InternalBrightnessLock)
        {
            _pendingInternalBrightnessDeltaPercent = Math.Clamp(
                _pendingInternalBrightnessDeltaPercent + deltaPercent,
                -100,
                100);
            if (!_internalWorkerRunning)
            {
                _internalWorkerRunning = true;
                scheduleWorker = true;
            }
        }

        if (!scheduleWorker)
        {
            return;
        }

        ThreadPool.UnsafeQueueUserWorkItem(static _ => ProcessInternalBrightnessQueue(), null);
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
                uint step = Math.Max(1u, (span * (uint)NativeStepPercent + 99u) / 100u);
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

    private static void ProcessInternalBrightnessQueue()
    {
        while (true)
        {
            int deltaPercent;
            lock (InternalBrightnessLock)
            {
                deltaPercent = _pendingInternalBrightnessDeltaPercent;
                if (deltaPercent == 0)
                {
                    _internalWorkerRunning = false;
                    return;
                }

                _pendingInternalBrightnessDeltaPercent = 0;
            }

            _ = InternalBrightnessWorker.TryAdjust(deltaPercent);
        }
    }

    private sealed class InternalBrightnessHelper : IDisposable
    {
        private const int StartupTimeoutMs = 1500;
        private const int RequestTimeoutMs = 1500;
        private readonly object _sync = new();
        private Process? _process;
        private StreamWriter? _input;
        private StreamReader? _output;

        public bool TryAdjust(int deltaPercent)
        {
            if (deltaPercent == 0)
            {
                return false;
            }

            lock (_sync)
            {
                if (!EnsureProcessLocked())
                {
                    return false;
                }

                if (TrySendDeltaLocked(deltaPercent))
                {
                    return true;
                }

                DisposeProcessLocked();
                if (!EnsureProcessLocked())
                {
                    return false;
                }

                return TrySendDeltaLocked(deltaPercent);
            }
        }

        public void Dispose()
        {
            lock (_sync)
            {
                DisposeProcessLocked();
            }
        }

        private bool EnsureProcessLocked()
        {
            if (_process is { HasExited: false } && _input is not null && _output is not null)
            {
                return true;
            }

            DisposeProcessLocked();

            string encodedScript = Convert.ToBase64String(Encoding.Unicode.GetBytes(BuildWorkerScript()));
            ProcessStartInfo startInfo = new()
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand " + encodedScript,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            try
            {
                Process? process = Process.Start(startInfo);
                if (process is null)
                {
                    return false;
                }

                _process = process;
                _input = process.StandardInput;
                _input.AutoFlush = true;
                _output = process.StandardOutput;
                string? ready = ReadLineWithTimeout(_output, StartupTimeoutMs);
                if (!string.Equals(ready, "READY", StringComparison.Ordinal))
                {
                    DisposeProcessLocked();
                    return false;
                }

                return true;
            }
            catch
            {
                DisposeProcessLocked();
                return false;
            }
        }

        private bool TrySendDeltaLocked(int deltaPercent)
        {
            if (_process is null || _input is null || _output is null)
            {
                return false;
            }

            try
            {
                _input.WriteLine(deltaPercent.ToString(System.Globalization.CultureInfo.InvariantCulture));
                string? response = ReadLineWithTimeout(_output, RequestTimeoutMs);
                return string.Equals(response, "OK", StringComparison.Ordinal);
            }
            catch
            {
                return false;
            }
        }

        private void DisposeProcessLocked()
        {
            try
            {
                _input?.Dispose();
            }
            catch
            {
            }

            try
            {
                _output?.Dispose();
            }
            catch
            {
            }

            if (_process is not null)
            {
                try
                {
                    if (!_process.HasExited)
                    {
                        _process.Kill(entireProcessTree: true);
                        _process.WaitForExit(250);
                    }
                }
                catch
                {
                }

                _process.Dispose();
            }

            _process = null;
            _input = null;
            _output = null;
        }

        private static string? ReadLineWithTimeout(StreamReader reader, int timeoutMs)
        {
            using CancellationTokenSource cts = new(timeoutMs);
            try
            {
                return reader.ReadLineAsync(cts.Token).AsTask().GetAwaiter().GetResult();
            }
            catch
            {
                return null;
            }
        }

        private static string BuildWorkerScript()
        {
            return
                "$ErrorActionPreference = 'SilentlyContinue'; " +
                "$methods = @{}; " +
                "foreach ($m in @(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue)) { $methods[$m.InstanceName] = $m }; " +
                "[Console]::Out.WriteLine('READY'); [Console]::Out.Flush(); " +
                "while (($line = [Console]::In.ReadLine()) -ne $null) { " +
                "$delta = 0; " +
                "if (-not [int]::TryParse($line, [ref]$delta) -or $delta -eq 0) { [Console]::Out.WriteLine('ERR'); [Console]::Out.Flush(); continue }; " +
                "$brightness = @(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue); " +
                "if ($brightness.Count -eq 0 -or $methods.Count -eq 0) { [Console]::Out.WriteLine('MISS'); [Console]::Out.Flush(); continue }; " +
                "$changed = $false; " +
                "foreach ($b in $brightness) { " +
                "if (-not $methods.ContainsKey($b.InstanceName)) { continue }; " +
                "$current = [int]$b.CurrentBrightness; " +
                "$target = [Math]::Min(100, [Math]::Max(0, $current + $delta)); " +
                "if ($target -eq $current) { continue }; " +
                "try { " +
                "Invoke-CimMethod -InputObject $methods[$b.InstanceName] -MethodName WmiSetBrightness -Arguments @{ Timeout = 0; Brightness = [byte]$target } -ErrorAction Stop | Out-Null; " +
                "$changed = $true " +
                "} catch { } " +
                "}; " +
                "if ($changed) { [Console]::Out.WriteLine('OK') } else { [Console]::Out.WriteLine('MISS') }; " +
                "[Console]::Out.Flush() " +
                "}";
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
