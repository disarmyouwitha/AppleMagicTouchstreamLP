using GlassToKey.Platform.Linux.Contracts;

namespace GlassToKey.Platform.Linux;

public sealed class LinuxInputRuntimeOptions
{
    public static LinuxInputRuntimeOptions Default { get; } = new();

    public TimeSpan ReconnectDelay { get; init; } = TimeSpan.FromMilliseconds(750);

    public ILinuxRuntimeObserver? Observer { get; init; }

    public Func<bool>? ShouldGrabExclusiveInput { get; init; }
}
