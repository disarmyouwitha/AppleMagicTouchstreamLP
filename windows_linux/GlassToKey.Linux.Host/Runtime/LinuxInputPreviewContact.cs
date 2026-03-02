namespace GlassToKey.Linux.Runtime;

public sealed record LinuxInputPreviewContact(
    uint Id,
    ushort X,
    ushort Y,
    byte Pressure,
    bool TipSwitch,
    bool Confidence);
