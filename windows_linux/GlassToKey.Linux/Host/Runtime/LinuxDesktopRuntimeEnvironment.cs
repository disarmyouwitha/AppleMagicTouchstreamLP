namespace GlassToKey.Linux.Runtime;

public static class LinuxDesktopRuntimeEnvironment
{
    private static readonly Lazy<LinuxDesktopRuntimeController> SharedControllerFactory =
        new(() => new LinuxDesktopRuntimeController());

    public static LinuxDesktopRuntimeController SharedController => SharedControllerFactory.Value;
}
