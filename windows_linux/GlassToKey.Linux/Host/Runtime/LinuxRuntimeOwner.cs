using System.Text.Json;
using GlassToKey.Linux.Config;
using GlassToKey.Platform.Linux;
using GlassToKey.Platform.Linux.Contracts;
using GlassToKey.Platform.Linux.Models;
using GlassToKey.Platform.Linux.Uinput;

namespace GlassToKey.Linux.Runtime;

public sealed class LinuxRuntimeOwner
{
    private static readonly TimeSpan SettingsPollInterval = TimeSpan.FromMilliseconds(250);
    private static readonly TimeSpan SessionRestartDelay = TimeSpan.FromMilliseconds(500);
    private static readonly JsonSerializerOptions SignatureSerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly LinuxAppRuntime _appRuntime;
    private readonly LinuxInputRuntimeService _runtime;
    private readonly LinuxRuntimeStateStore _stateStore;
    private readonly LinuxRuntimePolicy _policy;
    private readonly bool _disableExclusiveGrab;

    public LinuxRuntimeOwner(
        LinuxAppRuntime? appRuntime = null,
        LinuxInputRuntimeService? runtime = null,
        LinuxRuntimeStateStore? stateStore = null,
        LinuxRuntimePolicy policy = LinuxRuntimePolicy.DesktopInteractive,
        bool disableExclusiveGrab = false)
    {
        _appRuntime = appRuntime ?? new LinuxAppRuntime();
        _runtime = runtime ?? new LinuxInputRuntimeService();
        _stateStore = stateStore ?? new LinuxRuntimeStateStore();
        _policy = policy;
        _disableExclusiveGrab = disableExclusiveGrab;
    }

    public async Task RunAsync(
        ILinuxRuntimeObserver? observer = null,
        Action<string>? logger = null,
        CancellationToken cancellationToken = default)
    {
        _ = logger;
        LinuxRuntimeConfiguration configuration = _appRuntime.LoadConfiguration(_policy);
        string settingsSignature = BuildSettingsSignature(configuration.Settings);
        RuntimeSession? session = null;
        bool waitingForBindingsLogged = false;

        try
        {
            PersistStoppedState();
            while (!cancellationToken.IsCancellationRequested)
            {
                if (session == null)
                {
                    if (configuration.Bindings.Count == 0)
                    {
                        if (!waitingForBindingsLogged)
                        {
                            waitingForBindingsLogged = true;
                        }
                    }
                    else
                    {
                        session = StartSession(configuration, observer, cancellationToken);
                        waitingForBindingsLogged = false;
                    }
                }

                Task pollTask = Task.Delay(SettingsPollInterval, cancellationToken);
                if (session != null)
                {
                    Task completed = await Task.WhenAny(session.RunTask, pollTask).ConfigureAwait(false);
                    if (completed == session.RunTask)
                    {
                        RuntimeSession completedSession = session;
                        session = null;
                        try
                        {
                            await completedSession.RunTask.ConfigureAwait(false);
                        }
                        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                        {
                            break;
                        }
                        catch (Exception ex)
                        {
                            _ = ex;
                        }
                        finally
                        {
                            completedSession.Dispose();
                        }

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

                if (session != null && session.TryGetSnapshot(out TouchProcessorRuntimeSnapshot snapshot))
                {
                    PersistRunningState(snapshot);
                }

                LinuxRuntimeConfiguration updated = _appRuntime.LoadConfiguration(_policy);
                string updatedSignature = BuildSettingsSignature(updated.Settings);
                if (updatedSignature == settingsSignature)
                {
                    configuration = updated;
                    continue;
                }

                if (session == null)
                {
                    configuration = updated;
                    settingsSignature = updatedSignature;
                    continue;
                }

                if (LinuxRuntimeConfigurationComparer.HaveEquivalentBindings(configuration.Bindings, updated.Bindings))
                {
                    session.Dispatcher.SetHapticRoutes(updated.Bindings);
                    session.Dispatcher.ConfigureHaptics(updated.SharedProfile);
                    session.Dispatcher.WarmupHaptics();
                    session.Engine.Reconfigure(
                        updated.Keymap,
                        updated.LayoutPreset,
                        updated.SharedProfile,
                        ignoreTypingToggleActions: _policy.IgnoresTypingToggleActions(),
                        pureKeyboardIntent: _policy.UsesPureKeyboardIntent());
                    configuration = updated;
                    settingsSignature = updatedSignature;
                    continue;
                }

                if (session.TryGetSnapshot(out TouchProcessorRuntimeSnapshot pendingSnapshot) &&
                    (HasActiveContacts(pendingSnapshot) || session.Engine.RequestsExclusiveInput))
                {
                    continue;
                }

                configuration = updated;
                settingsSignature = updatedSignature;
                await session.StopAsync().ConfigureAwait(false);
                session.Dispose();
                session = null;
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal shutdown path.
        }
        finally
        {
            if (session != null)
            {
                await session.StopAsync().ConfigureAwait(false);
                session.Dispose();
            }

            PersistStoppedState();
        }
    }

    private RuntimeSession StartSession(
        LinuxRuntimeConfiguration configuration,
        ILinuxRuntimeObserver? observer,
        CancellationToken cancellationToken)
    {
        CancellationTokenSource sessionCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        LinuxUinputDispatcher uinputDispatcher = new();
        uinputDispatcher.SetHapticRoutes(configuration.Bindings);
        uinputDispatcher.ConfigureHaptics(configuration.SharedProfile);
        uinputDispatcher.WarmupHaptics();
        LinuxAppLaunchDispatcher dispatcher = new(uinputDispatcher);
        TouchProcessorRuntimeHost engine = new(
            dispatcher,
            configuration.Keymap,
            configuration.LayoutPreset,
            configuration.SharedProfile,
            ignoreTypingToggleActions: _policy.IgnoresTypingToggleActions(),
            pureKeyboardIntent: _policy.UsesPureKeyboardIntent());
        RuntimeSession? session = null;
        LinuxInputRuntimeOptions options = new()
        {
            Observer = observer,
            ExclusiveGrabMode = _policy.ResolveExclusiveGrabMode(_disableExclusiveGrab, LinuxGuiLauncher.IsGraphicalSession()),
            ShouldGrabExclusiveInput = () => ShouldGrabExclusiveInput(session, configuration.SharedProfile)
        };
        Task runTask = _runtime.RunAsync([.. configuration.Bindings], engine, options, sessionCts.Token);
        session = new RuntimeSession(sessionCts, dispatcher, uinputDispatcher, engine, runTask);
        return session;
    }

    private static bool ShouldGrabExclusiveInput(RuntimeSession? session, UserSettings fallbackProfile)
    {
        if (session != null && session.Engine.TryGetSnapshot(out TouchProcessorRuntimeSnapshot snapshot))
        {
            return session.Engine.RequestsExclusiveInput ||
                   (snapshot.KeyboardModeEnabled &&
                    snapshot.TypingEnabled &&
                    !snapshot.MomentaryLayerActive);
        }

        return fallbackProfile.KeyboardModeEnabled && fallbackProfile.TypingEnabled;
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

    private void PersistRunningState(in TouchProcessorRuntimeSnapshot snapshot)
    {
        _stateStore.Save(new LinuxRuntimeStateSnapshot(
            IsRunning: true,
            TypingEnabled: snapshot.TypingEnabled,
            KeyboardModeEnabled: snapshot.KeyboardModeEnabled,
            ActiveLayer: snapshot.ActiveLayer,
            UpdatedUtc: DateTimeOffset.UtcNow));
    }

    private void PersistStoppedState()
    {
        _stateStore.Save(new LinuxRuntimeStateSnapshot(
            IsRunning: false,
            TypingEnabled: false,
            KeyboardModeEnabled: false,
            ActiveLayer: 0,
            UpdatedUtc: DateTimeOffset.UtcNow));
    }

    private static bool HasActiveContacts(in TouchProcessorRuntimeSnapshot snapshot)
    {
        return snapshot.LeftContacts > 0 ||
               snapshot.RightContacts > 0 ||
               snapshot.LastFrameLeftContacts > 0 ||
               snapshot.LastFrameRightContacts > 0 ||
               snapshot.LastRawLeftContacts > 0 ||
               snapshot.LastRawRightContacts > 0;
    }

    private sealed class RuntimeSession : IDisposable
    {
        private readonly CancellationTokenSource _cts;
        private readonly LinuxAppLaunchDispatcher _dispatcher;
        private readonly LinuxUinputDispatcher _uinputDispatcher;
        private readonly TouchProcessorRuntimeHost _engine;
        private bool _disposed;

        public RuntimeSession(
            CancellationTokenSource cts,
            LinuxAppLaunchDispatcher dispatcher,
            LinuxUinputDispatcher uinputDispatcher,
            TouchProcessorRuntimeHost engine,
            Task runTask)
        {
            _cts = cts;
            _dispatcher = dispatcher;
            _uinputDispatcher = uinputDispatcher;
            _engine = engine;
            RunTask = runTask;
        }

        public TouchProcessorRuntimeHost Engine => _engine;

        public LinuxUinputDispatcher Dispatcher => _uinputDispatcher;

        public Task RunTask { get; }

        public bool TryGetSnapshot(out TouchProcessorRuntimeSnapshot snapshot)
        {
            return _engine.TryGetSnapshot(out snapshot);
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
            _engine.Dispose();
            _dispatcher.Dispose();
            _cts.Dispose();
        }
    }

}
