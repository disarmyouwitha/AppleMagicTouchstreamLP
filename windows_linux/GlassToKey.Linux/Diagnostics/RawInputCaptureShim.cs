namespace GlassToKey;

internal readonly record struct RawInputDeviceTag(int Index, uint Hash);

internal readonly record struct RawInputDeviceInfo(
    uint VendorId,
    uint ProductId,
    ushort UsagePage,
    ushort Usage);

internal readonly record struct RawInputDeviceSnapshot(
    string DeviceName,
    RawInputDeviceInfo Info,
    RawInputDeviceTag Tag);
