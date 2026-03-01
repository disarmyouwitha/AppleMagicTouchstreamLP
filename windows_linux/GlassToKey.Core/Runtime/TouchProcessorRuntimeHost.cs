namespace GlassToKey;

public sealed class TouchProcessorRuntimeHost : ITrackpadFrameTarget, IDisposable
{
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

        KeymapStore resolvedKeymap = keymap ?? KeymapStore.LoadBundledDefault();
        TouchProcessorCore core = settings == null
            ? TouchProcessorFactory.CreateDefault(resolvedKeymap, preset)
            : TouchProcessorFactory.CreateConfigured(resolvedKeymap, settings, preset);
        _dispatchQueue = new DispatchEventQueue();
        _actor = new TouchProcessorActor(core, dispatchQueue: _dispatchQueue);
        _actor.SetHapticsOnKeyDispatchEnabled(false);
        _dispatchPump = new DispatchEventPump(_dispatchQueue, dispatcher);
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
        snapshot = new TouchProcessorRuntimeSnapshot(
            ActiveLayer: engineSnapshot.ActiveLayer,
            TypingEnabled: engineSnapshot.TypingEnabled,
            KeyboardModeEnabled: engineSnapshot.KeyboardModeEnabled,
            ContactCount: engineSnapshot.ContactCount,
            LeftContacts: engineSnapshot.LeftContacts,
            RightContacts: engineSnapshot.RightContacts);
        return true;
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
}
