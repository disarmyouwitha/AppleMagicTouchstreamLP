using System.Text.Json;
using GlassToKey;
using GlassToKey.Linux.Config;
using GlassToKey.Platform.Linux;
using GlassToKey.Platform.Linux.Contracts;
using GlassToKey.Platform.Linux.Models;
using GlassToKey.Platform.Linux.Uinput;

namespace GlassToKey.Linux.Runtime;

public sealed class LinuxDesktopRuntimeController : IDisposable, ILinuxInputFrameSink, ILinuxRuntimeObserver
{
    private static readonly TimeSpan SettingsPollInterval = TimeSpan.FromMilliseconds(250);
    private static readonly TimeSpan SessionRestartDelay = TimeSpan.FromMilliseconds(500);
    private static readonly TimeSpan PreviewPublishInterval = TimeSpan.FromMilliseconds(33);
    private static readonly TimeSpan AutocorrectStatusRefreshInterval = TimeSpan.FromMilliseconds(150);
    private const int RuntimeSnapshotSyncTimeoutMs = 4;
    private static readonly JsonSerializerOptions SignatureSerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly object _gate = new();
    private readonly object _captureGate = new();
    private readonly LinuxAppRuntime _appRuntime;
    private readonly LinuxInputRuntimeService _runtime;
    private readonly Dictionary<TrackpadSide, LinuxInputPreviewTrackpadState> _trackpads = new();
    private CancellationTokenSource? _ownerCts;
    private CancellationTokenSource? _captureCts;
    private Task? _ownerTask;
    private TaskCompletionSource<LinuxDesktopAtpCapCaptureResult>? _captureCompletion;
    private RuntimeSession? _session;
    private long _lastPreviewPublishTicks;
    private long _lastAutocorrectStatusRefreshTicks;
    private int _captureFrameCount;
    private bool _disposed;
    private bool _hasAutocorrectStatusSnapshot;
    private LinuxAtpCapCaptureWriter? _captureWriter;
    private AutocorrectStatusSnapshot _autocorrectStatusSnapshot;
    private LinuxDesktopRuntimeSnapshot _runtimeSnapshot = LinuxDesktopRuntimeSnapshot.Stopped;
    private LinuxInputPreviewSnapshot _previewSnapshot = new(
        LinuxInputPreviewStatus.Stopped,
        "The Linux tray runtime is stopped.",
        null,
        Array.Empty<LinuxInputPreviewTrackpadState>());

    public LinuxDesktopRuntimeController(
        LinuxAppRuntime? appRuntime = null,
        LinuxInputRuntimeService? runtime = null)
    {
        _appRuntime = appRuntime ?? new LinuxAppRuntime();
        _runtime = runtime ?? new LinuxInputRuntimeService();
    }

    public event Action<LinuxDesktopRuntimeSnapshot>? RuntimeSnapshotChanged;

    public event Action<LinuxInputPreviewSnapshot>? PreviewSnapshotChanged;

    public LinuxDesktopRuntimeSnapshot RuntimeSnapshot
    {
        get
        {
            lock (_gate)
            {
                return _runtimeSnapshot;
            }
        }
    }

    public LinuxInputPreviewSnapshot PreviewSnapshot
    {
        get
        {
            lock (_gate)
            {
                return _previewSnapshot;
            }
        }
    }

    public bool IsCapturingAtpCap
    {
        get
        {
            lock (_captureGate)
            {
                return _captureWriter != null;
            }
        }
    }

    public bool TryGetAutocorrectStatus(out AutocorrectStatusSnapshot snapshot)
    {
        lock (_gate)
        {
            if (_hasAutocorrectStatusSnapshot)
            {
                snapshot = _autocorrectStatusSnapshot;
                return true;
            }
        }

        snapshot = default;
        return false;
    }

    public LinuxDesktopAtpCapCaptureResult StartAtpCapCapture(
        string outputPath,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(outputPath))
        {
            return new LinuxDesktopAtpCapCaptureResult(false, string.Empty, 0, "Capture path is empty.");
        }

        lock (_gate)
        {
            if (_runtimeSnapshot.Status != LinuxDesktopRuntimeStatus.Running)
            {
                return new LinuxDesktopAtpCapCaptureResult(false, Path.GetFullPath(outputPath), 0, "The Linux tray runtime must be running before capture can start.");
            }
        }

        string fullPath = Path.GetFullPath(outputPath);
        lock (_captureGate)
        {
            if (_captureWriter != null)
            {
                return new LinuxDesktopAtpCapCaptureResult(false, fullPath, 0, "An .atpcap capture is already running.");
            }

            _captureFrameCount = 0;
            _captureWriter = new LinuxAtpCapCaptureWriter(fullPath);
            _captureCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            _captureCompletion = new TaskCompletionSource<LinuxDesktopAtpCapCaptureResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        }

        return new LinuxDesktopAtpCapCaptureResult(true, fullPath, 0, $"Capture started: {fullPath}");
    }

    public Task<LinuxDesktopAtpCapCaptureResult> StopAtpCapCaptureAsync(bool canceled = false)
    {
        TaskCompletionSource<LinuxDesktopAtpCapCaptureResult>? completion;
        lock (_captureGate)
        {
            completion = _captureCompletion;
            if (completion == null)
            {
                return Task.FromResult(new LinuxDesktopAtpCapCaptureResult(false, string.Empty, 0, "No .atpcap capture is currently running."));
            }
        }

        CompleteCapture(success: !canceled, path: null, failure: canceled ? "Capture canceled." : null);
        return completion.Task;
    }

    public Task StartAsync(CancellationToken cancellationToken = default)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            if (_ownerTask is { IsCompleted: false })
            {
                return Task.CompletedTask;
            }

            _ownerCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            _ownerTask = RunOwnerAsync(_ownerCts.Token);
        }

        PublishRuntimeSnapshot(new LinuxDesktopRuntimeSnapshot(
            LinuxDesktopRuntimeStatus.Starting,
            TypingEnabled: false,
            KeyboardModeEnabled: false,
            ActiveLayer: 0,
            UpdatedUtc: DateTimeOffset.UtcNow,
            Message: "Starting the Linux tray runtime.",
            Failure: null));
        PublishPreviewSnapshot(LinuxInputPreviewStatus.Starting, "Starting the Linux tray runtime.", failure: null);
        return Task.CompletedTask;
    }

    public async Task StopAsync()
    {
        Task? ownerTask;
        lock (_gate)
        {
            ownerTask = _ownerTask;
            if (ownerTask == null)
            {
                return;
            }

            _ownerCts?.Cancel();
        }

        PublishRuntimeSnapshot(new LinuxDesktopRuntimeSnapshot(
            LinuxDesktopRuntimeStatus.Stopping,
            TypingEnabled: false,
            KeyboardModeEnabled: false,
            ActiveLayer: 0,
            UpdatedUtc: DateTimeOffset.UtcNow,
            Message: "Stopping the Linux tray runtime.",
            Failure: null));
        PublishPreviewSnapshot(LinuxInputPreviewStatus.Stopping, "Stopping the Linux tray runtime.", failure: null);

        try
        {
            await ownerTask.ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown path.
        }
    }

    public void RequestStop()
    {
        lock (_gate)
        {
            _ownerCts?.Cancel();
        }
    }

    public async ValueTask OnFrameAsync(LinuxRuntimeFrame frame, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        RuntimeSession? session;
        lock (_gate)
        {
            session = _session;
        }

        if (session == null)
        {
            return;
        }

        TrackpadFrameEnvelope envelope = new(
            frame.Binding.Side,
            frame.Snapshot.Frame,
            frame.Snapshot.MaxX,
            frame.Snapshot.MaxY,
            frame.Snapshot.Frame.ArrivalQpcTicks);

        bool publishPreviewImmediately;
        lock (_gate)
        {
            LinuxInputPreviewTrackpadState current = _trackpads.TryGetValue(frame.Binding.Side, out LinuxInputPreviewTrackpadState? existing)
                ? existing
                : CreateTrackpadState(frame.Binding.Side, frame.Binding.Device.StableId, frame.Binding.Device.DeviceNode, LinuxRuntimeBindingStatus.Streaming, "Streaming evdev frames.");

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
            publishPreviewImmediately = count == 0 ||
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
        }

        bool posted = session.Engine.Post(in envelope);
        lock (_captureGate)
        {
            _captureWriter?.WriteFrame(in frame);
            if (_captureWriter != null)
            {
                _captureFrameCount++;
            }
        }
        PublishPreviewIfDue(publishPreviewImmediately);

        if (!posted)
        {
            return;
        }

        TouchProcessorRuntimeSnapshot snapshot;
        bool snapshotReady = publishPreviewImmediately
            ? session.Engine.TryGetSynchronizedSnapshot(RuntimeSnapshotSyncTimeoutMs, out snapshot)
            : session.Engine.TryGetSnapshot(out snapshot);
        if (snapshotReady)
        {
            RefreshAutocorrectStatusCacheIfDue(session);
            PublishRuntimeSnapshot(new LinuxDesktopRuntimeSnapshot(
                LinuxDesktopRuntimeStatus.Running,
                snapshot.TypingEnabled,
                snapshot.KeyboardModeEnabled,
                snapshot.ActiveLayer,
                DateTimeOffset.UtcNow,
                "The Linux tray runtime is active.",
                Failure: null));
        }
    }

    public void OnBindingStateChanged(LinuxRuntimeBindingState state)
    {
        lock (_gate)
        {
            LinuxInputPreviewTrackpadState current = _trackpads.TryGetValue(state.Side, out LinuxInputPreviewTrackpadState? existing)
                ? existing
                : CreateTrackpadState(state.Side, state.StableId, state.DeviceNode, state.Status, state.Message);

            _trackpads[state.Side] = current with
            {
                StableId = state.StableId,
                DeviceNode = state.DeviceNode,
                BindingStatus = state.Status,
                BindingMessage = state.Message
            };
        }

        PublishPreviewSnapshot(
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
            _session?.Dispose();
            _session = null;
            _ownerCts?.Dispose();
            _ownerCts = null;
            _ownerTask = null;
            _trackpads.Clear();
        }

        CompleteCapture(success: false, path: null, failure: "Capture stopped because the Linux tray runtime shut down.");
    }

    private async Task RunOwnerAsync(CancellationToken cancellationToken)
    {
        LinuxRuntimeConfiguration configuration = _appRuntime.LoadConfiguration();
        string settingsSignature = BuildSettingsSignature(configuration.Settings);
        RuntimeSession? localSession = null;
        bool waitingForBindings = false;

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                if (localSession == null)
                {
                    if (configuration.Bindings.Count == 0)
                    {
                        if (!waitingForBindings)
                        {
                            ResetTrackpads(configuration.Bindings);
                            PublishRuntimeSnapshot(new LinuxDesktopRuntimeSnapshot(
                                LinuxDesktopRuntimeStatus.WaitingForBindings,
                                TypingEnabled: false,
                                KeyboardModeEnabled: false,
                                ActiveLayer: 0,
                                UpdatedUtc: DateTimeOffset.UtcNow,
                                Message: "Waiting for trackpad bindings.",
                                Failure: null));
                            PublishPreviewSnapshot(LinuxInputPreviewStatus.Stopped, "Waiting for trackpad bindings.", failure: null);
                            waitingForBindings = true;
                        }
                    }
                    else
                    {
                        localSession = StartSession(configuration, cancellationToken);
                        RefreshAutocorrectStatusCache(localSession, force: true);
                        waitingForBindings = false;
                        PublishPreviewSnapshot(LinuxInputPreviewStatus.Running, "The Linux tray runtime is streaming evdev frames.", failure: null);
                        if (localSession.Engine.TryGetSnapshot(out TouchProcessorRuntimeSnapshot startSnapshot))
                        {
                            PublishRuntimeSnapshot(new LinuxDesktopRuntimeSnapshot(
                                LinuxDesktopRuntimeStatus.Running,
                                startSnapshot.TypingEnabled,
                                startSnapshot.KeyboardModeEnabled,
                                startSnapshot.ActiveLayer,
                                DateTimeOffset.UtcNow,
                                "The Linux tray runtime is active.",
                                Failure: null));
                        }
                    }
                }

                Task pollTask = Task.Delay(SettingsPollInterval, cancellationToken);
                if (localSession != null)
                {
                    Task completed = await Task.WhenAny(localSession.RunTask, pollTask).ConfigureAwait(false);
                    if (completed == localSession.RunTask)
                    {
                        RuntimeSession endedSession = localSession;
                        localSession = null;
                        lock (_gate)
                        {
                            if (ReferenceEquals(_session, endedSession))
                            {
                                _session = null;
                            }
                        }
                        ClearAutocorrectStatusCache();

                        string message = "The tray-owned Linux runtime session stopped unexpectedly; restarting.";
                        string? failure = null;
                        try
                        {
                            await endedSession.RunTask.ConfigureAwait(false);
                        }
                        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                        {
                            break;
                        }
                        catch (Exception ex)
                        {
                            failure = ex.Message;
                            message = $"The tray-owned Linux runtime faulted ({ex.GetType().Name}); restarting.";
                        }
                        finally
                        {
                            endedSession.Dispose();
                        }

                        PublishRuntimeSnapshot(new LinuxDesktopRuntimeSnapshot(
                            LinuxDesktopRuntimeStatus.Faulted,
                            TypingEnabled: false,
                            KeyboardModeEnabled: false,
                            ActiveLayer: 0,
                            UpdatedUtc: DateTimeOffset.UtcNow,
                            Message: message,
                            Failure: failure));
                        PublishPreviewSnapshot(LinuxInputPreviewStatus.Faulted, message, failure);

                        try
                        {
                            await Task.Delay(SessionRestartDelay, cancellationToken).ConfigureAwait(false);
                        }
                        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                        {
                            break;
                        }

                        continue;
                    }
                }
                else
                {
                    await pollTask.ConfigureAwait(false);
                }

                LinuxRuntimeConfiguration updated = _appRuntime.LoadConfiguration();
                string updatedSignature = BuildSettingsSignature(updated.Settings);
                if (updatedSignature == settingsSignature)
                {
                    configuration = updated;
                    continue;
                }

                if (localSession == null)
                {
                    configuration = updated;
                    settingsSignature = updatedSignature;
                    ResetTrackpads(configuration.Bindings);
                    continue;
                }

                if (LinuxRuntimeConfigurationComparer.HaveEquivalentBindings(configuration.Bindings, updated.Bindings))
                {
                    localSession.Engine.Reconfigure(updated.Keymap, updated.LayoutPreset, updated.SharedProfile);
                    configuration = updated;
                    settingsSignature = updatedSignature;
                    continue;
                }

                if (HasActiveTrackpadContacts())
                {
                    continue;
                }

                configuration = updated;
                settingsSignature = updatedSignature;
                ResetTrackpads(configuration.Bindings);
                RuntimeSession completedSession = localSession;
                await completedSession.StopAsync().ConfigureAwait(false);
                completedSession.Dispose();
                localSession = null;
                lock (_gate)
                {
                    if (ReferenceEquals(_session, completedSession))
                    {
                        _session = null;
                    }
                }
                ClearAutocorrectStatusCache();
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal shutdown path.
        }
        catch (Exception ex)
        {
            PublishRuntimeSnapshot(new LinuxDesktopRuntimeSnapshot(
                LinuxDesktopRuntimeStatus.Faulted,
                TypingEnabled: false,
                KeyboardModeEnabled: false,
                ActiveLayer: 0,
                UpdatedUtc: DateTimeOffset.UtcNow,
                Message: "The Linux tray runtime faulted.",
                Failure: ex.Message));
            PublishPreviewSnapshot(LinuxInputPreviewStatus.Faulted, "The Linux tray runtime faulted.", ex.Message);
        }
        finally
        {
            if (localSession != null)
            {
                await localSession.StopAsync().ConfigureAwait(false);
                localSession.Dispose();
            }

            lock (_gate)
            {
                _session = null;
                _ownerTask = null;
                _ownerCts?.Dispose();
                _ownerCts = null;
                _trackpads.Clear();
            }
            ClearAutocorrectStatusCache();

            PublishRuntimeSnapshot(LinuxDesktopRuntimeSnapshot.Stopped with
            {
                UpdatedUtc = DateTimeOffset.UtcNow,
                Message = "The Linux tray runtime is stopped."
            });
            PublishPreviewSnapshot(LinuxInputPreviewStatus.Stopped, "The Linux tray runtime is stopped.", failure: null);
        }
    }

    private RuntimeSession StartSession(LinuxRuntimeConfiguration configuration, CancellationToken cancellationToken)
    {
        CancellationTokenSource sessionCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        LinuxUinputDispatcher dispatcher = new();
        TouchProcessorRuntimeHost engine = new(dispatcher, configuration.Keymap, configuration.LayoutPreset, configuration.SharedProfile);
        ResetTrackpads(configuration.Bindings);
        LinuxInputRuntimeOptions options = new()
        {
            Observer = this
        };
        Task runTask = _runtime.RunAsync([.. configuration.Bindings], this, options, sessionCts.Token);
        RuntimeSession session = new(sessionCts, dispatcher, engine, runTask);
        lock (_gate)
        {
            _session = session;
        }

        return session;
    }

    private void ResetTrackpads(IReadOnlyList<LinuxTrackpadBinding> bindings)
    {
        lock (_gate)
        {
            _trackpads.Clear();
            for (int index = 0; index < bindings.Count; index++)
            {
                LinuxTrackpadBinding binding = bindings[index];
                _trackpads[binding.Side] = CreateTrackpadState(
                    binding.Side,
                    binding.Device.StableId,
                    binding.Device.DeviceNode,
                    LinuxRuntimeBindingStatus.Starting,
                    "Waiting for first runtime frame.");
            }
        }
    }

    private void PublishPreviewIfDue(bool publishImmediately)
    {
        long nowTicks = Environment.TickCount64;
        bool shouldPublish;
        lock (_gate)
        {
            shouldPublish = publishImmediately || nowTicks - _lastPreviewPublishTicks >= PreviewPublishInterval.TotalMilliseconds;
            if (!shouldPublish)
            {
                return;
            }

            _lastPreviewPublishTicks = nowTicks;
        }

        PublishPreviewSnapshot(LinuxInputPreviewStatus.Running, "The Linux tray runtime is streaming evdev frames.", failure: null);
    }

    private void PublishRuntimeSnapshot(LinuxDesktopRuntimeSnapshot snapshot)
    {
        Action<LinuxDesktopRuntimeSnapshot>? handler;
        lock (_gate)
        {
            _runtimeSnapshot = snapshot;
            handler = RuntimeSnapshotChanged;
        }

        handler?.Invoke(snapshot);
    }

    private void PublishPreviewSnapshot(LinuxInputPreviewStatus status, string message, string? failure)
    {
        LinuxInputPreviewSnapshot snapshot;
        Action<LinuxInputPreviewSnapshot>? handler;
        lock (_gate)
        {
            snapshot = new LinuxInputPreviewSnapshot(status, message, failure, SnapshotTrackpadsLocked());
            _previewSnapshot = snapshot;
            handler = PreviewSnapshotChanged;
        }

        handler?.Invoke(snapshot);
    }

    private IReadOnlyList<LinuxInputPreviewTrackpadState> SnapshotTrackpadsLocked()
    {
        if (_trackpads.Count == 0)
        {
            return Array.Empty<LinuxInputPreviewTrackpadState>();
        }

        List<LinuxInputPreviewTrackpadState> states = new(_trackpads.Count);
        foreach (LinuxInputPreviewTrackpadState state in _trackpads.Values.OrderBy(trackpad => trackpad.Side))
        {
            states.Add(state);
        }

        return states;
    }

    private static LinuxInputPreviewTrackpadState CreateTrackpadState(
        TrackpadSide side,
        string stableId,
        string? deviceNode,
        LinuxRuntimeBindingStatus status,
        string message)
    {
        return new LinuxInputPreviewTrackpadState(
            side,
            stableId,
            deviceNode,
            0,
            0,
            false,
            0,
            0,
            status,
            message,
            Array.Empty<LinuxInputPreviewContact>());
    }

    private static string BuildPreviewMessage(LinuxRuntimeBindingStatus status)
    {
        return status switch
        {
            LinuxRuntimeBindingStatus.Starting => "The Linux tray runtime is starting.",
            LinuxRuntimeBindingStatus.Rebinding => "The Linux tray runtime is rebinding a trackpad.",
            LinuxRuntimeBindingStatus.Streaming => "The Linux tray runtime is streaming evdev frames.",
            LinuxRuntimeBindingStatus.WaitingForDevice => "The Linux tray runtime is waiting for a trackpad to return.",
            LinuxRuntimeBindingStatus.Disconnected => "A trackpad disconnected; the runtime is waiting to rebind.",
            LinuxRuntimeBindingStatus.Faulted => "The Linux tray runtime hit a trackpad fault.",
            _ => "The Linux tray runtime is stopped."
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

    private bool HasActiveTrackpadContacts()
    {
        lock (_gate)
        {
            foreach (LinuxInputPreviewTrackpadState trackpad in _trackpads.Values)
            {
                if (trackpad.ContactCount > 0 || CountTipContacts(trackpad.Contacts) > 0)
                {
                    return true;
                }
            }

            return false;
        }
    }

    private static string BuildSettingsSignature(LinuxHostSettings settings)
    {
        LinuxHostSettings normalized = new()
        {
            Version = settings.Version,
            LayoutPresetName = settings.LayoutPresetName,
            KeymapPath = settings.KeymapPath,
            KeymapRevision = settings.KeymapRevision,
            LeftTrackpadStableId = settings.LeftTrackpadStableId,
            RightTrackpadStableId = settings.RightTrackpadStableId,
            SharedProfile = settings.SharedProfile?.Clone() ?? UserSettings.LoadBundledDefaultsOrDefault()
        };
        normalized.Normalize();
        return JsonSerializer.Serialize(normalized, SignatureSerializerOptions);
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    private void RefreshAutocorrectStatusCacheIfDue(RuntimeSession session)
    {
        long nowTicks = Environment.TickCount64;
        bool shouldRefresh;
        lock (_gate)
        {
            shouldRefresh = nowTicks - _lastAutocorrectStatusRefreshTicks >= AutocorrectStatusRefreshInterval.TotalMilliseconds;
        }

        if (!shouldRefresh)
        {
            return;
        }

        RefreshAutocorrectStatusCache(session, force: false);
    }

    private void RefreshAutocorrectStatusCache(RuntimeSession session, bool force)
    {
        if (!force)
        {
            long nowTicks = Environment.TickCount64;
            lock (_gate)
            {
                if (nowTicks - _lastAutocorrectStatusRefreshTicks < AutocorrectStatusRefreshInterval.TotalMilliseconds)
                {
                    return;
                }
            }
        }

        if (!session.TryGetAutocorrectStatus(out AutocorrectStatusSnapshot snapshot))
        {
            return;
        }

        lock (_gate)
        {
            _autocorrectStatusSnapshot = snapshot;
            _hasAutocorrectStatusSnapshot = true;
            _lastAutocorrectStatusRefreshTicks = Environment.TickCount64;
        }
    }

    private void ClearAutocorrectStatusCache()
    {
        lock (_gate)
        {
            _autocorrectStatusSnapshot = default;
            _hasAutocorrectStatusSnapshot = false;
            _lastAutocorrectStatusRefreshTicks = 0;
        }
    }

    private void CompleteCapture(bool success, string? path, string? failure)
    {
        TaskCompletionSource<LinuxDesktopAtpCapCaptureResult>? completion;
        LinuxAtpCapCaptureWriter? writer;
        CancellationTokenSource? captureCts;
        int frameCount;
        string resolvedPath;
        lock (_captureGate)
        {
            completion = _captureCompletion;
            writer = _captureWriter;
            captureCts = _captureCts;
            frameCount = _captureFrameCount;
            resolvedPath = path ?? writer?.Path ?? string.Empty;
            _captureCompletion = null;
            _captureWriter = null;
            _captureCts = null;
            _captureFrameCount = 0;
        }

        if (completion == null)
        {
            return;
        }

        try
        {
            writer?.Dispose();
        }
        finally
        {
            captureCts?.Cancel();
            captureCts?.Dispose();
        }

        string summary = success
            ? $"Capture written: {resolvedPath} ({frameCount} frames)"
            : failure ?? "Capture did not complete.";
        completion.TrySetResult(new LinuxDesktopAtpCapCaptureResult(success, resolvedPath, frameCount, summary));
    }

    private sealed class RuntimeSession : IDisposable
    {
        private readonly CancellationTokenSource _cts;
        private readonly LinuxUinputDispatcher _dispatcher;
        private bool _disposed;

        public RuntimeSession(
            CancellationTokenSource cts,
            LinuxUinputDispatcher dispatcher,
            TouchProcessorRuntimeHost engine,
            Task runTask)
        {
            _cts = cts;
            _dispatcher = dispatcher;
            Engine = engine;
            RunTask = runTask;
        }

        public TouchProcessorRuntimeHost Engine { get; }

        public Task RunTask { get; }

        public bool TryGetAutocorrectStatus(out AutocorrectStatusSnapshot snapshot)
        {
            if (_disposed)
            {
                snapshot = default;
                return false;
            }

            snapshot = _dispatcher.GetAutocorrectStatus();
            return true;
        }

        public async Task StopAsync()
        {
            if (_disposed || _cts.IsCancellationRequested)
            {
                return;
            }

            _cts.Cancel();
            try
            {
                await RunTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // Normal shutdown path for a canceled runtime session.
            }
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            Engine.Dispose();
            _dispatcher.Dispose();
            _cts.Dispose();
        }
    }
}

public readonly record struct LinuxDesktopAtpCapCaptureResult(
    bool Success,
    string OutputPath,
    int FrameCount,
    string Summary);
