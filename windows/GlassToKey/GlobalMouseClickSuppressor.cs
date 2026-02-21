using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace GlassToKey;

internal sealed class GlobalMouseClickSuppressor : IDisposable
{
    private const int WhMouseLl = 14;
    private const int HcAction = 0;
    private const int LlmhfInjected = 0x00000001;

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

    private readonly uint _processId;
    private HookProc? _hookProc;
    private IntPtr _hookHandle;
    private int _enabled;
    private bool _disposed;
    public event Action? ClickObserved;

    public GlobalMouseClickSuppressor()
    {
        _processId = (uint)Environment.ProcessId;
    }

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
        return true;
    }

    public void SetEnabled(bool enabled)
    {
        Volatile.Write(ref _enabled, enabled ? 1 : 0);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        SetEnabled(false);
        if (_hookHandle != IntPtr.Zero)
        {
            _ = UnhookWindowsHookEx(_hookHandle);
            _hookHandle = IntPtr.Zero;
        }

        _hookProc = null;
        ClickObserved = null;
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= HcAction)
        {
            int message = unchecked((int)(long)wParam);
            bool isClick = IsClickMessage(message);
            bool isInjected = IsInjected(lParam);
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

            if (Volatile.Read(ref _enabled) != 0 &&
                isClick &&
                !isInjected &&
                !IsCurrentProcessWindowAtCursor(lParam))
            {
                return (IntPtr)1;
            }
        }

        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private bool IsCurrentProcessWindowAtCursor(IntPtr lParam)
    {
        int x = Marshal.ReadInt32(lParam, 0);
        int y = Marshal.ReadInt32(lParam, 4);
        IntPtr hwnd = WindowFromPoint(new POINT(x, y));
        if (hwnd == IntPtr.Zero)
        {
            return false;
        }

        _ = GetWindowThreadProcessId(hwnd, out uint processId);
        return processId == _processId;
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

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct POINT
    {
        public readonly int X;
        public readonly int Y;

        public POINT(int x, int y)
        {
            X = x;
            Y = y;
        }
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? moduleName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr WindowFromPoint(POINT point);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
