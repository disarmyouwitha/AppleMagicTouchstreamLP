using Avalonia;
using System;
using System.Threading;
using GlassToKey.Linux.Runtime;

namespace GlassToKey.Linux.Gui;

internal static class Program
{
    private static Mutex? _singleInstanceMutex;

    [STAThread]
    public static void Main(string[] args)
    {
        _singleInstanceMutex = new Mutex(initiallyOwned: true, "GlassToKey.Linux.Gui.TrayHost", out bool createdNew);
        if (!createdNew)
        {
            new LinuxGuiActivationSignalStore().RequestShow();
            _singleInstanceMutex.Dispose();
            _singleInstanceMutex = null;
            return;
        }

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    public static AppBuilder BuildAvaloniaApp()
    {
        return AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
    }
}
