using GlassToKey.Platform.Linux;
using GlassToKey.Platform.Linux.Contracts;
using GlassToKey.Platform.Linux.Models;
using GlassToKey.Platform.Linux.Uinput;

namespace GlassToKey.Linux.Runtime;

public sealed class LinuxEngineRuntimeController : IDisposable, ILinuxRuntimeObserver
{
    private readonly object _gate = new();
    private readonly LinuxAppRuntime _appRuntime;
    private LinuxEngineRuntimeSnapshot _snapshot = new(LinuxEngineRuntimeStatus.Stopped, "Linux runtime is stopped.", null, Array.Empty<LinuxRuntimeBindingState>());
    private Dictionary<TrackpadSide, LinuxRuntimeBindingState> _bindingStates = new();
    private CancellationTokenSource? _runCts;
    private Task? _runTask;
    private bool _disposed;

    public LinuxEngineRuntimeController(LinuxAppRuntime? appRuntime = null)
    {
        _appRuntime = appRuntime ?? new LinuxAppRuntime();
    }

    public event Action<LinuxEngineRuntimeSnapshot>? SnapshotChanged;

    public LinuxEngineRuntimeSnapshot Snapshot
    {
        get
        {
            lock (_gate)
            {
                return _snapshot;
            }
        }
    }

    public bool TryStart(TimeSpan? duration, out string message)
    {
        LinuxRuntimeConfiguration configuration = _appRuntime.LoadConfiguration();
        if (configuration.Bindings.Count == 0)
        {
            message = "No trackpads are currently resolved for the Linux runtime.";
            PublishSnapshot(LinuxEngineRuntimeStatus.Stopped, message, failure: null, bindingStates: Array.Empty<LinuxRuntimeBindingState>());
            return false;
        }

        lock (_gate)
        {
            ThrowIfDisposed();
            if (_runTask is { IsCompleted: false })
            {
                message = "Linux runtime is already active.";
                return false;
            }

            _bindingStates = new Dictionary<TrackpadSide, LinuxRuntimeBindingState>();
            _runCts = duration.HasValue
                ? new CancellationTokenSource(duration.Value)
                : new CancellationTokenSource();
            _runTask = RunCoreAsync(configuration, _runCts.Token);
        }

        string durationText = duration.HasValue
            ? $"for {duration.Value.TotalSeconds:0.##}s"
            : "until stopped";
        message = $"Starting Linux runtime {durationText}.";
        PublishSnapshot(LinuxEngineRuntimeStatus.Starting, message, failure: null, bindingStates: Array.Empty<LinuxRuntimeBindingState>());
        return true;
    }

    public async Task StopAsync()
    {
        Task? runTask;
        lock (_gate)
        {
            if (_runTask == null)
            {
                return;
            }

            runTask = _runTask;
            PublishSnapshotLocked(LinuxEngineRuntimeStatus.Stopping, "Stopping Linux runtime.", failure: null);
            _runCts?.Cancel();
        }

        try
        {
            await runTask.ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // Normal stop path.
        }
    }

    public void OnBindingStateChanged(LinuxRuntimeBindingState state)
    {
        lock (_gate)
        {
            _bindingStates[state.Side] = state;
            LinuxEngineRuntimeStatus status = _snapshot.Status switch
            {
                LinuxEngineRuntimeStatus.Stopping => LinuxEngineRuntimeStatus.Stopping,
                LinuxEngineRuntimeStatus.Faulted => LinuxEngineRuntimeStatus.Faulted,
                _ => LinuxEngineRuntimeStatus.Running
            };
            PublishSnapshotLocked(status, BuildBindingSummaryLocked(), failure: null);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        StopAsync().GetAwaiter().GetResult();
        lock (_gate)
        {
            _runCts?.Dispose();
            _runCts = null;
            _runTask = null;
            _bindingStates.Clear();
        }
    }

    private async Task RunCoreAsync(LinuxRuntimeConfiguration configuration, CancellationToken cancellationToken)
    {
        try
        {
            using LinuxUinputDispatcher dispatcher = new();
            using TouchProcessorRuntimeHost engine = new(dispatcher, configuration.Keymap, configuration.LayoutPreset);
            LinuxInputRuntimeService runtime = new();
            LinuxInputRuntimeOptions options = new()
            {
                Observer = this
            };
            await runtime.RunAsync(configuration.Bindings, engine, options, cancellationToken).ConfigureAwait(false);
            PublishSnapshot(
                LinuxEngineRuntimeStatus.Stopped,
                cancellationToken.IsCancellationRequested ? "Linux runtime stopped." : "Linux runtime completed.",
                failure: null,
                bindingStates: SnapshotBindingStates());
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            PublishSnapshot(LinuxEngineRuntimeStatus.Stopped, "Linux runtime stopped.", failure: null, bindingStates: SnapshotBindingStates());
        }
        catch (Exception ex)
        {
            PublishSnapshot(LinuxEngineRuntimeStatus.Faulted, "Linux runtime faulted.", ex.Message, bindingStates: SnapshotBindingStates());
        }
        finally
        {
            lock (_gate)
            {
                _runCts?.Dispose();
                _runCts = null;
                _runTask = null;
            }
        }
    }

    private void PublishSnapshot(LinuxEngineRuntimeStatus status, string message, string? failure, IReadOnlyList<LinuxRuntimeBindingState> bindingStates)
    {
        Action<LinuxEngineRuntimeSnapshot>? handler;
        LinuxEngineRuntimeSnapshot snapshot;
        lock (_gate)
        {
            _snapshot = new LinuxEngineRuntimeSnapshot(status, message, failure, bindingStates);
            snapshot = _snapshot;
            handler = SnapshotChanged;
        }

        handler?.Invoke(snapshot);
    }

    private void PublishSnapshotLocked(LinuxEngineRuntimeStatus status, string message, string? failure)
    {
        LinuxEngineRuntimeSnapshot snapshot = new(status, message, failure, SnapshotBindingStatesLocked());
        _snapshot = snapshot;
        Action<LinuxEngineRuntimeSnapshot>? handler = SnapshotChanged;
        Monitor.Exit(_gate);
        try
        {
            handler?.Invoke(snapshot);
        }
        finally
        {
            Monitor.Enter(_gate);
        }
    }

    private IReadOnlyList<LinuxRuntimeBindingState> SnapshotBindingStates()
    {
        lock (_gate)
        {
            return SnapshotBindingStatesLocked();
        }
    }

    private IReadOnlyList<LinuxRuntimeBindingState> SnapshotBindingStatesLocked()
    {
        if (_bindingStates.Count == 0)
        {
            return Array.Empty<LinuxRuntimeBindingState>();
        }

        return _bindingStates.Values
            .OrderBy(static state => state.Side)
            .ToArray();
    }

    private string BuildBindingSummaryLocked()
    {
        IReadOnlyList<LinuxRuntimeBindingState> bindingStates = SnapshotBindingStatesLocked();
        if (bindingStates.Count == 0)
        {
            return "Linux runtime is waiting for binding updates.";
        }

        return string.Join(
            Environment.NewLine,
            bindingStates.Select(static state => $"[{state.Side}] {state.Status}: {state.Message}"));
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }
}
