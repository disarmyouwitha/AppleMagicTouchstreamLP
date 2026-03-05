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
    public static bool OwnsRuntime { get; private set; } = true;

    [STAThread]
    public static void Main(string[] args)
    {
        string[] forwardedArgs = ParseStartupArguments(
            args,
            out bool backgroundRequested,
            out bool showRequested,
            out bool noRuntimeRequested);
        StartHidden = backgroundRequested && !showRequested;
        OwnsRuntime = !noRuntimeRequested;

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

        LinuxGuiHostController hostController = new();
        hostController.RegisterCurrentProcess(OwnsRuntime);
        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(forwardedArgs, ShutdownMode.OnExplicitShutdown);
        }
        finally
        {
            hostController.UnregisterCurrentProcess();
            _singleInstanceMutex?.Dispose();
            _singleInstanceMutex = null;
        }
    }

    public static AppBuilder BuildAvaloniaApp()
    {
        return AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
    }

    private static string[] ParseStartupArguments(
        string[] args,
        out bool backgroundRequested,
        out bool showRequested,
        out bool noRuntimeRequested)
    {
        backgroundRequested = false;
        showRequested = false;
        noRuntimeRequested = false;
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

            if (string.Equals(argument, "--no-runtime", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(argument, "--config-only", StringComparison.OrdinalIgnoreCase))
            {
                noRuntimeRequested = true;
                continue;
            }

            forwarded.Add(argument);
        }

        return forwarded.ToArray();
    }
}
