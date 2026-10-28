namespace AppleMagicTouchstream.Platform.Linux.Contracts;

public interface ILinuxVirtualInputBackend : IDisposable
{
    void EnsureStarted();
}
