using System;
using System.Runtime.InteropServices;

namespace GlassToKey;

// Windows 11 24H2+ read-only status and the documented Ctrl+Win+F24 toggle.
// This is global to Precision Touchpads; it is not a per-device API.
internal static class PtpSystemTouchpad
{
    private const uint SpiGetTouchpadParameters = 0x00AE;
    private const uint InputKeyboard = 1;
    private const uint KeyUp = 0x0002;
    private const ushort VkControl = 0x11;
    private const ushort VkLeftWindows = 0x5B;
    private const ushort VkF24 = 0x87;

    public static bool TryGetStatus(out PtpStatus status)
    {
        TouchpadParameters parameters = new() { VersionNumber = 1 };
        bool ok = SystemParametersInfo(SpiGetTouchpadParameters,
            (uint)Marshal.SizeOf<TouchpadParameters>(), ref parameters, 0);
        status = ok
            ? new PtpStatus((parameters.Status & 1) != 0,
                (parameters.Status & 4) != 0,
                (parameters.Status & 8) != 0,
                (parameters.Status & 16) != 0,
                (parameters.Settings & 1) != 0)
            : default;
        return ok;
    }

    public static bool SendDocumentedToggle()
    {
        Input[] inputs =
        {
            Key(VkControl, 0), Key(VkLeftWindows, 0), Key(VkF24, 0),
            Key(VkF24, KeyUp), Key(VkLeftWindows, KeyUp), Key(VkControl, KeyUp)
        };
        return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) == inputs.Length;
    }

    private static Input Key(ushort vk, uint flags) => new()
    {
        Type = InputKeyboard,
        Union = new InputUnion { Keyboard = new KeyboardInput
            { VirtualKey = vk, Flags = flags, ExtraInfo = (IntPtr)0x47544B50 } }
    };

    [StructLayout(LayoutKind.Sequential)]
    private struct TouchpadParameters
    {
        public uint VersionNumber, MaxSupportedContacts, LegacyFeatures;
        public uint Status, Settings, SensitivityLevel, CursorSpeed;
        public uint FeedbackIntensity, ClickForceSensitivity, RightClickZoneWidth, RightClickZoneHeight;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Input { public uint Type; public InputUnion Union; }
    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KeyboardInput Keyboard;
        [FieldOffset(0)] public MouseInput Mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int DeltaX, DeltaY;
        public uint MouseData, Flags, Time;
        public IntPtr ExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort VirtualKey, ScanCode;
        public uint Flags, Time;
        public IntPtr ExtraInfo;
    }

    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint action, uint size,
        ref TouchpadParameters parameters, uint updateFlags);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, Input[] inputs, int size);
}

internal readonly record struct PtpStatus(bool Present, bool ExternalMousePresent,
    bool Enabled, bool Active, bool AllowActiveWithMouse);
