using AppleMagicTouchstream.Platform.Linux.Models;

namespace AppleMagicTouchstream.Platform.Linux.Contracts;

public interface ILinuxInputFrameSink
{
    ValueTask OnFrameAsync(LinuxRuntimeFrame frame, CancellationToken cancellationToken);
}
