namespace GlassToKey.Platform.Linux.Models;

public sealed record LinuxInputAxisInfo(
    int Value,
    int Minimum,
    int Maximum,
    int Fuzz,
    int Flat,
    int Resolution);
