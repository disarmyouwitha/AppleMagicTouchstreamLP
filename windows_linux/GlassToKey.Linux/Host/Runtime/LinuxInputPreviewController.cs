using GlassToKey.Platform.Linux;
using GlassToKey.Platform.Linux.Contracts;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Runtime;

public sealed class LinuxInputPreviewController : IDisposable, ILinuxInputFrameSink, ILinuxRuntimeObserver
{
    private static readonly TimeSpan PublishInterval = TimeSpan.FromMilliseconds(33);

    private readonly object _gate = new();
    private readonly LinuxAppRuntime _appRuntime;
    private readonly LinuxInputRuntimeService _runtime;
    private readonly Dictionary<TrackpadSide, LinuxInputPreviewTrackpadState> _trackpads = new();
    private LinuxInputPreviewSnapshot _snapshot = new(
        LinuxInputPreviewStatus.Stopped,
        "Live input preview is stopped.",
        null,
        Array.Empty<LinuxInputPreviewTrackpadState>());
    private CancellationTokenSource? _runCts;
    private Task? _runTask;
    private long _lastPublishTicks;
    private bool _disposed;

    public LinuxInputPreviewController(
        LinuxAppRuntime? appRuntime = null,
        LinuxInputRuntimeService? runtime = null)
    {
        _appRuntime = appRuntime ?? new LinuxAppRuntime();
        _runtime = runtime ?? new LinuxInputRuntimeService();
    }

    public event Action<LinuxInputPreviewSnapshot>? SnapshotChanged;

    public LinuxInputPreviewSnapshot Snapshot
    {
        get
        {
            lock (_gate)
            {
                return _snapshot;
            }
        }
    }

    public bool TryStart(out string message)
    {
        LinuxRuntimeConfiguration configuration = _appRuntime.LoadConfiguration();
        if (configuration.Bindings.Count == 0)
        {
            message = "No trackpads are currently resolved for live preview.";
            PublishSnapshot(LinuxInputPreviewStatus.Stopped, message, failure: null);
            return false;
        }

        lock (_gate)
        {
            ThrowIfDisposed();
            if (_runTask is { IsCompleted: false })
            {
                message = "Live input preview is already active.";
                return false;
            }

            _trackpads.Clear();
            for (int index = 0; index < configuration.Bindings.Count; index++)
            {
                LinuxTrackpadBinding binding = configuration.Bindings[index];
                _trackpads[binding.Side] = new LinuxInputPreviewTrackpadState(
                    binding.Side,
                    binding.Device.StableId,
                    binding.Device.DeviceNode,
                    0,
                    0,
                    false,
                    0,
                    0,
                    LinuxRuntimeBindingStatus.Starting,
                    "Waiting for first preview frame.",
                    Array.Empty<LinuxInputPreviewContact>());
            }

            _runCts = new CancellationTokenSource();
            _runTask = RunCoreAsync([.. configuration.Bindings], _runCts.Token);
        }

        message = "Starting live input preview.";
        PublishSnapshot(LinuxInputPreviewStatus.Starting, message, failure: null);
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
        }

        PublishSnapshot(LinuxInputPreviewStatus.Stopping, "Stopping live input preview.", failure: null);
        _runCts?.Cancel();

        try
        {
            await runTask.ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // Normal stop path.
        }
    }

    public ValueTask OnFrameAsync(LinuxRuntimeFrame frame, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        LinuxInputPreviewSnapshot? snapshotToPublish = null;
        Action<LinuxInputPreviewSnapshot>? handler = null;
        lock (_gate)
        {
            LinuxInputPreviewTrackpadState current = _trackpads.TryGetValue(frame.Binding.Side, out LinuxInputPreviewTrackpadState? existing)
                ? existing
                : new LinuxInputPreviewTrackpadState(
                    frame.Binding.Side,
                    frame.Binding.Device.StableId,
                    frame.Binding.Device.DeviceNode,
                    0,
                    0,
                    false,
                    0,
                    0,
                    LinuxRuntimeBindingStatus.Streaming,
                    "Streaming evdev frames.",
                    Array.Empty<LinuxInputPreviewContact>());

            InputFrame input = frame.Snapshot.Frame;
            int count = input.GetClampedContactCount();
            LinuxInputPreviewContact[] contacts = new LinuxInputPreviewContact[count];
            for (int index = 0; index < count; index++)
            {
                ContactFrame contact = input.GetContact(index);
                contacts[index] = new LinuxInputPreviewContact(
                    contact.Id,
                    contact.X,
                    contact.Y,
                    contact.Pressure8,
                    contact.TipSwitch,
                    contact.Confidence);
            }

            int previousTipContacts = CountTipContacts(current.Contacts);
            int nextTipContacts = CountTipContacts(contacts);
            bool publishImmediately =
                count == 0 ||
                current.ContactCount != count ||
                previousTipContacts != nextTipContacts;

            _trackpads[frame.Binding.Side] = current with
            {
                DeviceNode = frame.Snapshot.DeviceNode,
                MaxX = frame.Snapshot.MaxX,
                MaxY = frame.Snapshot.MaxY,
                IsButtonPressed = input.IsButtonPressed,
                ContactCount = count,
                FrameSequence = frame.Snapshot.FrameSequence,
                BindingStatus = LinuxRuntimeBindingStatus.Streaming,
                BindingMessage = "Streaming evdev frames.",
                Contacts = contacts
            };

            long nowTicks = Environment.TickCount64;
            if (publishImmediately || nowTicks - _lastPublishTicks >= PublishInterval.TotalMilliseconds)
            {
                _lastPublishTicks = nowTicks;
                _snapshot = new LinuxInputPreviewSnapshot(
                    LinuxInputPreviewStatus.Running,
                    "Live input preview is running.",
                    null,
                    SnapshotTrackpadsLocked());
                snapshotToPublish = _snapshot;
                handler = SnapshotChanged;
            }
        }

        handler?.Invoke(snapshotToPublish!);
        return ValueTask.CompletedTask;
    }

    public void OnBindingStateChanged(LinuxRuntimeBindingState state)
    {
        LinuxInputPreviewTrackpadState next;
        lock (_gate)
        {
            LinuxInputPreviewTrackpadState current = _trackpads.TryGetValue(state.Side, out LinuxInputPreviewTrackpadState? existing)
                ? existing
                : new LinuxInputPreviewTrackpadState(
                    state.Side,
                    state.StableId,
                    state.DeviceNode,
                    0,
                    0,
                    false,
                    0,
                    0,
                    state.Status,
                    state.Message,
                    Array.Empty<LinuxInputPreviewContact>());

            next = current with
            {
                StableId = state.StableId,
                DeviceNode = state.DeviceNode,
                BindingStatus = state.Status,
                BindingMessage = state.Message
            };
            _trackpads[state.Side] = next;
        }

        PublishSnapshot(
            state.Status == LinuxRuntimeBindingStatus.Faulted ? LinuxInputPreviewStatus.Faulted : LinuxInputPreviewStatus.Running,
            BuildPreviewMessage(state.Status),
            state.Status == LinuxRuntimeBindingStatus.Faulted ? state.Message : null);
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
            _trackpads.Clear();
        }
    }

    private async Task RunCoreAsync(
        IReadOnlyList<LinuxTrackpadBinding> bindings,
        CancellationToken cancellationToken)
    {
        try
        {
            LinuxInputRuntimeOptions options = new()
            {
                Observer = this
            };
            await _runtime.RunAsync(bindings, this, options, cancellationToken).ConfigureAwait(false);
            PublishSnapshot(
                LinuxInputPreviewStatus.Stopped,
                cancellationToken.IsCancellationRequested ? "Live input preview stopped." : "Live input preview completed.",
                failure: null);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            PublishSnapshot(LinuxInputPreviewStatus.Stopped, "Live input preview stopped.", failure: null);
        }
        catch (Exception ex)
        {
            PublishSnapshot(LinuxInputPreviewStatus.Faulted, "Live input preview faulted.", ex.Message);
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

    private void PublishSnapshot(LinuxInputPreviewStatus status, string message, string? failure)
    {
        Action<LinuxInputPreviewSnapshot>? handler;
        LinuxInputPreviewSnapshot snapshot;
        lock (_gate)
        {
            _snapshot = new LinuxInputPreviewSnapshot(status, message, failure, SnapshotTrackpadsLocked());
            snapshot = _snapshot;
            handler = SnapshotChanged;
        }

        handler?.Invoke(snapshot);
    }

    private IReadOnlyList<LinuxInputPreviewTrackpadState> SnapshotTrackpadsLocked()
    {
        if (_trackpads.Count == 0)
        {
            return Array.Empty<LinuxInputPreviewTrackpadState>();
        }

        return _trackpads.Values
            .OrderBy(static state => state.Side)
            .ToArray();
    }

    private static string BuildPreviewMessage(LinuxRuntimeBindingStatus status)
    {
        return status switch
        {
            LinuxRuntimeBindingStatus.WaitingForDevice => "Live input preview is waiting for a trackpad to reappear.",
            LinuxRuntimeBindingStatus.Rebinding => "Live input preview is rebinding to a trackpad.",
            LinuxRuntimeBindingStatus.Faulted => "Live input preview found a binding fault.",
            LinuxRuntimeBindingStatus.Stopped => "Live input preview is stopped.",
            _ => "Live input preview is running."
        };
    }

    private static int CountTipContacts(IReadOnlyList<LinuxInputPreviewContact> contacts)
    {
        int count = 0;
        for (int index = 0; index < contacts.Count; index++)
        {
            if (contacts[index].TipSwitch)
            {
                count++;
            }
        }

        return count;
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }
}
