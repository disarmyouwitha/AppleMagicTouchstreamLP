using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux.Contracts;

public interface ILinuxRuntimeObserver
{
    void OnBindingStateChanged(LinuxRuntimeBindingState state);
}
