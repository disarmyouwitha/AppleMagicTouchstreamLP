namespace GlassToKey;

public sealed class TouchProcessorRuntimeHost : ITrackpadFrameTarget, IDisposable
{
    private readonly IInputDispatcher _dispatcher;
    private readonly DispatchEventQueue _dispatchQueue;
    private readonly DispatchEventPump _dispatchPump;
    private readonly TouchProcessorActor _actor;
    private bool _disposed;

    public TouchProcessorRuntimeHost(
        IInputDispatcher dispatcher,
        KeymapStore? keymap = null,
        TrackpadLayoutPreset? preset = null,
        UserSettings? settings = null)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        _dispatcher = dispatcher;

        KeymapStore resolvedKeymap = keymap ?? KeymapStore.LoadBundledDefault();
        TouchProcessorCore core = settings == null
            ? TouchProcessorFactory.CreateDefault(resolvedKeymap, preset)
            : TouchProcessorFactory.CreateConfigured(resolvedKeymap, settings, preset);
        _dispatchQueue = new DispatchEventQueue();
        _actor = new TouchProcessorActor(core, dispatchQueue: _dispatchQueue);
        _actor.SetHapticsOnKeyDispatchEnabled(false);
        _dispatchPump = new DispatchEventPump(_dispatchQueue, dispatcher);
        if (settings != null)
        {
            ConfigureDispatcherAutocorrect(dispatcher, settings);
        }
    }

    public bool Post(in TrackpadFrameEnvelope frame)
    {
        if (_disposed)
        {
            return false;
        }

        InputFrame payload = frame.Frame;
        return _actor.Post(frame.Side, in payload, frame.MaxX, frame.MaxY, frame.TimestampTicks);
    }

    public bool TryGetSnapshot(out TouchProcessorRuntimeSnapshot snapshot)
    {
        if (_disposed)
        {
            snapshot = default;
            return false;
        }

        TouchProcessorSnapshot engineSnapshot = _actor.Snapshot();
        DispatchEventPumpDiagnostics pumpSnapshot = _dispatchPump.Snapshot();
        InputDispatcherDiagnostics dispatcherSnapshot = default;
        if (_dispatcher is IInputDispatcherDiagnosticsProvider diagnosticsProvider)
        {
            diagnosticsProvider.TryGetDiagnostics(out dispatcherSnapshot);
        }

        snapshot = new TouchProcessorRuntimeSnapshot(
            ActiveLayer: engineSnapshot.ActiveLayer,
            MomentaryLayerActive: engineSnapshot.MomentaryLayerActive,
            TypingEnabled: engineSnapshot.TypingEnabled,
            KeyboardModeEnabled: engineSnapshot.KeyboardModeEnabled,
            ContactCount: engineSnapshot.ContactCount,
            LeftContacts: engineSnapshot.LeftContacts,
            RightContacts: engineSnapshot.RightContacts,
            LastFrameLeftContacts: engineSnapshot.LastFrameLeftContacts,
            LastFrameRightContacts: engineSnapshot.LastFrameRightContacts,
            LastRawLeftContacts: engineSnapshot.LastRawLeftContacts,
            LastRawRightContacts: engineSnapshot.LastRawRightContacts,
            LastOnKeyLeftContacts: engineSnapshot.LastOnKeyLeftContacts,
            LastOnKeyRightContacts: engineSnapshot.LastOnKeyRightContacts,
            LastChordSuppressedLeft: engineSnapshot.LastChordSuppressedLeft,
            LastChordSuppressedRight: engineSnapshot.LastChordSuppressedRight,
            TouchStateCount: engineSnapshot.TouchStateCount,
            IntentTouchStateCount: engineSnapshot.IntentTouchStateCount,
            GesturePriorityLeft: engineSnapshot.GesturePriorityLeft,
            GesturePriorityRight: engineSnapshot.GesturePriorityRight,
            ChordShiftLeft: engineSnapshot.ChordShiftLeft,
            ChordShiftRight: engineSnapshot.ChordShiftRight,
            IntentMode: engineSnapshot.IntentMode.ToString(),
            FramesProcessed: engineSnapshot.FramesProcessed,
            QueueDrops: engineSnapshot.QueueDrops,
            StaleTouchExpirations: engineSnapshot.StaleTouchExpirations,
            ReleaseDroppedTotal: engineSnapshot.ReleaseDroppedTotal,
            ReleaseDroppedGesturePriority: engineSnapshot.ReleaseDroppedGesturePriority,
            LastReleaseDroppedTicks: engineSnapshot.LastReleaseDroppedTicks,
            LastReleaseDroppedReason: engineSnapshot.LastReleaseDroppedReason,
            DispatchEnqueued: engineSnapshot.DispatchEnqueued,
            DispatchSuppressedTypingDisabled: engineSnapshot.DispatchSuppressedTypingDisabled,
            DispatchSuppressedRingFull: engineSnapshot.DispatchSuppressedRingFull,
            DispatchQueueCount: _dispatchQueue.Count,
            DispatchQueueDrops: _dispatchQueue.Drops,
            DispatchPumpAlive: pumpSnapshot.IsAlive,
            DispatchPumpDispatchCalls: pumpSnapshot.DispatchCalls,
            DispatchPumpTickCalls: pumpSnapshot.TickCalls,
            DispatchPumpLastDispatchTicks: pumpSnapshot.LastDispatchTicks,
            DispatchPumpLastTickTicks: pumpSnapshot.LastTickTicks,
            DispatchPumpLastFaultTicks: pumpSnapshot.LastFaultTicks,
            DispatchPumpLastFault: pumpSnapshot.LastFaultMessage,
            DispatcherDispatchCalls: dispatcherSnapshot.DispatchCalls,
            DispatcherTickCalls: dispatcherSnapshot.TickCalls,
            DispatcherSendFailures: dispatcherSnapshot.SendFailures,
            DispatcherActiveRepeats: dispatcherSnapshot.ActiveRepeats,
            DispatcherKeysDown: dispatcherSnapshot.KeysDown,
            DispatcherActiveModifiers: dispatcherSnapshot.ActiveModifiers,
            DispatcherLastDispatchTicks: dispatcherSnapshot.LastDispatchTicks,
            DispatcherLastTickTicks: dispatcherSnapshot.LastTickTicks,
            DispatcherLastError: dispatcherSnapshot.LastErrorMessage);
        return true;
    }

    public bool TryGetSynchronizedSnapshot(int timeoutMs, out TouchProcessorRuntimeSnapshot snapshot)
    {
        if (_disposed)
        {
            snapshot = default;
            return false;
        }

        if (timeoutMs > 0)
        {
            _actor.WaitForIdle(timeoutMs);
        }

        return TryGetSnapshot(out snapshot);
    }

    public void Reconfigure(
        KeymapStore keymap,
        TrackpadLayoutPreset preset,
        UserSettings settings)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(keymap);
        ArgumentNullException.ThrowIfNull(preset);
        ArgumentNullException.ThrowIfNull(settings);

        UserSettings profile = settings.Clone();
        profile.NormalizeRanges();
        profile.LayoutPresetName = preset.Name;
        keymap.SetActiveLayout(preset.Name);

        ColumnLayoutSettings[] columns = RuntimeConfigurationFactory.BuildColumnSettingsForPreset(profile, preset);
        RuntimeConfigurationFactory.BuildLayouts(profile, keymap, preset, columns, out KeyLayout leftLayout, out KeyLayout rightLayout);

        int activeLayer = Math.Clamp(profile.ActiveLayer, 0, 7);
        bool typingEnabled = profile.TypingEnabled;
        bool keyboardModeEnabled = profile.KeyboardModeEnabled;
        if (TryGetSnapshot(out TouchProcessorRuntimeSnapshot snapshot))
        {
            activeLayer = Math.Clamp(snapshot.ActiveLayer, 0, 7);
            typingEnabled = snapshot.TypingEnabled;
            keyboardModeEnabled = snapshot.KeyboardModeEnabled;
        }

        _actor.Configure(RuntimeConfigurationFactory.BuildTouchConfig(profile));
        _actor.SetTypingEnabled(typingEnabled);
        _actor.SetKeyboardModeEnabled(keyboardModeEnabled);
        _actor.SetAllowMouseTakeover(profile.AllowMouseTakeover);
        _actor.ConfigureLayouts(leftLayout, rightLayout);
        _actor.ConfigureKeymap(keymap);
        _actor.SetPersistentLayer(activeLayer);
        ConfigureDispatcherAutocorrect(_dispatcher, profile);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _actor.Dispose();
        _dispatchPump.Dispose();
        _dispatchQueue.Dispose();
    }

    private static void ConfigureDispatcherAutocorrect(IInputDispatcher dispatcher, UserSettings settings)
    {
        if (dispatcher is not IAutocorrectController autocorrectController)
        {
            return;
        }

        autocorrectController.ConfigureAutocorrectOptions(AutocorrectOptions.FromSettings(settings));
        autocorrectController.SetAutocorrectEnabled(settings.AutocorrectEnabled);
    }
}
