using AppleMagicTouchstream.Platform.Linux.Models;

namespace AppleMagicTouchstream.Platform.Linux.Contracts;

public interface ILinuxRuntimeObserver
{
    void OnBindingStateChanged(LinuxRuntimeBindingState state);
}
