using Avalonia;
using Avalonia.Controls;
using System;
using System.Collections.Generic;
using System.Threading;
using GlassToKey.Linux.Runtime;

namespace GlassToKey.Linux.Gui;

internal static class Program
{
    private static Mutex? _singleInstanceMutex;
    public static bool StartHidden { get; private set; }

    [STAThread]
    public static void Main(string[] args)
    {
        string[] forwardedArgs = ParseStartupArguments(args, out bool backgroundRequested, out bool showRequested);
        StartHidden = backgroundRequested && !showRequested;

        _singleInstanceMutex = new Mutex(initiallyOwned: true, "GlassToKey.Linux.Gui.TrayHost", out bool createdNew);
        if (!createdNew)
        {
            if (!StartHidden)
            {
                new LinuxGuiActivationSignalStore().RequestShow();
            }

            _singleInstanceMutex.Dispose();
            _singleInstanceMutex = null;
            return;
        }

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(forwardedArgs, ShutdownMode.OnExplicitShutdown);
    }

    public static AppBuilder BuildAvaloniaApp()
    {
        return AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
    }

    private static string[] ParseStartupArguments(string[] args, out bool backgroundRequested, out bool showRequested)
    {
        backgroundRequested = false;
        showRequested = false;
        List<string> forwarded = new(args.Length);

        for (int index = 0; index < args.Length; index++)
        {
            string argument = args[index];
            if (string.Equals(argument, "--background", StringComparison.OrdinalIgnoreCase))
            {
                backgroundRequested = true;
                continue;
            }

            if (string.Equals(argument, "--show", StringComparison.OrdinalIgnoreCase))
            {
                showRequested = true;
                continue;
            }

            if (string.Equals(argument, "--foreground", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            forwarded.Add(argument);
        }

        return forwarded.ToArray();
    }
}
