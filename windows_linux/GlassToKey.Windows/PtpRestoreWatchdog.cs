using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Threading;

namespace GlassToKey;

// Separate process so a diagnostic crash cannot leave the global PTP toggle off.
internal static class PtpRestoreWatchdog
{
    private static DispatcherTimer? _timer;
    private static readonly Stopwatch Elapsed = new();
    private static string? _logPath;
    private static Action? _finished;
    private static int _lastAttemptSecond;

    public static void Start(string logPath, Action finished)
    {
        _logPath = Path.GetFullPath(logPath);
        _finished = finished;
        Log($"WATCHDOG_START utc={DateTime.UtcNow:O}");
        Elapsed.Restart();
        _timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(500) };
        _timer.Tick += Tick;
        _timer.Start();
    }

    private static void Tick(object? sender, EventArgs e)
    {
        int seconds = (int)Elapsed.Elapsed.TotalSeconds;
        bool armed = false;
        try { armed = File.ReadAllText(_logPath!).Contains("WATCHDOG_ARMED", StringComparison.Ordinal); }
        catch { /* No toggle was armed yet. */ }
        if (armed && seconds >= 23 && seconds - _lastAttemptSecond >= 5 &&
            PtpSystemTouchpad.TryGetStatus(out PtpStatus status) && !status.Enabled)
        {
            _lastAttemptSecond = seconds;
            Log($"WATCHDOG_RESTORE second={seconds} sent={PtpSystemTouchpad.SendDocumentedToggle()}");
        }
        if (seconds < 36) return;
        _timer?.Stop();
        _timer = null;
        bool ok = PtpSystemTouchpad.TryGetStatus(out PtpStatus final) && final.Enabled;
        Log($"WATCHDOG_END utc={DateTime.UtcNow:O} enabled={ok}");
        _finished?.Invoke();
    }

    private static void Log(string line)
    {
        try { File.AppendAllText(_logPath!, line + Environment.NewLine); }
        catch { /* Restoration must not depend on logging. */ }
    }
}
