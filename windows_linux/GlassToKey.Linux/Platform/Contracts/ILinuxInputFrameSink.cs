using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux.Contracts;

public interface ILinuxInputFrameSink
{
    ValueTask OnFrameAsync(LinuxRuntimeFrame frame, CancellationToken cancellationToken);
}
