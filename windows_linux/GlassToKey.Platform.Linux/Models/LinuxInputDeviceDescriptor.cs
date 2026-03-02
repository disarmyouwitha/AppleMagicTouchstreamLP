namespace GlassToKey.Platform.Linux.Models;

public sealed record LinuxInputDeviceDescriptor(
    string DeviceNode,
    string StableId,
    string UniqueId,
    string PhysicalPath,
    string DisplayName,
    ushort VendorId,
    ushort ProductId,
    bool SupportsMultitouch,
    bool SupportsPressure,
    bool SupportsButtonClick,
    bool IsPreferredInterface,
    bool CanOpenEventStream,
    string AccessError);
