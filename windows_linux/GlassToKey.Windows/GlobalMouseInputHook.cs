using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace GlassToKey;

internal sealed class GlobalMouseInputHook : IDisposable
{
    private const int WhMouseLl = 14;
    private const int HcAction = 0;
    private const int LlmhfInjected = 0x00000001;
    private const int WmMouseMove = 0x0200;
    private const int WmMouseWheel = 0x020A;
    private const int WmMouseHWheel = 0x020E;

    private const int WmLButtonDown = 0x0201;
    private const int WmLButtonUp = 0x0202;
    private const int WmLButtonDblClk = 0x0203;
    private const int WmRButtonDown = 0x0204;
    private const int WmRButtonUp = 0x0205;
    private const int WmRButtonDblClk = 0x0206;
    private const int WmMButtonDown = 0x0207;
    private const int WmMButtonUp = 0x0208;
    private const int WmMButtonDblClk = 0x0209;
    private const int WmXButtonDown = 0x020B;
    private const int WmXButtonUp = 0x020C;
    private const int WmXButtonDblClk = 0x020D;
    private const int WmNcLButtonDown = 0x00A1;
    private const int WmNcLButtonUp = 0x00A2;
    private const int WmNcLButtonDblClk = 0x00A3;
    private const int WmNcRButtonDown = 0x00A4;
    private const int WmNcRButtonUp = 0x00A5;
    private const int WmNcRButtonDblClk = 0x00A6;
    private const int WmNcMButtonDown = 0x00A7;
    private const int WmNcMButtonUp = 0x00A8;
    private const int WmNcMButtonDblClk = 0x00A9;
    private const int WmNcXButtonDown = 0x00AB;
    private const int WmNcXButtonUp = 0x00AC;
    private const int WmNcXButtonDblClk = 0x00AD;

    private HookProc? _hookProc;
    private IntPtr _hookHandle;
    private long _movementGateDeadline;
    private readonly MouseTakeoverGate _takeover = new();
    private int _takeoverReleaseKey = 0x79;
    private int _takeoverEscapeReleaseEnabled = 1;
    private bool _disposed;
    internal PhysicalKeyboardTracker PhysicalKeyboard { get; }=new();
    public event Action? ClickObserved;
    public event Action<MouseHookDiagnosticEvent>? DiagnosticEvent;

    public bool IsInstalled => _hookHandle != IntPtr.Zero;

    public bool Install(out string? error)
    {
        if (_disposed)
        {
            error = "disposed";
            return false;
        }

        if (_hookHandle != IntPtr.Zero)
        {
            error = null;
            return true;
        }

        _hookProc = HookCallback;
        IntPtr moduleHandle = GetModuleHandle(null);
        _hookHandle = SetWindowsHookEx(WhMouseLl, _hookProc, moduleHandle, 0);
        if (_hookHandle == IntPtr.Zero && moduleHandle != IntPtr.Zero)
        {
            // Fallback for environments where a null module handle is required.
            _hookHandle = SetWindowsHookEx(WhMouseLl, _hookProc, IntPtr.Zero, 0);
        }

        if (_hookHandle == IntPtr.Zero)
        {
            error = $"0x{Marshal.GetLastWin32Error():X}";
            _hookProc = null;
            return false;
        }

        error = null;
        PhysicalKeyboard.Install();
        return true;
    }

    // Enforced inside the hook: a stalled UI timer fails open.
    public void GatePhysicalMovementFor(TimeSpan duration)
    {
        if (duration <= TimeSpan.Zero || duration > TimeSpan.FromSeconds(10))
        {
            throw new ArgumentOutOfRangeException(nameof(duration));
        }
        Interlocked.Exchange(ref _movementGateDeadline,
            Stopwatch.GetTimestamp() + (long)(duration.TotalSeconds * Stopwatch.Frequency));
    }

    public void ReleaseMovementGate() => Interlocked.Exchange(ref _movementGateDeadline, 0);

    public bool IsMouseTakeoverActive => _takeover.IsActive(Stopwatch.GetTimestamp());
    public long GatePhysicalMouseFor(TimeSpan duration) => _takeover.Arm(Stopwatch.GetTimestamp(), duration);
    public void ReleaseMouseTakeover() => _takeover.Release();
    public void ReleaseMouseTakeover(long expectedDeadline) => _takeover.Release(expectedDeadline);
    public void SetTakeoverReleaseKey(int virtualKey) => Volatile.Write(ref _takeoverReleaseKey, virtualKey);
    public void SetTakeoverEscapeReleaseEnabled(bool enabled) => Volatile.Write(ref _takeoverEscapeReleaseEnabled, enabled ? 1 : 0);

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        PhysicalKeyboard.Dispose();
        ReleaseMouseTakeover();
        ReleaseMovementGate();
        if (_hookHandle != IntPtr.Zero)
        {
            _ = UnhookWindowsHookEx(_hookHandle);
            _hookHandle = IntPtr.Zero;
        }

        _hookProc = null;
        ClickObserved = null;
        DiagnosticEvent = null;
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= HcAction)
        {
            int message = unchecked((int)(long)wParam);
            bool isClick = IsClickMessage(message);
            bool isInjected = IsInjected(lParam);
            bool emergencyRelease = IsMouseTakeoverActive &&
                ((Volatile.Read(ref _takeoverEscapeReleaseEnabled) != 0 && (GetAsyncKeyState(0x1B) & 0x8000) != 0) ||
                 ((GetAsyncKeyState(0x11) & 0x8000) != 0 &&
                  (GetAsyncKeyState(0x12) & 0x8000) != 0 && (GetAsyncKeyState(Volatile.Read(ref _takeoverReleaseKey)) & 0x8000) != 0));
            if (isClick || message == WmMouseMove || message == WmMouseWheel || message == WmMouseHWheel)
            {
                try
                {
                    DiagnosticEvent?.Invoke(new MouseHookDiagnosticEvent(
                        Stopwatch.GetTimestamp(), message,
                        Marshal.ReadInt32(lParam, 0), Marshal.ReadInt32(lParam, 4),
                        Marshal.ReadInt32(lParam, 8), Marshal.ReadInt32(lParam, 12),
                        unchecked((uint)Marshal.ReadInt32(lParam, 16)),
                        unchecked((ulong)Marshal.ReadIntPtr(lParam, IntPtr.Size == 8 ? 24 : 20).ToInt64())));
                }
                catch
                {
                    // Diagnostics must never break the input chain.
                }
            }
            if (_takeover.ShouldBlock(isClick || message == WmMouseMove || message == WmMouseWheel || message == WmMouseHWheel,
                isInjected, Stopwatch.GetTimestamp(), emergencyRelease))
                return (IntPtr)1;
            if (message == WmMouseMove && !isInjected &&
                Stopwatch.GetTimestamp() < Interlocked.Read(ref _movementGateDeadline))
            {
                return (IntPtr)1;
            }
            if (isClick && !isInjected)
            {
                try
                {
                    ClickObserved?.Invoke();
                }
                catch
                {
                    // Observer failures should never impact input hook stability.
                }
            }

        }

        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private static bool IsInjected(IntPtr lParam)
    {
        int flags = Marshal.ReadInt32(lParam, 12);
        return (flags & LlmhfInjected) != 0;
    }

    private static bool IsClickMessage(int message)
    {
        return message == WmLButtonDown ||
               message == WmLButtonUp ||
               message == WmLButtonDblClk ||
               message == WmRButtonDown ||
               message == WmRButtonUp ||
               message == WmRButtonDblClk ||
               message == WmMButtonDown ||
               message == WmMButtonUp ||
               message == WmMButtonDblClk ||
               message == WmXButtonDown ||
               message == WmXButtonUp ||
               message == WmXButtonDblClk ||
               message == WmNcLButtonDown ||
               message == WmNcLButtonUp ||
               message == WmNcLButtonDblClk ||
               message == WmNcRButtonDown ||
               message == WmNcRButtonUp ||
               message == WmNcRButtonDblClk ||
               message == WmNcMButtonDown ||
               message == WmNcMButtonUp ||
               message == WmNcMButtonDblClk ||
               message == WmNcXButtonDown ||
               message == WmNcXButtonUp ||
               message == WmNcXButtonDblClk;
    }

    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? moduleName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);

}

internal readonly record struct MouseHookDiagnosticEvent(
    long StopwatchTicks, int Message, int X, int Y, int MouseData,
    int Flags, uint WindowsTime, ulong ExtraInfo);
