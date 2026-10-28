using GlassToKey.Platform.Linux.Contracts;

namespace GlassToKey.Platform.Linux;

public enum LinuxExclusiveGrabMode
{
    Never = 0,
    DynamicKeyboardMode = 1,
    Always = 2
}

public sealed class LinuxInputRuntimeOptions
{
    public static LinuxInputRuntimeOptions Default { get; } = new();

    public TimeSpan ReconnectDelay { get; init; } = TimeSpan.FromMilliseconds(750);

    public ILinuxRuntimeObserver? Observer { get; init; }

    public LinuxExclusiveGrabMode ExclusiveGrabMode { get; init; } = LinuxExclusiveGrabMode.DynamicKeyboardMode;

    public Func<bool>? ShouldGrabExclusiveInput { get; init; }
}
