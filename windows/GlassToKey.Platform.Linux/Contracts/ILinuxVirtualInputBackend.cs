namespace GlassToKey.Platform.Linux.Contracts;

public interface ILinuxVirtualInputBackend : IDisposable
{
    void EnsureStarted();
}
