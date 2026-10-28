using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace GlassToKey.Linux.Runtime;

public sealed class LinuxBackgroundRuntimeController
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    private static readonly TimeSpan StartPollInterval = TimeSpan.FromMilliseconds(100);
    private static readonly TimeSpan StartTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan StopPollInterval = TimeSpan.FromMilliseconds(100);
    private static readonly TimeSpan StopTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan ForceStopTimeout = TimeSpan.FromSeconds(2);

    private readonly string _markerPath;

    public LinuxBackgroundRuntimeController(LinuxRuntimeStateStore? stateStore = null)
    {
        LinuxRuntimeStateStore resolvedStateStore = stateStore ?? new LinuxRuntimeStateStore();
        string statePath = resolvedStateStore.GetStatePath();
        string stateDirectory = Path.GetDirectoryName(statePath)
            ?? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".local",
                "state",
                "GlassToKey.Linux");
        _markerPath = Path.Combine(stateDirectory, "background-runtime.json");
    }

    public string MarkerPath => _markerPath;

    public LinuxBackgroundRuntimeStatus Query()
    {
        BackgroundRuntimeMarker? marker = LoadMarker();
        if (marker == null)
        {
            return new LinuxBackgroundRuntimeStatus(false, null, _markerPath, "The background runtime is not running.");
        }

        if (IsProcessAlive(marker.ProcessId))
        {
            return new LinuxBackgroundRuntimeStatus(
                true,
                marker.ProcessId,
                _markerPath,
                $"The background runtime is running as PID {marker.ProcessId}.");
        }

        DeleteMarker();
        return new LinuxBackgroundRuntimeStatus(false, null, _markerPath, "The background runtime is not running.");
    }

    public async Task<LinuxBackgroundRuntimeStatus> StartAsync(
        bool disableExclusiveGrab = false,
        CancellationToken cancellationToken = default)
    {
        LinuxBackgroundRuntimeStatus current = Query();
        if (current.IsRunning)
        {
            return current with
            {
                Message = $"The background runtime is already running as PID {current.ProcessId}."
            };
        }

        DeleteMarker();
        LaunchDetachedProcess(disableExclusiveGrab);

        Stopwatch stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < StartTimeout)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await Task.Delay(StartPollInterval, cancellationToken).ConfigureAwait(false);

            LinuxBackgroundRuntimeStatus started = Query();
            if (started.IsRunning)
            {
                return started;
            }
        }

        return new LinuxBackgroundRuntimeStatus(
            false,
            null,
            _markerPath,
            "The background runtime did not stay up long enough to confirm startup.");
    }

    public async Task<LinuxBackgroundRuntimeStatus> StopAsync(CancellationToken cancellationToken = default)
    {
        BackgroundRuntimeMarker? marker = LoadMarker();
        if (marker == null || !IsProcessAlive(marker.ProcessId))
        {
            DeleteMarker();
            return new LinuxBackgroundRuntimeStatus(false, null, _markerPath, "The background runtime is not running.");
        }

        if (!SendSignal(marker.ProcessId, SignalTerm))
        {
            DeleteMarker();
            return new LinuxBackgroundRuntimeStatus(false, null, _markerPath, "The background runtime is no longer running.");
        }

        Stopwatch stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < StopTimeout)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await Task.Delay(StopPollInterval, cancellationToken).ConfigureAwait(false);
            if (!IsProcessAlive(marker.ProcessId))
            {
                DeleteMarker();
                return new LinuxBackgroundRuntimeStatus(false, null, _markerPath, "The background runtime has stopped.");
            }
        }

        if (!SendSignal(marker.ProcessId, SignalKill))
        {
            DeleteMarker();
            return new LinuxBackgroundRuntimeStatus(false, null, _markerPath, "The background runtime is no longer running.");
        }

        Stopwatch forceStopwatch = Stopwatch.StartNew();
        while (forceStopwatch.Elapsed < ForceStopTimeout)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await Task.Delay(StopPollInterval, cancellationToken).ConfigureAwait(false);
            if (!IsProcessAlive(marker.ProcessId))
            {
                DeleteMarker();
                return new LinuxBackgroundRuntimeStatus(
                    false,
                    null,
                    _markerPath,
                    $"The background runtime did not stop within {StopTimeout.TotalSeconds:0}s and was force-stopped.");
            }
        }

        return new LinuxBackgroundRuntimeStatus(
            true,
            marker.ProcessId,
            _markerPath,
            $"The background runtime did not stop within {StopTimeout.TotalSeconds:0}s and could not be force-stopped.");
    }

    public async Task<int> RunBackgroundAsync(
        LinuxRuntimeOwner runtimeOwner,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(runtimeOwner);

        using CancellationTokenSource linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        using PosixSignalRegistration sigTermRegistration = PosixSignalRegistration.Create(PosixSignal.SIGTERM, context =>
        {
            context.Cancel = true;
            linkedCts.Cancel();
        });
        using PosixSignalRegistration sigIntRegistration = PosixSignalRegistration.Create(PosixSignal.SIGINT, context =>
        {
            context.Cancel = true;
            linkedCts.Cancel();
        });

        WriteCurrentProcessMarker();
        try
        {
            await runtimeOwner.RunAsync(cancellationToken: linkedCts.Token).ConfigureAwait(false);
            return 0;
        }
        catch (OperationCanceledException) when (linkedCts.IsCancellationRequested)
        {
            return 0;
        }
        finally
        {
            DeleteMarker();
        }
    }

    private void WriteCurrentProcessMarker()
    {
        string? directory = Path.GetDirectoryName(_markerPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        BackgroundRuntimeMarker marker = new(
            ProcessId: Environment.ProcessId,
            StartedUtc: DateTimeOffset.UtcNow);
        string json = JsonSerializer.Serialize(marker, SerializerOptions);
        File.WriteAllText(_markerPath, json);
    }

    private BackgroundRuntimeMarker? LoadMarker()
    {
        if (!File.Exists(_markerPath))
        {
            return null;
        }

        try
        {
            string json = File.ReadAllText(_markerPath);
            return JsonSerializer.Deserialize<BackgroundRuntimeMarker>(json, SerializerOptions);
        }
        catch
        {
            return null;
        }
    }

    private void DeleteMarker()
    {
        try
        {
            if (File.Exists(_markerPath))
            {
                File.Delete(_markerPath);
            }
        }
        catch
        {
            // Best-effort cleanup only.
        }
    }

    private void LaunchDetachedProcess(bool disableExclusiveGrab)
    {
        LaunchSpec launchSpec = ResolveLaunchSpec(disableExclusiveGrab);
        string command = $"nohup setsid {EscapeShellArgument(launchSpec.FileName)} {string.Join(" ", launchSpec.Arguments.Select(EscapeShellArgument))} >/dev/null 2>&1 < /dev/null &";
        using Process shell = Process.Start(new ProcessStartInfo
        {
            FileName = "/bin/sh",
            ArgumentList = { "-c", command },
            UseShellExecute = false
        }) ?? throw new InvalidOperationException("Could not launch the detached runtime shell.");

        shell.WaitForExit();
        if (shell.ExitCode != 0)
        {
            throw new InvalidOperationException($"Detached runtime launch shell exited with code {shell.ExitCode}.");
        }
    }

    private static LaunchSpec ResolveLaunchSpec(bool disableExclusiveGrab)
    {
        string? processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath) && !IsDotnetHost(processPath))
        {
            return new LaunchSpec(processPath, BuildBackgroundArguments("__background-run", disableExclusiveGrab));
        }

        string? entryAssemblyPath = Assembly.GetEntryAssembly()?.Location;
        if (!string.IsNullOrWhiteSpace(entryAssemblyPath))
        {
            List<string> arguments = [entryAssemblyPath];
            arguments.AddRange(BuildBackgroundArguments("__background-run", disableExclusiveGrab));
            return new LaunchSpec("dotnet", arguments);
        }

        throw new InvalidOperationException("Could not resolve how to relaunch the current CLI for background runtime startup.");
    }

    private static IReadOnlyList<string> BuildBackgroundArguments(string command, bool disableExclusiveGrab)
    {
        List<string> arguments = [command];
        if (disableExclusiveGrab)
        {
            arguments.Add("--no-grab");
        }

        return arguments;
    }

    private static bool IsDotnetHost(string path)
    {
        return string.Equals(
            Path.GetFileNameWithoutExtension(path),
            "dotnet",
            StringComparison.OrdinalIgnoreCase);
    }

    private static string EscapeShellArgument(string value)
    {
        return $"'{value.Replace("'", "'\"'\"'", StringComparison.Ordinal)}'";
    }

    private static bool IsProcessAlive(int processId)
    {
        try
        {
            using Process process = Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch
        {
            return false;
        }
    }

    private static bool SendSignal(int processId, int signal)
    {
        try
        {
            return kill(processId, signal) == 0;
        }
        catch
        {
            return false;
        }
    }

    private const int SignalTerm = 15;
    private const int SignalKill = 9;

    [DllImport("libc", SetLastError = true)]
    private static extern int kill(int pid, int sig);

    private sealed record BackgroundRuntimeMarker(
        int ProcessId,
        DateTimeOffset StartedUtc);

    private sealed record LaunchSpec(
        string FileName,
        IReadOnlyList<string> Arguments);
}
