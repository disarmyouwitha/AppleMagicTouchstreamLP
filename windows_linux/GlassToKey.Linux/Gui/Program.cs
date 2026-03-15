using Avalonia;
using Avalonia.Controls;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using GlassToKey.Linux.Runtime;

namespace GlassToKey.Linux.Gui;

internal static class Program
{
    private static readonly TimeSpan SignalShutdownTimeout = TimeSpan.FromSeconds(5);
    private static Mutex? _singleInstanceMutex;
    private static int _shutdownRequested;
    public static bool StartHidden { get; private set; }
    public static bool ShowRequested { get; private set; }
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
        ShowRequested = showRequested;
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
        ConsoleCancelEventHandler cancelKeyPressHandler = OnConsoleCancelKeyPress;
        using PosixSignalRegistration sigIntRegistration = RegisterShutdownSignal(PosixSignal.SIGINT);
        using PosixSignalRegistration sigTermRegistration = RegisterShutdownSignal(PosixSignal.SIGTERM);
        using PosixSignalRegistration sigQuitRegistration = RegisterShutdownSignal(PosixSignal.SIGQUIT);
        Console.CancelKeyPress += cancelKeyPressHandler;
        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(forwardedArgs, ShutdownMode.OnExplicitShutdown);
        }
        finally
        {
            Console.CancelKeyPress -= cancelKeyPressHandler;
            hostController.UnregisterCurrentProcess();
            _singleInstanceMutex?.Dispose();
            _singleInstanceMutex = null;
            Interlocked.Exchange(ref _shutdownRequested, 0);
        }
    }

    public static AppBuilder BuildAvaloniaApp()
    {
        return AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
    }

    public static bool TryRelaunchBackground(out string? error)
    {
        error = null;

        try
        {
            RelaunchSpec launchSpec = ResolveRelaunchSpec();
            ProcessStartInfo startInfo = new()
            {
                FileName = launchSpec.FileName,
                UseShellExecute = false
            };

            for (int index = 0; index < launchSpec.Arguments.Count; index++)
            {
                startInfo.ArgumentList.Add(launchSpec.Arguments[index]);
            }

            using Process process = Process.Start(startInfo)
                ?? throw new InvalidOperationException("Process launch returned no process.");
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
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

    private static RelaunchSpec ResolveRelaunchSpec()
    {
        List<string> arguments = ["--background"];
        if (!OwnsRuntime)
        {
            arguments.Add("--no-runtime");
        }

        string? processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath) && !IsDotnetHost(processPath))
        {
            return new RelaunchSpec(processPath, arguments);
        }

        string? entryAssemblyPath = Assembly.GetEntryAssembly()?.Location;
        if (!string.IsNullOrWhiteSpace(entryAssemblyPath))
        {
            return new RelaunchSpec("dotnet", [entryAssemblyPath, .. arguments]);
        }

        throw new InvalidOperationException("Could not resolve how to relaunch GlassToKey Linux GUI.");
    }

    private static bool IsDotnetHost(string path)
    {
        return string.Equals(
            Path.GetFileNameWithoutExtension(path),
            "dotnet",
            StringComparison.OrdinalIgnoreCase);
    }

    private static PosixSignalRegistration RegisterShutdownSignal(PosixSignal signal)
    {
        return PosixSignalRegistration.Create(signal, context =>
        {
            context.Cancel = true;
            RequestGracefulShutdown(signal.ToString());
        });
    }

    private static void OnConsoleCancelKeyPress(object? sender, ConsoleCancelEventArgs e)
    {
        e.Cancel = true;
        RequestGracefulShutdown(nameof(Console.CancelKeyPress));
    }

    private static void RequestGracefulShutdown(string reason)
    {
        if (Interlocked.Exchange(ref _shutdownRequested, 1) != 0)
        {
            return;
        }

        _ = Task.Run(async () =>
        {
            try
            {
                if (Application.Current is App app)
                {
                    Task shutdownTask = app.RequestShutdownAsync(reason);
                    if (await Task.WhenAny(shutdownTask, Task.Delay(SignalShutdownTimeout)).ConfigureAwait(false) == shutdownTask)
                    {
                        await shutdownTask.ConfigureAwait(false);
                    }

                    return;
                }
            }
            catch (Exception ex)
            {
                Trace.WriteLine($"Linux GUI signal shutdown failed ({reason}): {ex}");
            }

            try
            {
                using Process current = Process.GetCurrentProcess();
                current.Kill(entireProcessTree: false);
            }
            catch
            {
                Environment.Exit(0);
            }
        });
    }

    private sealed record RelaunchSpec(
        string FileName,
        IReadOnlyList<string> Arguments);
}
