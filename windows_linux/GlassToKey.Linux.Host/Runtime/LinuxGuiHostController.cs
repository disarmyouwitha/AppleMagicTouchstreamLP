using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace GlassToKey.Linux.Runtime;

public sealed class LinuxGuiHostController
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    private static readonly TimeSpan StopPollInterval = TimeSpan.FromMilliseconds(100);
    private static readonly TimeSpan StopTimeout = TimeSpan.FromSeconds(10);
    private const int SignalTerm = 15;

    private readonly string _markerPath;

    public LinuxGuiHostController(LinuxRuntimeStateStore? stateStore = null)
    {
        LinuxRuntimeStateStore resolvedStateStore = stateStore ?? new LinuxRuntimeStateStore();
        string statePath = resolvedStateStore.GetStatePath();
        string stateDirectory = Path.GetDirectoryName(statePath)
            ?? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".local",
                "state",
                "GlassToKey.Linux");
        _markerPath = Path.Combine(stateDirectory, "tray-host.json");
    }

    public string MarkerPath => _markerPath;

    public LinuxGuiHostStatus Query()
    {
        GuiHostMarker? marker = LoadMarker();
        if (marker == null)
        {
            return new LinuxGuiHostStatus(
                IsRunning: false,
                ProcessId: null,
                OwnsRuntime: false,
                MarkerPath: _markerPath,
                Message: "The tray host is not running.");
        }

        if (IsProcessAlive(marker.ProcessId))
        {
            return new LinuxGuiHostStatus(
                IsRunning: true,
                ProcessId: marker.ProcessId,
                OwnsRuntime: marker.OwnsRuntime,
                MarkerPath: _markerPath,
                Message: marker.OwnsRuntime
                    ? $"The tray host is running as PID {marker.ProcessId} and owns runtime."
                    : $"The tray host is running as PID {marker.ProcessId} (config-only).");
        }

        DeleteMarker();
        return new LinuxGuiHostStatus(
            IsRunning: false,
            ProcessId: null,
            OwnsRuntime: false,
            MarkerPath: _markerPath,
            Message: "The tray host is not running.");
    }

    public async Task<LinuxGuiHostStatus> StopAsync(CancellationToken cancellationToken = default)
    {
        GuiHostMarker? marker = LoadMarker();
        if (marker == null || !IsProcessAlive(marker.ProcessId))
        {
            DeleteMarker();
            return new LinuxGuiHostStatus(
                IsRunning: false,
                ProcessId: null,
                OwnsRuntime: false,
                MarkerPath: _markerPath,
                Message: "The tray host is not running.");
        }

        if (!SendSignal(marker.ProcessId, SignalTerm))
        {
            DeleteMarker();
            return new LinuxGuiHostStatus(
                IsRunning: false,
                ProcessId: null,
                OwnsRuntime: false,
                MarkerPath: _markerPath,
                Message: "The tray host is no longer running.");
        }

        Stopwatch stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < StopTimeout)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await Task.Delay(StopPollInterval, cancellationToken).ConfigureAwait(false);
            if (!IsProcessAlive(marker.ProcessId))
            {
                DeleteMarker();
                return new LinuxGuiHostStatus(
                    IsRunning: false,
                    ProcessId: null,
                    OwnsRuntime: false,
                    MarkerPath: _markerPath,
                    Message: "The tray host has stopped.");
            }
        }

        return new LinuxGuiHostStatus(
            IsRunning: true,
            ProcessId: marker.ProcessId,
            OwnsRuntime: marker.OwnsRuntime,
            MarkerPath: _markerPath,
            Message: $"The tray host did not stop within {StopTimeout.TotalSeconds:0}s.");
    }

    public void RegisterCurrentProcess(bool ownsRuntime)
    {
        string? directory = Path.GetDirectoryName(_markerPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        GuiHostMarker marker = new(
            ProcessId: Environment.ProcessId,
            OwnsRuntime: ownsRuntime,
            StartedUtc: DateTimeOffset.UtcNow);
        string json = JsonSerializer.Serialize(marker, SerializerOptions);
        File.WriteAllText(_markerPath, json);
    }

    public void UnregisterCurrentProcess()
    {
        GuiHostMarker? marker = LoadMarker();
        if (marker == null || marker.ProcessId != Environment.ProcessId)
        {
            return;
        }

        DeleteMarker();
    }

    private GuiHostMarker? LoadMarker()
    {
        if (!File.Exists(_markerPath))
        {
            return null;
        }

        try
        {
            string json = File.ReadAllText(_markerPath);
            return JsonSerializer.Deserialize<GuiHostMarker>(json, SerializerOptions);
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

    [DllImport("libc", SetLastError = true)]
    private static extern int kill(int pid, int sig);

    private sealed record GuiHostMarker(
        int ProcessId,
        bool OwnsRuntime,
        DateTimeOffset StartedUtc);
}

