using System;
using System.Diagnostics;
using System.Threading;

namespace GlassToKey;

internal sealed class TouchProcessorCore
{
    private const double FiveFingerSwipeThresholdMm = 8.0;
    private const int FiveFingerSwipeArmContacts = 5;
    private const int FiveFingerSwipeSustainContacts = 4;
    private const int FiveFingerSwipeReleaseContacts = 2;
    private const int ChordShiftContactThreshold = 4;
    private const double ChordSourceStaleTimeoutMs = 200.0;
    private const ushort ShiftVirtualKey = 0x10;

    private TouchProcessorConfig _config;
    private readonly IntentTransition[] _transitionRing = new IntentTransition[256];
    private int _transitionRingHead;
    private int _transitionRingCount;

    private readonly TouchTable<IntentTouchInfo> _intentTouches = new(32);
    private readonly TouchTable<TouchBindingState> _touchStates = new(32);
    private readonly TouchTable<int> _momentaryLayerTouches = new(16);
    private readonly ulong[] _removalBuffer = new ulong[32];

    private KeyLayout _leftLayout;
    private KeyLayout _rightLayout;
    private KeymapStore _keymap;
    private BindingIndex? _leftBindingIndex;
    private BindingIndex? _rightBindingIndex;
    private int _bindingsGeneration;
    private int _bindingsLayer = -1;

    private IntentMode _intentMode = IntentMode.Idle;
    private int _lastContactCount;
    private long _keyCandidateStartTicks;
    private ulong _keyCandidateTouchKey;
    private double _keyCandidateCentroidX;
    private double _keyCandidateCentroidY;
    private long _mouseCandidateStartTicks;
    private long _gestureCandidateStartTicks;
    private long _typingGraceDeadlineTicks;
    private bool _typingCommittedUntilAllUp;
    private bool _allowMouseTakeoverDuringTyping;

    private bool _typingEnabled = true;
    private bool _keyboardModeEnabled;
    private int _persistentLayer;
    private int _activeLayer;

    private FiveFingerSwipeState _fiveFingerSwipeLeft;
    private FiveFingerSwipeState _fiveFingerSwipeRight;

    private bool _chordShiftLeft;
    private bool _chordShiftRight;
    private bool _chordShiftKeyDown;
    private int _lastRawLeftContacts;
    private int _lastRawRightContacts;
    private long _lastRawLeftUpdateTicks = -1;
    private long _lastRawRightUpdateTicks = -1;

    private long _framesProcessed;
    private long _queueDrops;
    private long _snapAttempts;
    private long _snapAccepted;
    private long _snapRejected;
    private ulong _intentTraceFingerprint = 14695981039346656037ul;
    private readonly DispatchEvent[] _dispatchRing = new DispatchEvent[512];
    private int _dispatchRingHead;
    private int _dispatchRingCount;
    private long _dispatchDrops;
    private long _dispatchEnqueued;
    private long _dispatchSuppressedTypingDisabled;
    private long _dispatchSuppressedRingFull;
    private PendingTapGesture _pendingTapGesture;
    private bool _diagnosticsEnabled;
    private readonly EngineDiagnosticEvent[] _diagnosticRing = new EngineDiagnosticEvent[8192];
    private int _diagnosticRingHead;
    private int _diagnosticRingCount;
    private long _clockAnchorTimestampTicks;
    private long _clockAnchorWallTicks;

    public TouchProcessorCore(
        KeyLayout leftLayout,
        KeyLayout rightLayout,
        KeymapStore keymap,
        TouchProcessorConfig? config = null)
    {
        _leftLayout = leftLayout;
        _rightLayout = rightLayout;
        _keymap = keymap;
        _config = NormalizeConfig(config ?? TouchProcessorConfig.Default);
    }

    public TouchProcessorConfig CurrentConfig => _config;

    public void ConfigureLayouts(KeyLayout leftLayout, KeyLayout rightLayout)
    {
        _leftLayout = leftLayout;
        _rightLayout = rightLayout;
        InvalidateBindings();
    }

    public void ConfigureKeymap(KeymapStore keymap)
    {
        _keymap = keymap;
        InvalidateBindings();
    }

    public void Configure(TouchProcessorConfig config)
    {
        TouchProcessorConfig normalized = NormalizeConfig(config);
        bool rebuildBindings =
            Math.Abs(normalized.SnapRadiusPercent - _config.SnapRadiusPercent) > 0.0001 ||
            Math.Abs(normalized.SnapAmbiguityRatio - _config.SnapAmbiguityRatio) > 0.0001;
        _config = normalized;
        if (rebuildBindings)
        {
            InvalidateBindings();
        }
    }

    public void SetPersistentLayer(int layer)
    {
        _persistentLayer = Math.Clamp(layer, 0, 7);
        UpdateActiveLayer();
    }

    public void SetTypingEnabled(bool enabled)
    {
        SetTypingEnabledState(enabled, Stopwatch.GetTimestamp(), TypingToggleSource.Api);
    }

    public void SetKeyboardModeEnabled(bool enabled)
    {
        _keyboardModeEnabled = enabled;
    }

    public void SetAllowMouseTakeover(bool enabled)
    {
        _allowMouseTakeoverDuringTyping = enabled;
    }

    public void SetDiagnosticsEnabled(bool enabled)
    {
        _diagnosticsEnabled = enabled;
        if (!enabled)
        {
            _diagnosticRingHead = 0;
            _diagnosticRingCount = 0;
        }
    }

    public void RecordQueueDrop()
    {
        _queueDrops++;
    }

    public void RecordDispatchDrop()
    {
        _dispatchDrops++;
    }

    public int CopyDiagnostics(Span<EngineDiagnosticEvent> destination)
    {
        int count = Math.Min(destination.Length, _diagnosticRingCount);
        if (count <= 0)
        {
            return 0;
        }

        int start = (_diagnosticRingHead - _diagnosticRingCount + _diagnosticRing.Length) % _diagnosticRing.Length;
        for (int i = 0; i < count; i++)
        {
            destination[i] = _diagnosticRing[(start + i) % _diagnosticRing.Length];
        }

        return count;
    }

    public void ResetState()
    {
        _intentTouches.RemoveAll();
        _touchStates.RemoveAll();
        _momentaryLayerTouches.RemoveAll();
        _intentMode = IntentMode.Idle;
        _lastContactCount = 0;
        _keyCandidateStartTicks = 0;
        _keyCandidateTouchKey = 0;
        _mouseCandidateStartTicks = 0;
        _gestureCandidateStartTicks = 0;
        _typingGraceDeadlineTicks = 0;
        _typingCommittedUntilAllUp = false;
        _fiveFingerSwipeLeft = default;
        _fiveFingerSwipeRight = default;
        _chordShiftLeft = false;
        _chordShiftRight = false;
        _chordShiftKeyDown = false;
        _lastRawLeftContacts = 0;
        _lastRawRightContacts = 0;
        _lastRawLeftUpdateTicks = -1;
        _lastRawRightUpdateTicks = -1;
        _intentTraceFingerprint = 14695981039346656037ul;
        _transitionRingHead = 0;
        _transitionRingCount = 0;
        _dispatchRingHead = 0;
        _dispatchRingCount = 0;
        _dispatchDrops = 0;
        _dispatchEnqueued = 0;
        _dispatchSuppressedTypingDisabled = 0;
        _dispatchSuppressedRingFull = 0;
        _pendingTapGesture = default;
        _diagnosticRingHead = 0;
        _diagnosticRingCount = 0;
        _clockAnchorTimestampTicks = 0;
        _clockAnchorWallTicks = 0;
    }

    public void ProcessFrame(
        TrackpadSide side,
        in InputFrame frame,
        ushort maxX,
        ushort maxY,
        long timestampTicks)
    {
        CaptureClockAnchor(timestampTicks);
        _framesProcessed++;
        EnsureBindingIndexes();
        BindingIndex sideIndex = side == TrackpadSide.Left ? _leftBindingIndex! : _rightBindingIndex!;
        RefreshStaleRawContactCounts(timestampTicks);
        int contactCountInFrame = frame.GetClampedContactCount();
        int tipContactsInFrame = 0;
        for (int i = 0; i < contactCountInFrame; i++)
        {
            if (frame.GetContact(i).TipSwitch)
            {
                tipContactsInFrame++;
            }
        }

        if (side == TrackpadSide.Left)
        {
            _lastRawLeftContacts = tipContactsInFrame;
            _lastRawLeftUpdateTicks = timestampTicks;
        }
        else
        {
            _lastRawRightContacts = tipContactsInFrame;
            _lastRawRightUpdateTicks = timestampTicks;
        }
        UpdateChordShift(_lastRawLeftContacts, _lastRawRightContacts, timestampTicks);
        double tipSumXNorm = 0;
        double tipSumYNorm = 0;
        Span<ulong> frameKeys = stackalloc ulong[InputFrame.MaxContacts];
        int frameKeyCount = 0;
        bool suppressSideForChordSource = IsChordSourceSide(side);
        if (suppressSideForChordSource)
        {
            ClearTouchesForChordSourceSide(side, timestampTicks);
        }
        RecordDiagnostic(
            timestampTicks,
            EngineDiagnosticEventKind.Frame,
            side,
            _intentMode,
            DispatchEventKind.None,
            DispatchSuppressReason.None,
            TypingToggleSource.Api,
            0,
            DispatchMouseButton.None,
            _typingEnabled,
            suppressSideForChordSource,
            side == TrackpadSide.Left ? _fiveFingerSwipeLeft.Active : _fiveFingerSwipeRight.Active,
            side == TrackpadSide.Left ? _fiveFingerSwipeLeft.Triggered : _fiveFingerSwipeRight.Triggered,
            contactCountInFrame,
            tipContactsInFrame,
            _lastRawLeftContacts,
            _lastRawRightContacts,
            "frame_start");

        for (int i = 0; i < contactCountInFrame; i++)
        {
            ContactFrame contact = frame.GetContact(i);
            if (!contact.TipSwitch)
            {
                // Treat non-tip hover/near-field contacts as released for intent and key lifecycle.
                // Confidence can flicker even while a finger is visibly down, so don't gate keying on it.
                continue;
            }
            double xNorm = SafeNormalize(contact.X, maxX);
            double yNorm = SafeNormalize(contact.Y, maxY);
            tipSumXNorm += xNorm;
            tipSumYNorm += yNorm;
            if (suppressSideForChordSource)
            {
                // Chord-source side acts as a shift anchor only; do not dispatch or track key touches.
                continue;
            }

            ulong touchKey = MakeTouchKey(side, contact.Id);
            frameKeys[frameKeyCount++] = touchKey;

            EngineBindingHit hit = sideIndex.HitTest(xNorm, yNorm);
            bool onKey = hit.Found;
            bool keyboardAnchor = false;
            if (onKey)
            {
                EngineActionKind kind = sideIndex.Bindings[hit.BindingIndex].Mapping.Primary.Kind;
                keyboardAnchor = kind is EngineActionKind.Modifier or EngineActionKind.Continuous or EngineActionKind.MomentaryLayer or EngineActionKind.KeyChord;
            }

            if (_intentTouches.TryGetValue(touchKey, out IntentTouchInfo existing))
            {
                UpdateIntentTouch(ref existing, xNorm, yNorm, onKey, keyboardAnchor, timestampTicks);
                _intentTouches.Set(touchKey, existing);
            }
            else
            {
                _intentTouches.Set(touchKey, new IntentTouchInfo(
                    Side: side,
                    StartXNorm: xNorm,
                    StartYNorm: yNorm,
                    LastXNorm: xNorm,
                    LastYNorm: yNorm,
                    StartTicks: timestampTicks,
                    LastTicks: timestampTicks,
                    MaxDistanceMm: 0,
                    LastVelocityMmPerSec: 0,
                    OnKey: onKey,
                    KeyboardAnchor: keyboardAnchor,
                    InitialBindingIndex: hit.Found ? hit.BindingIndex : -1));
            }

            HandleContactLifecycle(
                touchKey,
                side,
                hit,
                xNorm,
                yNorm,
                timestampTicks);
        }

        RemoveStaleTouchesForSide(side, frameKeys.Slice(0, frameKeyCount), timestampTicks);

        IntentAggregate aggregate = BuildIntentAggregate();
        int previousContactCount = _lastContactCount;
        if (tipContactsInFrame > 0)
        {
            double centroidX = tipSumXNorm / tipContactsInFrame;
            double centroidY = tipSumYNorm / tipContactsInFrame;
            UpdateFiveFingerSwipe(side, tipContactsInFrame, centroidX, centroidY, timestampTicks);
        }
        else
        {
            UpdateFiveFingerSwipe(side, 0, 0, 0, timestampTicks);
        }
        UpdateTapGestureState(aggregate, timestampTicks, previousContactCount);
        UpdateIntentState(aggregate, timestampTicks);
    }

    public TouchProcessorSnapshot Snapshot()
    {
        return Snapshot(EstimateNowTicks());
    }

    public TouchProcessorSnapshot Snapshot(long nowTicks)
    {
        IntentAggregate aggregate = BuildIntentAggregate();
        RefreshPassiveIntentState(in aggregate, nowTicks);
        return new TouchProcessorSnapshot(
            IntentMode: _intentMode,
            ActiveLayer: _activeLayer,
            TypingEnabled: _typingEnabled,
            KeyboardModeEnabled: _keyboardModeEnabled,
            ContactCount: aggregate.ContactCount,
            LeftContacts: aggregate.LeftContacts,
            RightContacts: aggregate.RightContacts,
            FiveFingerSwipeTriggered: _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
            ChordShiftLeft: _chordShiftLeft,
            ChordShiftRight: _chordShiftRight,
            FramesProcessed: _framesProcessed,
            QueueDrops: _queueDrops,
            DispatchEnqueued: _dispatchEnqueued,
            DispatchSuppressedTypingDisabled: _dispatchSuppressedTypingDisabled,
            DispatchSuppressedRingFull: _dispatchSuppressedRingFull,
            SnapAttempts: _snapAttempts,
            SnapAccepted: _snapAccepted,
            SnapRejected: _snapRejected,
            IntentTraceFingerprint: _intentTraceFingerprint);
    }

    private void CaptureClockAnchor(long timestampTicks)
    {
        _clockAnchorTimestampTicks = timestampTicks;
        _clockAnchorWallTicks = Stopwatch.GetTimestamp();
    }

    private long EstimateNowTicks()
    {
        long anchorWallTicks = _clockAnchorWallTicks;
        long wallNowTicks = Stopwatch.GetTimestamp();
        if (anchorWallTicks == 0)
        {
            return wallNowTicks;
        }

        long elapsedTicks = wallNowTicks - anchorWallTicks;
        if (elapsedTicks <= 0)
        {
            return _clockAnchorTimestampTicks;
        }

        long anchorTimestampTicks = _clockAnchorTimestampTicks;
        if (anchorTimestampTicks > long.MaxValue - elapsedTicks)
        {
            return long.MaxValue;
        }

        return anchorTimestampTicks + elapsedTicks;
    }

    private void RefreshPassiveIntentState(in IntentAggregate aggregate, long nowTicks)
    {
        if (aggregate.ContactCount > 0)
        {
            // Keep grace deadline fresh when snapshots are read faster than frames arrive.
            _ = IsTypingGraceActive(nowTicks);
            return;
        }

        if (IsTypingGraceActive(nowTicks))
        {
            SetTypingCommittedState(nowTicks, untilAllUp: true, reason: "grace_snapshot");
            _lastContactCount = 0;
            return;
        }

        _typingCommittedUntilAllUp = false;
        _lastContactCount = 0;
        TransitionTo(IntentMode.Idle, nowTicks, "all_up_snapshot");
    }

    public int CopyIntentTransitions(Span<IntentTransition> destination)
    {
        int count = Math.Min(destination.Length, _transitionRingCount);
        if (count == 0)
        {
            return 0;
        }

        int start = (_transitionRingHead - _transitionRingCount + _transitionRing.Length) % _transitionRing.Length;
        for (int i = 0; i < count; i++)
        {
            destination[i] = _transitionRing[(start + i) % _transitionRing.Length];
        }

        return count;
    }

    public int DrainDispatchEvents(Span<DispatchEvent> destination)
    {
        int count = Math.Min(destination.Length, _dispatchRingCount);
        if (count <= 0)
        {
            return 0;
        }

        int start = (_dispatchRingHead - _dispatchRingCount + _dispatchRing.Length) % _dispatchRing.Length;
        for (int i = 0; i < count; i++)
        {
            destination[i] = _dispatchRing[(start + i) % _dispatchRing.Length];
        }

        _dispatchRingCount -= count;
        if (_dispatchRingCount == 0)
        {
            _dispatchRingHead = 0;
        }

        return count;
    }

    private void InvalidateBindings()
    {
        _bindingsGeneration++;
        _leftBindingIndex = null;
        _rightBindingIndex = null;
    }

    private void EnsureBindingIndexes()
    {
        if (_leftBindingIndex != null &&
            _rightBindingIndex != null &&
            _bindingsLayer == _activeLayer)
        {
            return;
        }

        _leftBindingIndex = BindingIndex.Build(_leftLayout, TrackpadSide.Left, _activeLayer, _keymap, snapRadiusFraction: _config.SnapRadiusPercent / 100.0);
        _rightBindingIndex = BindingIndex.Build(_rightLayout, TrackpadSide.Right, _activeLayer, _keymap, snapRadiusFraction: _config.SnapRadiusPercent / 100.0);
        _bindingsLayer = _activeLayer;
    }

    private void UpdateIntentTouch(ref IntentTouchInfo touch, double xNorm, double yNorm, bool onKey, bool keyboardAnchor, long nowTicks)
    {
        double distanceFromStartMm = DistanceMm(touch.StartXNorm, touch.StartYNorm, xNorm, yNorm);
        if (distanceFromStartMm > touch.MaxDistanceMm)
        {
            touch.MaxDistanceMm = distanceFromStartMm;
        }

        long dtTicks = nowTicks - touch.LastTicks;
        if (dtTicks < 1)
        {
            dtTicks = 1;
        }

        double dtSeconds = dtTicks / (double)Stopwatch.Frequency;
        double deltaMm = DistanceMm(touch.LastXNorm, touch.LastYNorm, xNorm, yNorm);
        touch.LastVelocityMmPerSec = deltaMm / dtSeconds;
        touch.LastXNorm = xNorm;
        touch.LastYNorm = yNorm;
        touch.LastTicks = nowTicks;
        touch.OnKey = onKey;
        touch.KeyboardAnchor = keyboardAnchor;
    }

    private void HandleContactLifecycle(
        ulong touchKey,
        TrackpadSide side,
        EngineBindingHit hit,
        double xNorm,
        double yNorm,
        long timestampTicks)
    {
        if (_touchStates.TryGetValue(touchKey, out TouchBindingState existing))
        {
            double movementMm = DistanceMm(existing.StartXNorm, existing.StartYNorm, xNorm, yNorm);
            existing.LastXNorm = xNorm;
            existing.LastYNorm = yNorm;
            existing.MaxDistanceMm = Math.Max(existing.MaxDistanceMm, movementMm);

            if (existing.DispatchDownSent && existing.MaxDistanceMm > _config.DragCancelMm)
            {
                EndPressAction(ref existing, timestampTicks);
            }

            if (existing.Lifecycle == EngineTouchLifecycle.Pending && existing.HasHoldAction)
            {
                long holdTicks = MsToTicks(_config.HoldDurationMs);
                if (existing.MaxDistanceMm <= _config.DragCancelMm &&
                    timestampTicks - existing.StartTicks >= holdTicks)
                {
                    existing.Lifecycle = EngineTouchLifecycle.Active;
                    existing.HoldTriggered = true;
                    BindingIndex existingIndex = side == TrackpadSide.Left ? _leftBindingIndex! : _rightBindingIndex!;
                    EngineKeyBinding existingBinding = existingIndex.Bindings[existing.BindingIndex];
                    TryBeginPressAction(existingBinding.Mapping.Hold, touchKey, timestampTicks, ref existing);
                    if (!existing.DispatchDownSent)
                    {
                        ApplyReleaseAction(existingBinding.Mapping.Hold, side, touchKey, timestampTicks);
                    }
                }
            }

            _touchStates.Set(touchKey, existing);
            return;
        }

        if (!hit.Found)
        {
            if (!ShouldTrackOffKeyTouchForSnap())
            {
                return;
            }

            TouchBindingState offKey = new(
                Side: side,
                BindingIndex: -1,
                Lifecycle: EngineTouchLifecycle.Pending,
                StartTicks: timestampTicks,
                StartXNorm: xNorm,
                StartYNorm: yNorm,
                LastXNorm: xNorm,
                LastYNorm: yNorm,
                MaxDistanceMm: 0,
                HasHoldAction: false,
                HoldTriggered: false,
                MomentaryLayerTarget: -1,
                DispatchDownSent: false,
                DispatchDownKind: DispatchEventKind.None,
                DispatchDownVirtualKey: 0,
                DispatchDownMouseButton: DispatchMouseButton.None,
                RepeatToken: 0,
                DispatchDownLabel: string.Empty);
            _touchStates.Set(touchKey, offKey);
            return;
        }

        BindingIndex index = side == TrackpadSide.Left ? _leftBindingIndex! : _rightBindingIndex!;
        EngineKeyBinding binding = index.Bindings[hit.BindingIndex];
        TouchBindingState next = new(
            Side: side,
            BindingIndex: hit.BindingIndex,
            Lifecycle: EngineTouchLifecycle.Pending,
            StartTicks: timestampTicks,
            StartXNorm: xNorm,
            StartYNorm: yNorm,
            LastXNorm: xNorm,
            LastYNorm: yNorm,
            MaxDistanceMm: 0,
            HasHoldAction: binding.Mapping.HasHold,
            HoldTriggered: false,
            MomentaryLayerTarget: binding.Mapping.Primary.Kind == EngineActionKind.MomentaryLayer ? binding.Mapping.Primary.LayerTarget : -1,
            DispatchDownSent: false,
            DispatchDownKind: DispatchEventKind.None,
            DispatchDownVirtualKey: 0,
            DispatchDownMouseButton: DispatchMouseButton.None,
            RepeatToken: 0,
            DispatchDownLabel: string.Empty);

        _touchStates.Set(touchKey, next);
        if (next.MomentaryLayerTarget >= 0)
        {
            _momentaryLayerTouches.Set(touchKey, next.MomentaryLayerTarget);
            UpdateActiveLayer();
        }

        if (!next.HasHoldAction)
        {
            TryBeginPressAction(binding.Mapping.Primary, touchKey, timestampTicks, ref next);
            _touchStates.Set(touchKey, next);
        }
    }

    private void RemoveStaleTouchesForSide(TrackpadSide side, ReadOnlySpan<ulong> frameKeys, long timestampTicks)
    {
        int removalCount = 0;
        for (int i = 0; i < _intentTouches.Capacity; i++)
        {
            if (!_intentTouches.IsOccupiedAt(i))
            {
                continue;
            }

            ulong key = _intentTouches.KeyAt(i);
            if (TouchSideFromKey(key) != side)
            {
                continue;
            }

            if (Contains(frameKeys, key))
            {
                continue;
            }

            if (removalCount < _removalBuffer.Length)
            {
                _removalBuffer[removalCount++] = key;
            }
        }

        for (int i = 0; i < removalCount; i++)
        {
            ulong key = _removalBuffer[i];
            _intentTouches.Remove(key, out _);
            HandleRelease(key, timestampTicks);
        }
    }

    private void HandleRelease(ulong touchKey, long timestampTicks)
    {
        if (!_touchStates.Remove(touchKey, out TouchBindingState state))
        {
            return;
        }

        if (state.MomentaryLayerTarget >= 0)
        {
            _momentaryLayerTouches.Remove(touchKey, out _);
            UpdateActiveLayer();
            RecordReleaseDropped(state.Side, EngineKeyAction.None, timestampTicks, "momentary_layer_release");
            return;
        }

        bool hadDispatchDown = state.DispatchDownSent;
        if (hadDispatchDown)
        {
            EndPressAction(ref state, timestampTicks);
        }

        BindingIndex index = state.Side == TrackpadSide.Left ? _leftBindingIndex! : _rightBindingIndex!;
        bool hasBoundBinding = state.BindingIndex >= 0 && state.BindingIndex < index.Bindings.Length;
        EngineKeyBinding binding = default;
        EngineKeyAction action = EngineKeyAction.None;
        if (hasBoundBinding)
        {
            binding = index.Bindings[state.BindingIndex];
            action = binding.Mapping.Primary;
            if (state.HoldTriggered && binding.Mapping.HasHold)
            {
                action = binding.Mapping.Hold;
            }
        }

        if (state.MaxDistanceMm > _config.DragCancelMm)
        {
            RecordReleaseDropped(state.Side, action, timestampTicks, "drag_cancel");
            return;
        }

        if (hadDispatchDown)
        {
            return;
        }
        if (_pendingTapGesture.Active)
        {
            RecordReleaseDropped(state.Side, action, timestampTicks, "tap_gesture_active");
            return;
        }
        if (state.HoldTriggered)
        {
            RecordReleaseDropped(state.Side, action, timestampTicks, "hold_consumed");
            return;
        }

        if (hasBoundBinding && binding.Rect.Contains(state.LastXNorm, state.LastYNorm))
        {
            ApplyReleaseAction(action, state.Side, touchKey, timestampTicks);
            return;
        }

        // If release lands inside any key, treat it as a direct hit and skip snap logic.
        EngineBindingHit directHit = index.HitTest(state.LastXNorm, state.LastYNorm);
        if (directHit.Found)
        {
            if (hasBoundBinding && directHit.BindingIndex != state.BindingIndex)
            {
                RecordReleaseDropped(state.Side, action, timestampTicks, "drag_cross_key");
                return;
            }

            EngineKeyBinding directBinding = index.Bindings[directHit.BindingIndex];
            ApplyReleaseAction(directBinding.Mapping.Primary, state.Side, touchKey, timestampTicks);
            return;
        }

        if (ShouldAttemptSnap())
        {
            _snapAttempts++;
            if (TrySnapBinding(state.Side, state.LastXNorm, state.LastYNorm, out EngineKeyBinding snapped))
            {
                _snapAccepted++;
                ApplyReleaseAction(snapped.Mapping.Primary, state.Side, touchKey, timestampTicks);
                return;
            }

            _snapRejected++;
        }

        RecordReleaseDropped(state.Side, action, timestampTicks, "off_key_no_snap");
    }

    private void RecordReleaseDropped(TrackpadSide side, EngineKeyAction action, long timestampTicks, string reason)
    {
        RecordDiagnostic(
            timestampTicks,
            EngineDiagnosticEventKind.ReleaseDropped,
            side,
            _intentMode,
            DispatchEventKind.None,
            DispatchSuppressReason.None,
            TypingToggleSource.Api,
            action.VirtualKey,
            action.MouseButton,
            _typingEnabled,
            false,
            _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
            _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
            _intentTouches.Count,
            0,
            _lastRawLeftContacts,
            _lastRawRightContacts,
            reason,
            dispatchLabel: action.Label);
    }

    private bool ShouldAttemptSnap()
    {
        if (_config.SnapRadiusPercent <= 0)
        {
            return false;
        }

        return _intentMode is IntentMode.KeyCandidate or IntentMode.TypingCommitted;
    }

    private bool ShouldTrackOffKeyTouchForSnap()
    {
        return ShouldAttemptSnap();
    }

    private bool TrySnapBinding(TrackpadSide side, double xNorm, double yNorm, out EngineKeyBinding binding)
    {
        BindingIndex index = side == TrackpadSide.Left ? _leftBindingIndex! : _rightBindingIndex!;
        int count = index.SnapBindingIndices.Length;
        if (count == 0)
        {
            binding = default;
            return false;
        }

        float px = (float)xNorm;
        float py = (float)yNorm;
        int bestIndex = -1;
        float bestDistanceSq = float.MaxValue;
        int secondIndex = -1;
        float secondDistanceSq = float.MaxValue;
        for (int i = 0; i < count; i++)
        {
            float dx = px - index.SnapCentersX[i];
            float dy = py - index.SnapCentersY[i];
            float distanceSq = (dx * dx) + (dy * dy);
            if (distanceSq < bestDistanceSq)
            {
                secondDistanceSq = bestDistanceSq;
                secondIndex = bestIndex;
                bestDistanceSq = distanceSq;
                bestIndex = i;
            }
            else if (distanceSq < secondDistanceSq)
            {
                secondDistanceSq = distanceSq;
                secondIndex = i;
            }
        }

        if (bestIndex < 0 || bestDistanceSq > index.SnapRadiusSq[bestIndex])
        {
            binding = default;
            return false;
        }

        int selected = bestIndex;
        if (secondIndex >= 0 &&
            secondDistanceSq <= index.SnapRadiusSq[secondIndex] &&
            secondDistanceSq <= bestDistanceSq * (float)(_config.SnapAmbiguityRatio * _config.SnapAmbiguityRatio))
        {
            int bestBindingIndex = index.SnapBindingIndices[bestIndex];
            int secondBindingIndex = index.SnapBindingIndices[secondIndex];
            float edgeBest = DistanceSqToRectEdge(xNorm, yNorm, index.Bindings[bestBindingIndex].Rect);
            float edgeSecond = DistanceSqToRectEdge(xNorm, yNorm, index.Bindings[secondBindingIndex].Rect);
            if (edgeSecond < edgeBest)
            {
                selected = secondIndex;
            }
        }

        binding = index.Bindings[index.SnapBindingIndices[selected]];
        return true;
    }

    private void TryBeginPressAction(EngineKeyAction action, ulong touchKey, long timestampTicks, ref TouchBindingState state)
    {
        switch (action.Kind)
        {
            case EngineActionKind.Modifier:
                if (action.VirtualKey == 0)
                {
                    return;
                }

                ApplyActionState(action, timestampTicks);
                if (EnqueueDispatchEvent(
                    DispatchEventKind.ModifierDown,
                    action.VirtualKey,
                    DispatchMouseButton.None,
                    repeatToken: 0,
                    DispatchEventFlags.None,
                    state.Side,
                    timestampTicks,
                    dispatchLabel: action.Label))
                {
                    state.DispatchDownSent = true;
                    state.DispatchDownKind = DispatchEventKind.ModifierDown;
                    state.DispatchDownVirtualKey = action.VirtualKey;
                    state.DispatchDownMouseButton = DispatchMouseButton.None;
                    state.RepeatToken = 0;
                    state.DispatchDownLabel = action.Label;
                }
                break;
            case EngineActionKind.Continuous:
                if (action.VirtualKey == 0)
                {
                    return;
                }

                ApplyActionState(action, timestampTicks);
                if (EnqueueDispatchEvent(
                    DispatchEventKind.KeyDown,
                    action.VirtualKey,
                    DispatchMouseButton.None,
                    repeatToken: touchKey,
                    DispatchEventFlags.Repeatable,
                    state.Side,
                    timestampTicks,
                    dispatchLabel: action.Label))
                {
                    state.DispatchDownSent = true;
                    state.DispatchDownKind = DispatchEventKind.KeyDown;
                    state.DispatchDownVirtualKey = action.VirtualKey;
                    state.DispatchDownMouseButton = DispatchMouseButton.None;
                    state.RepeatToken = touchKey;
                    state.DispatchDownLabel = action.Label;
                }
                break;
            default:
                break;
        }
    }

    private void EndPressAction(ref TouchBindingState state, long timestampTicks)
    {
        if (!state.DispatchDownSent)
        {
            return;
        }

        switch (state.DispatchDownKind)
        {
            case DispatchEventKind.ModifierDown:
                EnqueueDispatchEvent(
                    DispatchEventKind.ModifierUp,
                    state.DispatchDownVirtualKey,
                    DispatchMouseButton.None,
                    repeatToken: 0,
                    DispatchEventFlags.None,
                    state.Side,
                    timestampTicks,
                    dispatchLabel: state.DispatchDownLabel);
                break;
            case DispatchEventKind.KeyDown:
                EnqueueDispatchEvent(
                    DispatchEventKind.KeyUp,
                    state.DispatchDownVirtualKey,
                    DispatchMouseButton.None,
                    state.RepeatToken,
                    DispatchEventFlags.None,
                    state.Side,
                    timestampTicks,
                    dispatchLabel: state.DispatchDownLabel);
                break;
            case DispatchEventKind.MouseButtonDown:
                EnqueueDispatchEvent(
                    DispatchEventKind.MouseButtonUp,
                    0,
                    state.DispatchDownMouseButton,
                    repeatToken: 0,
                    DispatchEventFlags.None,
                    state.Side,
                    timestampTicks,
                    dispatchLabel: state.DispatchDownLabel);
                break;
            default:
                break;
        }

        state.DispatchDownSent = false;
        state.DispatchDownKind = DispatchEventKind.None;
        state.DispatchDownVirtualKey = 0;
        state.DispatchDownMouseButton = DispatchMouseButton.None;
        state.RepeatToken = 0;
        state.DispatchDownLabel = string.Empty;
    }

    private void ApplyReleaseAction(EngineKeyAction action, TrackpadSide side, ulong touchKey, long timestampTicks)
    {
        ApplyActionState(action, timestampTicks);
        EmitTapDispatch(action, side, touchKey, timestampTicks);
    }

    private void EmitTapDispatch(EngineKeyAction action, TrackpadSide side, ulong touchKey, long timestampTicks)
    {
        switch (action.Kind)
        {
            case EngineActionKind.Key:
            case EngineActionKind.Continuous:
                if (action.VirtualKey != 0)
                {
                    EnqueueDispatchEvent(
                        DispatchEventKind.KeyTap,
                        action.VirtualKey,
                        DispatchMouseButton.None,
                        repeatToken: touchKey,
                        DispatchEventFlags.None,
                        side,
                        timestampTicks,
                        dispatchLabel: action.Label);
                }
                break;
            case EngineActionKind.Modifier:
                if (action.VirtualKey != 0)
                {
                    EnqueueDispatchEvent(
                        DispatchEventKind.ModifierDown,
                        action.VirtualKey,
                        DispatchMouseButton.None,
                        repeatToken: 0,
                        DispatchEventFlags.None,
                        side,
                        timestampTicks,
                        dispatchLabel: action.Label);
                    EnqueueDispatchEvent(
                        DispatchEventKind.ModifierUp,
                        action.VirtualKey,
                        DispatchMouseButton.None,
                        repeatToken: 0,
                        DispatchEventFlags.None,
                        side,
                        timestampTicks,
                        dispatchLabel: action.Label);
                }
                break;
            case EngineActionKind.MouseButton:
                if (action.MouseButton != DispatchMouseButton.None)
                {
                    EnqueueDispatchEvent(
                        DispatchEventKind.MouseButtonClick,
                        0,
                        action.MouseButton,
                        repeatToken: 0,
                        DispatchEventFlags.None,
                        side,
                        timestampTicks,
                        dispatchLabel: action.Label);
                }
                break;
            case EngineActionKind.KeyChord:
                if (action.ModifierVirtualKey != 0 && action.VirtualKey != 0)
                {
                    EnqueueDispatchEvent(
                        DispatchEventKind.ModifierDown,
                        action.ModifierVirtualKey,
                        DispatchMouseButton.None,
                        repeatToken: 0,
                        DispatchEventFlags.None,
                        side,
                        timestampTicks,
                        dispatchLabel: action.Label);
                    EnqueueDispatchEvent(
                        DispatchEventKind.KeyTap,
                        action.VirtualKey,
                        DispatchMouseButton.None,
                        repeatToken: touchKey,
                        DispatchEventFlags.None,
                        side,
                        timestampTicks,
                        dispatchLabel: action.Label);
                    EnqueueDispatchEvent(
                        DispatchEventKind.ModifierUp,
                        action.ModifierVirtualKey,
                        DispatchMouseButton.None,
                        repeatToken: 0,
                        DispatchEventFlags.None,
                        side,
                        timestampTicks,
                        dispatchLabel: action.Label);
                }
                break;
            default:
                break;
        }
    }

    private void ApplyActionState(EngineKeyAction action, long timestampTicks)
    {
        switch (action.Kind)
        {
            case EngineActionKind.TypingToggle:
                SetTypingEnabledState(!_typingEnabled, timestampTicks, TypingToggleSource.KeyAction);
                break;
            case EngineActionKind.LayerSet:
                _persistentLayer = Math.Clamp(action.LayerTarget, 0, 7);
                UpdateActiveLayer();
                break;
            case EngineActionKind.LayerToggle:
                _persistentLayer = _persistentLayer == action.LayerTarget ? 0 : Math.Clamp(action.LayerTarget, 0, 7);
                UpdateActiveLayer();
                break;
            case EngineActionKind.MomentaryLayer:
                break;
            case EngineActionKind.Key:
            case EngineActionKind.Continuous:
            case EngineActionKind.Modifier:
            case EngineActionKind.MouseButton:
            case EngineActionKind.KeyChord:
                ExtendTypingGrace(timestampTicks);
                break;
            case EngineActionKind.None:
            default:
                break;
        }
    }

    private void SetTypingEnabledState(bool enabled, long timestampTicks, TypingToggleSource source)
    {
        CaptureClockAnchor(timestampTicks);
        if (_typingEnabled == enabled)
        {
            return;
        }

        _typingEnabled = enabled;
        RecordDiagnostic(
            timestampTicks,
            EngineDiagnosticEventKind.TypingToggle,
            side: TrackpadSide.Left,
            intentMode: _intentMode,
            dispatchKind: DispatchEventKind.None,
            suppressReason: DispatchSuppressReason.None,
            toggleSource: source,
            virtualKey: 0,
            mouseButton: DispatchMouseButton.None,
            typingEnabled: _typingEnabled,
            chordSourceSuppressed: false,
            fiveFingerActive: _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
            fiveFingerTriggered: _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
            contactCount: _intentTouches.Count,
            tipContactCount: 0,
            leftRawContacts: _lastRawLeftContacts,
            rightRawContacts: _lastRawRightContacts,
            reason: enabled ? "typing_enabled" : "typing_disabled");
        if (!enabled)
        {
            ReleaseHeldStateForTypingDisable(timestampTicks);
        }
    }

    private void ReleaseHeldStateForTypingDisable(long timestampTicks)
    {
        if (_chordShiftKeyDown)
        {
            EnqueueDispatchEvent(
                DispatchEventKind.ModifierUp,
                ShiftVirtualKey,
                DispatchMouseButton.None,
                repeatToken: 0,
                DispatchEventFlags.None,
                side: TrackpadSide.Left,
                timestampTicks,
                dispatchLabel: "ChordShift");
            _chordShiftKeyDown = false;
        }

        for (int i = 0; i < _touchStates.Capacity; i++)
        {
            if (!_touchStates.IsOccupiedAt(i))
            {
                continue;
            }

            TouchBindingState state = _touchStates.ValueRefAt(i);
            if (state.DispatchDownSent)
            {
                EndPressAction(ref state, timestampTicks);
            }
        }

        _touchStates.RemoveAll();
        _intentTouches.RemoveAll();
        _momentaryLayerTouches.RemoveAll();
        _pendingTapGesture = default;
        _typingGraceDeadlineTicks = 0;
        _intentMode = IntentMode.Idle;
        _typingCommittedUntilAllUp = false;
        _lastContactCount = 0;
        _chordShiftLeft = false;
        _chordShiftRight = false;
        UpdateActiveLayer();
    }

    private bool EnqueueDispatchEvent(
        DispatchEventKind kind,
        ushort virtualKey,
        DispatchMouseButton mouseButton,
        ulong repeatToken,
        DispatchEventFlags flags,
        TrackpadSide side,
        long timestampTicks,
        string dispatchLabel = "")
    {
        string normalizedDispatchLabel = _diagnosticsEnabled
            ? NormalizeDispatchLabel(kind, virtualKey, mouseButton, dispatchLabel)
            : string.Empty;
        if (!_typingEnabled && IsTypingSuppressedDispatch(kind))
        {
            _dispatchSuppressedTypingDisabled++;
            RecordDiagnostic(
                timestampTicks,
                EngineDiagnosticEventKind.DispatchSuppressed,
                side,
                _intentMode,
                kind,
                DispatchSuppressReason.TypingDisabled,
                TypingToggleSource.Api,
                virtualKey,
                mouseButton,
                _typingEnabled,
                false,
                _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
                _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
                _intentTouches.Count,
                0,
                _lastRawLeftContacts,
                _lastRawRightContacts,
                "typing_disabled",
                normalizedDispatchLabel);
            return false;
        }

        if (_dispatchRingCount >= _dispatchRing.Length)
        {
            _dispatchSuppressedRingFull++;
            _dispatchDrops++;
            RecordDiagnostic(
                timestampTicks,
                EngineDiagnosticEventKind.DispatchSuppressed,
                side,
                _intentMode,
                kind,
                DispatchSuppressReason.DispatchRingFull,
                TypingToggleSource.Api,
                virtualKey,
                mouseButton,
                _typingEnabled,
                false,
                _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
                _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
                _intentTouches.Count,
                0,
                _lastRawLeftContacts,
                _lastRawRightContacts,
                "dispatch_ring_full",
                normalizedDispatchLabel);
            return false;
        }

        _dispatchRing[_dispatchRingHead] = new DispatchEvent(
            timestampTicks,
            kind,
            virtualKey,
            mouseButton,
            repeatToken,
            flags,
            side,
            normalizedDispatchLabel);
        _dispatchRingHead = (_dispatchRingHead + 1) % _dispatchRing.Length;
        _dispatchRingCount++;
        _dispatchEnqueued++;
        RecordDiagnostic(
            timestampTicks,
            EngineDiagnosticEventKind.DispatchEnqueued,
            side,
            _intentMode,
            kind,
            DispatchSuppressReason.None,
            TypingToggleSource.Api,
            virtualKey,
            mouseButton,
            _typingEnabled,
            false,
            _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
            _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
            _intentTouches.Count,
            0,
            _lastRawLeftContacts,
            _lastRawRightContacts,
            "dispatch_enqueued",
            normalizedDispatchLabel);
        return true;
    }

    private static string NormalizeDispatchLabel(
        DispatchEventKind kind,
        ushort virtualKey,
        DispatchMouseButton mouseButton,
        string dispatchLabel)
    {
        if (!string.IsNullOrWhiteSpace(dispatchLabel))
        {
            return dispatchLabel;
        }

        return kind switch
        {
            DispatchEventKind.MouseButtonClick => $"Mouse{mouseButton}Click",
            DispatchEventKind.MouseButtonDown => $"Mouse{mouseButton}Down",
            DispatchEventKind.MouseButtonUp => $"Mouse{mouseButton}Up",
            DispatchEventKind.ModifierDown => $"ModifierDown({VirtualKeyLabel(virtualKey)})",
            DispatchEventKind.ModifierUp => $"ModifierUp({VirtualKeyLabel(virtualKey)})",
            DispatchEventKind.KeyDown => $"KeyDown({VirtualKeyLabel(virtualKey)})",
            DispatchEventKind.KeyUp => $"KeyUp({VirtualKeyLabel(virtualKey)})",
            DispatchEventKind.KeyTap => $"KeyTap({VirtualKeyLabel(virtualKey)})",
            _ => kind.ToString()
        };
    }

    private static string VirtualKeyLabel(ushort virtualKey)
    {
        return virtualKey switch
        {
            0x08 => "Backspace",
            0x09 => "Tab",
            0x0D => "Enter",
            0x10 => "Shift",
            0x11 => "Ctrl",
            0x12 => "Alt",
            0x1B => "Esc",
            0x20 => "Space",
            0x25 => "Left",
            0x26 => "Up",
            0x27 => "Right",
            0x28 => "Down",
            0xBA => ";",
            0xBB => "=",
            0xBC => ",",
            0xBD => "-",
            0xBE => ".",
            0xBF => "/",
            0xC0 => "`",
            0xDB => "[",
            0xDC => "\\",
            0xDD => "]",
            0xDE => "'",
            >= 0x30 and <= 0x39 => ((char)virtualKey).ToString(),
            >= 0x41 and <= 0x5A => ((char)virtualKey).ToString(),
            _ => $"VK_0x{virtualKey:X2}"
        };
    }

    private static bool IsTypingSuppressedDispatch(DispatchEventKind kind)
    {
        return kind is DispatchEventKind.KeyTap or
            DispatchEventKind.KeyDown or
            DispatchEventKind.ModifierDown;
    }

    private void UpdateActiveLayer()
    {
        int layer = _persistentLayer;
        for (int i = 0; i < _momentaryLayerTouches.Capacity; i++)
        {
            if (!_momentaryLayerTouches.IsOccupiedAt(i))
            {
                continue;
            }

            layer = Math.Clamp(_momentaryLayerTouches.ValueRefAt(i), 0, 7);
            break;
        }

        if (_activeLayer != layer)
        {
            _activeLayer = layer;
            _bindingsLayer = -1;
        }
    }

    private IntentAggregate BuildIntentAggregate()
    {
        int count = 0;
        int onKey = 0;
        int offKey = 0;
        int leftCount = 0;
        int rightCount = 0;
        bool keyboardAnchor = false;
        double sumX = 0;
        double sumY = 0;
        double maxDistanceMm = 0;
        double maxVelocityMmPerSec = 0;
        ulong firstOnKeyTouch = 0;
        bool hasFirstOnKey = false;
        long earliestStart = long.MaxValue;
        long latestStart = long.MinValue;
        for (int i = 0; i < _intentTouches.Capacity; i++)
        {
            if (!_intentTouches.IsOccupiedAt(i))
            {
                continue;
            }

            ulong touchKey = _intentTouches.KeyAt(i);
            IntentTouchInfo info = _intentTouches.ValueRefAt(i);
            count++;
            if (info.Side == TrackpadSide.Left) leftCount++;
            if (info.Side == TrackpadSide.Right) rightCount++;
            sumX += info.LastXNorm;
            sumY += info.LastYNorm;
            if (info.OnKey)
            {
                onKey++;
                if (!hasFirstOnKey)
                {
                    hasFirstOnKey = true;
                    firstOnKeyTouch = touchKey;
                }
            }
            else
            {
                offKey++;
            }

            if (info.KeyboardAnchor)
            {
                keyboardAnchor = true;
            }

            if (info.MaxDistanceMm > maxDistanceMm)
            {
                maxDistanceMm = info.MaxDistanceMm;
            }

            if (info.LastVelocityMmPerSec > maxVelocityMmPerSec)
            {
                maxVelocityMmPerSec = info.LastVelocityMmPerSec;
            }

            if (info.StartTicks < earliestStart)
            {
                earliestStart = info.StartTicks;
            }

            if (info.StartTicks > latestStart)
            {
                latestStart = info.StartTicks;
            }
        }

        return new IntentAggregate(
            ContactCount: count,
            LeftContacts: leftCount,
            RightContacts: rightCount,
            OnKeyCount: onKey,
            OffKeyCount: offKey,
            KeyboardAnchor: keyboardAnchor,
            MaxDistanceMm: maxDistanceMm,
            MaxVelocityMmPerSec: maxVelocityMmPerSec,
            CentroidX: count == 0 ? 0 : sumX / count,
            CentroidY: count == 0 ? 0 : sumY / count,
            HasFirstOnKeyTouch: hasFirstOnKey,
            FirstOnKeyTouch: firstOnKeyTouch,
            EarliestStartTicks: earliestStart == long.MaxValue ? 0 : earliestStart,
            LatestStartTicks: latestStart == long.MinValue ? 0 : latestStart);
    }

    private void UpdateIntentState(in IntentAggregate aggregate, long nowTicks)
    {
        bool graceActive = IsTypingGraceActive(nowTicks);
        bool keyboardOnly = _keyboardModeEnabled && _typingEnabled;
        if (aggregate.ContactCount <= 0)
        {
            if (graceActive)
            {
                SetTypingCommittedState(nowTicks, untilAllUp: true, reason: "grace");
            }
            else
            {
                TransitionTo(IntentMode.Idle, nowTicks, "all_up");
            }

            _lastContactCount = 0;
            return;
        }

        int previousContactCount = _lastContactCount;
        if (keyboardOnly)
        {
            _lastContactCount = aggregate.ContactCount;
            SetTypingCommittedState(nowTicks, untilAllUp: true, reason: "keyboard_only");
            return;
        }

        long keyBufferTicks = MsToTicks(_config.KeyBufferMs);
        bool allowGestureCandidate = !aggregate.KeyboardAnchor;
        if (allowGestureCandidate && TryGetGestureCandidateStartTicks(
            aggregate.ContactCount,
            previousContactCount,
            aggregate.EarliestStartTicks,
            aggregate.LatestStartTicks,
            keyBufferTicks,
            out long gestureStartTicks))
        {
            _gestureCandidateStartTicks = gestureStartTicks;
            TransitionTo(IntentMode.GestureCandidate, nowTicks, "gesture_buffer");
            _lastContactCount = aggregate.ContactCount;
            return;
        }

        if (_intentMode == IntentMode.GestureCandidate && aggregate.ContactCount < 2)
        {
            TransitionTo(IntentMode.Idle, nowTicks, "gesture_exit");
        }

        _lastContactCount = aggregate.ContactCount;
        bool secondFingerAppeared = aggregate.ContactCount > 1 && aggregate.ContactCount > previousContactCount;
        bool centroidMoved = _intentMode == IntentMode.KeyCandidate &&
                             DistanceMm(_keyCandidateCentroidX, _keyCandidateCentroidY, aggregate.CentroidX, aggregate.CentroidY) > _config.IntentMoveMm;
        bool velocitySignal = aggregate.MaxVelocityMmPerSec > _config.IntentVelocityMmPerSec &&
                              aggregate.MaxDistanceMm > (_config.IntentMoveMm * 0.25);
        bool mouseSignal = aggregate.MaxDistanceMm > _config.IntentMoveMm ||
                           aggregate.MaxDistanceMm > _config.DragCancelMm ||
                           velocitySignal ||
                           (secondFingerAppeared && aggregate.OffKeyCount > 0) ||
                           centroidMoved;

        bool typingAnchorActive = aggregate.KeyboardAnchor && aggregate.ContactCount <= 1;
        if (graceActive)
        {
            SetTypingCommittedState(nowTicks, untilAllUp: !_allowMouseTakeoverDuringTyping, reason: "grace");
            return;
        }

        switch (_intentMode)
        {
            case IntentMode.Idle:
                if (typingAnchorActive)
                {
                    SetTypingCommittedState(nowTicks, untilAllUp: !_allowMouseTakeoverDuringTyping, reason: "typing_anchor");
                    return;
                }

                if (aggregate.OnKeyCount > 0 && !mouseSignal && aggregate.HasFirstOnKeyTouch)
                {
                    _keyCandidateStartTicks = nowTicks;
                    _keyCandidateTouchKey = aggregate.FirstOnKeyTouch;
                    _keyCandidateCentroidX = aggregate.CentroidX;
                    _keyCandidateCentroidY = aggregate.CentroidY;
                    TransitionTo(IntentMode.KeyCandidate, nowTicks, "on_key");
                }
                else
                {
                    _mouseCandidateStartTicks = nowTicks;
                    TransitionTo(IntentMode.MouseCandidate, nowTicks, "off_key");
                }
                break;
            case IntentMode.KeyCandidate:
                if (typingAnchorActive)
                {
                    SetTypingCommittedState(nowTicks, untilAllUp: !_allowMouseTakeoverDuringTyping, reason: "typing_anchor");
                    return;
                }

                if (mouseSignal)
                {
                    _mouseCandidateStartTicks = nowTicks;
                    TransitionTo(IntentMode.MouseCandidate, nowTicks, "mouse_signal");
                }
                else if (nowTicks - _keyCandidateStartTicks >= keyBufferTicks)
                {
                    SetTypingCommittedState(nowTicks, untilAllUp: !_allowMouseTakeoverDuringTyping, reason: "candidate_elapsed");
                }
                break;
            case IntentMode.TypingCommitted:
                if (typingAnchorActive)
                {
                    SetTypingCommittedState(nowTicks, untilAllUp: _typingCommittedUntilAllUp, reason: "typing_anchor_hold");
                    return;
                }

                if (_typingCommittedUntilAllUp)
                {
                    break;
                }

                if (mouseSignal)
                {
                    TransitionTo(IntentMode.MouseActive, nowTicks, "mouse_takeover");
                }
                break;
            case IntentMode.MouseCandidate:
                if (typingAnchorActive)
                {
                    SetTypingCommittedState(nowTicks, untilAllUp: !_allowMouseTakeoverDuringTyping, reason: "typing_anchor");
                    return;
                }

                if (mouseSignal || (nowTicks - _mouseCandidateStartTicks) >= keyBufferTicks)
                {
                    TransitionTo(IntentMode.MouseActive, nowTicks, "mouse_confirmed");
                }
                break;
            case IntentMode.MouseActive:
                if (typingAnchorActive)
                {
                    SetTypingCommittedState(nowTicks, untilAllUp: !_allowMouseTakeoverDuringTyping, reason: "typing_anchor");
                }
                break;
            case IntentMode.GestureCandidate:
                break;
            default:
                break;
        }
    }

    private void SetTypingCommittedState(long nowTicks, bool untilAllUp, string reason)
    {
        _typingCommittedUntilAllUp = untilAllUp;
        TransitionTo(IntentMode.TypingCommitted, nowTicks, reason);
    }

    private static bool TryGetGestureCandidateStartTicks(
        int contactCount,
        int previousContactCount,
        long earliestStartTicks,
        long latestStartTicks,
        long keyBufferTicks,
        out long startTicks)
    {
        startTicks = 0;
        if (contactCount >= 3)
        {
            if (previousContactCount == 2)
            {
                return false;
            }

            long startSpan = latestStartTicks - earliestStartTicks;
            if (startSpan <= keyBufferTicks)
            {
                startTicks = earliestStartTicks;
                return true;
            }

            return false;
        }

        if (contactCount >= 2 && previousContactCount <= 1)
        {
            long startSpan = latestStartTicks - earliestStartTicks;
            if (startSpan <= keyBufferTicks)
            {
                startTicks = earliestStartTicks;
                return true;
            }
        }

        return false;
    }

    private void UpdateTapGestureState(in IntentAggregate aggregate, long nowTicks, int previousContactCount)
    {
        if (!_config.TapClickEnabled)
        {
            _pendingTapGesture = default;
            return;
        }

        long staggerTicks = MsToTicks(_config.TapStaggerToleranceMs);
        long cadenceTicks = MsToTicks(_config.TapCadenceWindowMs);
        bool releaseBoundary = aggregate.ContactCount == 0 && previousContactCount > 0;
        bool candidateContactCount = (_config.TwoFingerTapEnabled && aggregate.ContactCount == 2) ||
                                     (_config.ThreeFingerTapEnabled && aggregate.ContactCount == 3);
        bool couldStartCandidate = previousContactCount <= 1 &&
                                   candidateContactCount &&
                                   aggregate.OnKeyCount == 0 &&
                                   !aggregate.KeyboardAnchor &&
                                   (aggregate.LatestStartTicks - aggregate.EarliestStartTicks) <= staggerTicks;

        if (!_pendingTapGesture.Active && couldStartCandidate)
        {
            _pendingTapGesture = new PendingTapGesture(
                Active: true,
                CandidateValid: true,
                ContactCount: aggregate.ContactCount,
                Side: aggregate.RightContacts > aggregate.LeftContacts ? TrackpadSide.Right : TrackpadSide.Left,
                StartedTicks: nowTicks,
                EarliestTouchTicks: aggregate.EarliestStartTicks,
                LatestTouchTicks: aggregate.LatestStartTicks);
            RecordDiagnostic(
                nowTicks,
                EngineDiagnosticEventKind.TapGesture,
                _pendingTapGesture.Side,
                _intentMode,
                DispatchEventKind.None,
                DispatchSuppressReason.None,
                TypingToggleSource.Api,
                0,
                DispatchMouseButton.None,
                _typingEnabled,
                false,
                _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
                _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
                aggregate.ContactCount,
                aggregate.ContactCount,
                _lastRawLeftContacts,
                _lastRawRightContacts,
                "candidate_start");
        }

        if (_pendingTapGesture.Active && aggregate.ContactCount > 0)
        {
            if (aggregate.ContactCount != _pendingTapGesture.ContactCount ||
                aggregate.MaxDistanceMm > _config.TapMoveThresholdMm ||
                (nowTicks - _pendingTapGesture.StartedTicks) > cadenceTicks ||
                (aggregate.LatestStartTicks - aggregate.EarliestStartTicks) > staggerTicks)
            {
                _pendingTapGesture.CandidateValid = false;
                RecordDiagnostic(
                    nowTicks,
                    EngineDiagnosticEventKind.TapGesture,
                    _pendingTapGesture.Side,
                    _intentMode,
                    DispatchEventKind.None,
                    DispatchSuppressReason.None,
                    TypingToggleSource.Api,
                    0,
                    DispatchMouseButton.None,
                    _typingEnabled,
                    false,
                    _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
                    _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
                    aggregate.ContactCount,
                    aggregate.ContactCount,
                    _lastRawLeftContacts,
                    _lastRawRightContacts,
                    "candidate_invalidated");
            }
        }

        if (!releaseBoundary)
        {
            return;
        }

        if (!_pendingTapGesture.Active)
        {
            return;
        }

        bool keyboardOnly = _keyboardModeEnabled && _typingEnabled;
        bool typingSuppressed = _typingEnabled && (_intentMode == IntentMode.TypingCommitted || IsTypingGraceActive(nowTicks));
        bool suppressed = keyboardOnly || typingSuppressed;
        bool cadenceExpired = (nowTicks - _pendingTapGesture.StartedTicks) > cadenceTicks;
        if (_pendingTapGesture.CandidateValid && !suppressed && !cadenceExpired)
        {
            EmitTapGestureClick(_pendingTapGesture.ContactCount, _pendingTapGesture.Side, nowTicks);
            RecordDiagnostic(
                nowTicks,
                EngineDiagnosticEventKind.TapGesture,
                _pendingTapGesture.Side,
                _intentMode,
                DispatchEventKind.MouseButtonClick,
                DispatchSuppressReason.None,
                TypingToggleSource.Api,
                0,
                _pendingTapGesture.ContactCount == 3 ? DispatchMouseButton.Right : DispatchMouseButton.Left,
                _typingEnabled,
                false,
                _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
                _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
                aggregate.ContactCount,
                aggregate.ContactCount,
                _lastRawLeftContacts,
                _lastRawRightContacts,
                "click_emitted");
        }
        else
        {
            string reason = !_pendingTapGesture.CandidateValid
                ? "candidate_invalid"
                : suppressed ? "suppressed" : "cadence_expired";
            RecordDiagnostic(
                nowTicks,
                EngineDiagnosticEventKind.TapGesture,
                _pendingTapGesture.Side,
                _intentMode,
                DispatchEventKind.None,
                DispatchSuppressReason.None,
                TypingToggleSource.Api,
                0,
                DispatchMouseButton.None,
                _typingEnabled,
                false,
                _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
                _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
                aggregate.ContactCount,
                aggregate.ContactCount,
                _lastRawLeftContacts,
                _lastRawRightContacts,
                reason);
        }

        _pendingTapGesture = default;
    }

    private void EmitTapGestureClick(int contactCount, TrackpadSide side, long nowTicks)
    {
        DispatchMouseButton button = contactCount switch
        {
            2 when _config.TwoFingerTapEnabled => DispatchMouseButton.Left,
            3 when _config.ThreeFingerTapEnabled => DispatchMouseButton.Right,
            _ => DispatchMouseButton.None
        };

        if (button == DispatchMouseButton.None)
        {
            return;
        }

        EnqueueDispatchEvent(
            DispatchEventKind.MouseButtonClick,
            0,
            button,
            repeatToken: 0,
            DispatchEventFlags.None,
            side,
            nowTicks,
            dispatchLabel: button == DispatchMouseButton.Left ? "TapClickLeft" : "TapClickRight");
    }

    private void ExtendTypingGrace(long nowTicks)
    {
        long duration = MsToTicks(_config.TypingGraceMs);
        _typingGraceDeadlineTicks = nowTicks + duration;
        if (_intentMode != IntentMode.TypingCommitted)
        {
            SetTypingCommittedState(nowTicks, untilAllUp: true, reason: "typing_grace_extend");
        }
    }

    private bool IsTypingGraceActive(long nowTicks)
    {
        if (_typingGraceDeadlineTicks == 0)
        {
            return false;
        }

        if (nowTicks < _typingGraceDeadlineTicks)
        {
            return true;
        }

        _typingGraceDeadlineTicks = 0;
        return false;
    }

    private void UpdateFiveFingerSwipe(
        TrackpadSide side,
        int contactCount,
        double centroidX,
        double centroidY,
        long timestampTicks)
    {
        ref FiveFingerSwipeState swipe = ref side == TrackpadSide.Left
            ? ref _fiveFingerSwipeLeft
            : ref _fiveFingerSwipeRight;

        if (!swipe.Active)
        {
            if (contactCount >= FiveFingerSwipeArmContacts)
            {
                swipe.Active = true;
                swipe.Triggered = false;
                swipe.StartX = centroidX;
                swipe.StartY = centroidY;
                RecordDiagnostic(
                    timestampTicks,
                    EngineDiagnosticEventKind.FiveFingerState,
                    side,
                    _intentMode,
                    DispatchEventKind.None,
                    DispatchSuppressReason.None,
                    TypingToggleSource.FiveFingerSwipe,
                    0,
                    DispatchMouseButton.None,
                    _typingEnabled,
                    false,
                    swipe.Active,
                    swipe.Triggered,
                    contactCount,
                    contactCount,
                    _lastRawLeftContacts,
                    _lastRawRightContacts,
                    "armed");
            }
            return;
        }

        if (contactCount <= FiveFingerSwipeReleaseContacts)
        {
            swipe.Active = false;
            swipe.Triggered = false;
            RecordDiagnostic(
                timestampTicks,
                EngineDiagnosticEventKind.FiveFingerState,
                side,
                _intentMode,
                DispatchEventKind.None,
                DispatchSuppressReason.None,
                TypingToggleSource.FiveFingerSwipe,
                0,
                DispatchMouseButton.None,
                _typingEnabled,
                false,
                swipe.Active,
                swipe.Triggered,
                contactCount,
                contactCount,
                _lastRawLeftContacts,
                _lastRawRightContacts,
                "released");
            return;
        }

        if (contactCount < FiveFingerSwipeSustainContacts)
        {
            return;
        }

        if (swipe.Triggered)
        {
            return;
        }

        double dxMm = Math.Abs((centroidX - swipe.StartX) * _config.TrackpadWidthMm);
        double dyMm = Math.Abs((centroidY - swipe.StartY) * _config.TrackpadHeightMm);
        if (Math.Max(dxMm, dyMm) >= FiveFingerSwipeThresholdMm)
        {
            swipe.Triggered = true;
            RecordDiagnostic(
                timestampTicks,
                EngineDiagnosticEventKind.FiveFingerState,
                side,
                _intentMode,
                DispatchEventKind.None,
                DispatchSuppressReason.None,
                TypingToggleSource.FiveFingerSwipe,
                0,
                DispatchMouseButton.None,
                _typingEnabled,
                false,
                swipe.Active,
                swipe.Triggered,
                contactCount,
                contactCount,
                _lastRawLeftContacts,
                _lastRawRightContacts,
                "triggered");
            SetTypingEnabledState(!_typingEnabled, timestampTicks, TypingToggleSource.FiveFingerSwipe);
        }
    }

    private void UpdateChordShift(int leftContacts, int rightContacts, long timestampTicks)
    {
        bool prevLeft = _chordShiftLeft;
        bool prevRight = _chordShiftRight;
        if (!_config.ChordShiftEnabled)
        {
            _chordShiftLeft = false;
            _chordShiftRight = false;
            UpdateChordShiftKeyState(timestampTicks);
            if (prevLeft || prevRight)
            {
                RecordDiagnostic(
                    timestampTicks,
                    EngineDiagnosticEventKind.ChordShiftState,
                    TrackpadSide.Left,
                    _intentMode,
                    DispatchEventKind.None,
                    DispatchSuppressReason.None,
                    TypingToggleSource.Api,
                    0,
                    DispatchMouseButton.None,
                    _typingEnabled,
                    false,
                    _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
                    _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
                    _intentTouches.Count,
                    0,
                    leftContacts,
                    rightContacts,
                    "disabled");
            }
            return;
        }

        // Latch chord-shift once 4+ contacts are present on a side.
        // Keep it active until that source side fully releases (0 contacts).
        if (rightContacts >= ChordShiftContactThreshold)
        {
            _chordShiftLeft = true;
        }
        else if (rightContacts == 0)
        {
            _chordShiftLeft = false;
        }

        if (leftContacts >= ChordShiftContactThreshold)
        {
            _chordShiftRight = true;
        }
        else if (leftContacts == 0)
        {
            _chordShiftRight = false;
        }

        UpdateChordShiftKeyState(timestampTicks);
        if (prevLeft != _chordShiftLeft || prevRight != _chordShiftRight)
        {
            RecordDiagnostic(
                timestampTicks,
                EngineDiagnosticEventKind.ChordShiftState,
                TrackpadSide.Left,
                _intentMode,
                DispatchEventKind.None,
                DispatchSuppressReason.None,
                TypingToggleSource.Api,
                0,
                DispatchMouseButton.None,
                _typingEnabled,
                false,
                _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
                _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
                _intentTouches.Count,
                0,
                leftContacts,
                rightContacts,
                "latched");
        }
    }

    private void RefreshStaleRawContactCounts(long nowTicks)
    {
        long staleTicks = MsToTicks(ChordSourceStaleTimeoutMs);
        if (staleTicks <= 0)
        {
            return;
        }

        if (_lastRawLeftContacts > 0 &&
            _lastRawLeftUpdateTicks >= 0 &&
            (nowTicks - _lastRawLeftUpdateTicks) > staleTicks)
        {
            _lastRawLeftContacts = 0;
        }

        if (_lastRawRightContacts > 0 &&
            _lastRawRightUpdateTicks >= 0 &&
            (nowTicks - _lastRawRightUpdateTicks) > staleTicks)
        {
            _lastRawRightContacts = 0;
        }
    }

    private bool IsChordSourceSide(TrackpadSide side)
    {
        // Reserve 5-finger contact sets for swipe gestures (typing toggle),
        // instead of suppressing them as chord-source anchors.
        if (side == TrackpadSide.Left &&
            (_lastRawLeftContacts >= FiveFingerSwipeArmContacts ||
             (_fiveFingerSwipeLeft.Active && _lastRawLeftContacts >= FiveFingerSwipeSustainContacts)))
        {
            return false;
        }

        if (side == TrackpadSide.Right &&
            (_lastRawRightContacts >= FiveFingerSwipeArmContacts ||
             (_fiveFingerSwipeRight.Active && _lastRawRightContacts >= FiveFingerSwipeSustainContacts)))
        {
            return false;
        }

        return side == TrackpadSide.Left ? _chordShiftRight : _chordShiftLeft;
    }

    private void ClearTouchesForChordSourceSide(TrackpadSide side, long timestampTicks)
    {
        int removalCount = 0;
        for (int i = 0; i < _intentTouches.Capacity; i++)
        {
            if (!_intentTouches.IsOccupiedAt(i))
            {
                continue;
            }

            ulong key = _intentTouches.KeyAt(i);
            if (TouchSideFromKey(key) != side)
            {
                continue;
            }

            if (removalCount < _removalBuffer.Length)
            {
                _removalBuffer[removalCount++] = key;
            }
        }

        for (int i = 0; i < removalCount; i++)
        {
            ulong key = _removalBuffer[i];
            _intentTouches.Remove(key, out _);
            CancelTouchWithoutReleaseAction(key, timestampTicks);
        }
    }

    private void CancelTouchWithoutReleaseAction(ulong touchKey, long timestampTicks)
    {
        if (!_touchStates.Remove(touchKey, out TouchBindingState state))
        {
            return;
        }

        if (state.MomentaryLayerTarget >= 0)
        {
            _momentaryLayerTouches.Remove(touchKey, out _);
            UpdateActiveLayer();
            return;
        }

        if (state.DispatchDownSent)
        {
            EndPressAction(ref state, timestampTicks);
        }
    }

    private void UpdateChordShiftKeyState(long timestampTicks)
    {
        bool shouldBeDown = _config.ChordShiftEnabled && (_chordShiftLeft || _chordShiftRight);
        if (shouldBeDown == _chordShiftKeyDown)
        {
            return;
        }

        DispatchEventKind kind = shouldBeDown ? DispatchEventKind.ModifierDown : DispatchEventKind.ModifierUp;
        if (EnqueueDispatchEvent(
            kind,
            ShiftVirtualKey,
            DispatchMouseButton.None,
            repeatToken: 0,
            DispatchEventFlags.None,
            side: TrackpadSide.Left,
            timestampTicks,
            dispatchLabel: "ChordShift"))
        {
            _chordShiftKeyDown = shouldBeDown;
            RecordDiagnostic(
                timestampTicks,
                EngineDiagnosticEventKind.ChordShiftState,
                TrackpadSide.Left,
                _intentMode,
                kind,
                DispatchSuppressReason.None,
                TypingToggleSource.Api,
                ShiftVirtualKey,
                DispatchMouseButton.None,
                _typingEnabled,
                false,
                _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
                _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
                _intentTouches.Count,
                0,
                _lastRawLeftContacts,
                _lastRawRightContacts,
                shouldBeDown ? "shift_down" : "shift_up");
        }
    }

    private static TouchProcessorConfig NormalizeConfig(TouchProcessorConfig config)
    {
        return config with
        {
            HoldDurationMs = Math.Max(0, config.HoldDurationMs),
            DragCancelMm = Math.Max(0, config.DragCancelMm),
            TypingGraceMs = Math.Max(0, config.TypingGraceMs),
            IntentMoveMm = Math.Max(0.1, config.IntentMoveMm),
            IntentVelocityMmPerSec = Math.Max(1.0, config.IntentVelocityMmPerSec),
            SnapRadiusPercent = Math.Clamp(config.SnapRadiusPercent, 0, 200),
            SnapAmbiguityRatio = Math.Max(1.0, config.SnapAmbiguityRatio),
            KeyBufferMs = Math.Max(0, config.KeyBufferMs),
            TapStaggerToleranceMs = Math.Max(0, config.TapStaggerToleranceMs),
            TapCadenceWindowMs = Math.Max(1, config.TapCadenceWindowMs),
            TapMoveThresholdMm = Math.Max(0, config.TapMoveThresholdMm)
        };
    }

    private void TransitionTo(IntentMode next, long timestampTicks, string reason)
    {
        if (_intentMode == next)
        {
            return;
        }

        IntentTransition transition = new(timestampTicks, _intentMode, next, reason);
        _transitionRing[_transitionRingHead] = transition;
        _transitionRingHead = (_transitionRingHead + 1) % _transitionRing.Length;
        if (_transitionRingCount < _transitionRing.Length)
        {
            _transitionRingCount++;
        }

        _intentTraceFingerprint = Mix(_intentTraceFingerprint, (ulong)_intentMode);
        _intentTraceFingerprint = Mix(_intentTraceFingerprint, (ulong)next);
        _intentTraceFingerprint = Mix(_intentTraceFingerprint, StableStringHash(reason));
        _intentMode = next;
        RecordDiagnostic(
            timestampTicks,
            EngineDiagnosticEventKind.IntentTransition,
            TrackpadSide.Left,
            _intentMode,
            DispatchEventKind.None,
            DispatchSuppressReason.None,
            TypingToggleSource.Api,
            0,
            DispatchMouseButton.None,
            _typingEnabled,
            false,
            _fiveFingerSwipeLeft.Active || _fiveFingerSwipeRight.Active,
            _fiveFingerSwipeLeft.Triggered || _fiveFingerSwipeRight.Triggered,
            _intentTouches.Count,
            0,
            _lastRawLeftContacts,
            _lastRawRightContacts,
            reason);
    }

    private void RecordDiagnostic(
        long timestampTicks,
        EngineDiagnosticEventKind kind,
        TrackpadSide side,
        IntentMode intentMode,
        DispatchEventKind dispatchKind,
        DispatchSuppressReason suppressReason,
        TypingToggleSource toggleSource,
        ushort virtualKey,
        DispatchMouseButton mouseButton,
        bool typingEnabled,
        bool chordSourceSuppressed,
        bool fiveFingerActive,
        bool fiveFingerTriggered,
        int contactCount,
        int tipContactCount,
        int leftRawContacts,
        int rightRawContacts,
        string reason,
        string dispatchLabel = "")
    {
        if (!_diagnosticsEnabled)
        {
            return;
        }

        _diagnosticRing[_diagnosticRingHead] = new EngineDiagnosticEvent(
            timestampTicks,
            kind,
            side,
            intentMode,
            dispatchKind,
            suppressReason,
            toggleSource,
            virtualKey,
            mouseButton,
            typingEnabled,
            chordSourceSuppressed,
            fiveFingerActive,
            fiveFingerTriggered,
            contactCount,
            tipContactCount,
            leftRawContacts,
            rightRawContacts,
            dispatchLabel,
            reason);
        _diagnosticRingHead = (_diagnosticRingHead + 1) % _diagnosticRing.Length;
        if (_diagnosticRingCount < _diagnosticRing.Length)
        {
            _diagnosticRingCount++;
        }
    }

    private static ulong MakeTouchKey(TrackpadSide side, uint contactId)
    {
        ulong sideBits = side == TrackpadSide.Left ? 0ul : 1ul;
        return (sideBits << 32) | contactId;
    }

    private static TrackpadSide TouchSideFromKey(ulong key)
    {
        return ((key >> 32) & 1ul) == 0ul ? TrackpadSide.Left : TrackpadSide.Right;
    }

    private static bool Contains(ReadOnlySpan<ulong> values, ulong value)
    {
        for (int i = 0; i < values.Length; i++)
        {
            if (values[i] == value)
            {
                return true;
            }
        }

        return false;
    }

    private static double SafeNormalize(ushort value, ushort max)
    {
        if (max == 0)
        {
            return 0;
        }

        return value / (double)max;
    }

    private double DistanceMm(double x1Norm, double y1Norm, double x2Norm, double y2Norm)
    {
        double dxMm = (x2Norm - x1Norm) * _config.TrackpadWidthMm;
        double dyMm = (y2Norm - y1Norm) * _config.TrackpadHeightMm;
        return Math.Sqrt((dxMm * dxMm) + (dyMm * dyMm));
    }

    private static float DistanceSqToRectEdge(double x, double y, NormalizedRect rect)
    {
        float px = (float)x;
        float py = (float)y;
        float minX = (float)rect.X;
        float maxX = (float)(rect.X + rect.Width);
        float minY = (float)rect.Y;
        float maxY = (float)(rect.Y + rect.Height);
        float dx = px < minX ? (minX - px) : (px > maxX ? (px - maxX) : 0);
        float dy = py < minY ? (minY - py) : (py > maxY ? (py - maxY) : 0);
        return (dx * dx) + (dy * dy);
    }

    private static long MsToTicks(double milliseconds)
    {
        if (milliseconds <= 0)
        {
            return 0;
        }

        return (long)Math.Round(milliseconds * Stopwatch.Frequency / 1000.0);
    }

    private static ulong Mix(ulong hash, ulong value)
    {
        hash ^= value;
        hash *= 1099511628211ul;
        return hash;
    }

    private static ulong StableStringHash(string text)
    {
        ulong hash = 14695981039346656037ul;
        for (int i = 0; i < text.Length; i++)
        {
            ushort ch = text[i];
            hash = Mix(hash, (byte)(ch & 0xFF));
            hash = Mix(hash, (byte)((ch >> 8) & 0xFF));
        }

        return hash;
    }

    private readonly record struct IntentAggregate(
        int ContactCount,
        int LeftContacts,
        int RightContacts,
        int OnKeyCount,
        int OffKeyCount,
        bool KeyboardAnchor,
        double MaxDistanceMm,
        double MaxVelocityMmPerSec,
        double CentroidX,
        double CentroidY,
        bool HasFirstOnKeyTouch,
        ulong FirstOnKeyTouch,
        long EarliestStartTicks,
        long LatestStartTicks);

    private struct IntentTouchInfo
    {
        public IntentTouchInfo(
            TrackpadSide Side,
            double StartXNorm,
            double StartYNorm,
            double LastXNorm,
            double LastYNorm,
            long StartTicks,
            long LastTicks,
            double MaxDistanceMm,
            double LastVelocityMmPerSec,
            bool OnKey,
            bool KeyboardAnchor,
            int InitialBindingIndex)
        {
            this.Side = Side;
            this.StartXNorm = StartXNorm;
            this.StartYNorm = StartYNorm;
            this.LastXNorm = LastXNorm;
            this.LastYNorm = LastYNorm;
            this.StartTicks = StartTicks;
            this.LastTicks = LastTicks;
            this.MaxDistanceMm = MaxDistanceMm;
            this.LastVelocityMmPerSec = LastVelocityMmPerSec;
            this.OnKey = OnKey;
            this.KeyboardAnchor = KeyboardAnchor;
            this.InitialBindingIndex = InitialBindingIndex;
        }

        public TrackpadSide Side;
        public double StartXNorm;
        public double StartYNorm;
        public double LastXNorm;
        public double LastYNorm;
        public long StartTicks;
        public long LastTicks;
        public double MaxDistanceMm;
        public double LastVelocityMmPerSec;
        public bool OnKey;
        public bool KeyboardAnchor;
        public int InitialBindingIndex;
    }

    private struct TouchBindingState
    {
        public TouchBindingState(
            TrackpadSide Side,
            int BindingIndex,
            EngineTouchLifecycle Lifecycle,
            long StartTicks,
            double StartXNorm,
            double StartYNorm,
            double LastXNorm,
            double LastYNorm,
            double MaxDistanceMm,
            bool HasHoldAction,
            bool HoldTriggered,
            int MomentaryLayerTarget,
            bool DispatchDownSent,
            DispatchEventKind DispatchDownKind,
            ushort DispatchDownVirtualKey,
            DispatchMouseButton DispatchDownMouseButton,
            ulong RepeatToken,
            string DispatchDownLabel)
        {
            this.Side = Side;
            this.BindingIndex = BindingIndex;
            this.Lifecycle = Lifecycle;
            this.StartTicks = StartTicks;
            this.StartXNorm = StartXNorm;
            this.StartYNorm = StartYNorm;
            this.LastXNorm = LastXNorm;
            this.LastYNorm = LastYNorm;
            this.MaxDistanceMm = MaxDistanceMm;
            this.HasHoldAction = HasHoldAction;
            this.HoldTriggered = HoldTriggered;
            this.MomentaryLayerTarget = MomentaryLayerTarget;
            this.DispatchDownSent = DispatchDownSent;
            this.DispatchDownKind = DispatchDownKind;
            this.DispatchDownVirtualKey = DispatchDownVirtualKey;
            this.DispatchDownMouseButton = DispatchDownMouseButton;
            this.RepeatToken = RepeatToken;
            this.DispatchDownLabel = DispatchDownLabel;
        }

        public TrackpadSide Side;
        public int BindingIndex;
        public EngineTouchLifecycle Lifecycle;
        public long StartTicks;
        public double StartXNorm;
        public double StartYNorm;
        public double LastXNorm;
        public double LastYNorm;
        public double MaxDistanceMm;
        public bool HasHoldAction;
        public bool HoldTriggered;
        public int MomentaryLayerTarget;
        public bool DispatchDownSent;
        public DispatchEventKind DispatchDownKind;
        public ushort DispatchDownVirtualKey;
        public DispatchMouseButton DispatchDownMouseButton;
        public ulong RepeatToken;
        public string DispatchDownLabel;
    }

    private struct PendingTapGesture
    {
        public PendingTapGesture(
            bool Active,
            bool CandidateValid,
            int ContactCount,
            TrackpadSide Side,
            long StartedTicks,
            long EarliestTouchTicks,
            long LatestTouchTicks)
        {
            this.Active = Active;
            this.CandidateValid = CandidateValid;
            this.ContactCount = ContactCount;
            this.Side = Side;
            this.StartedTicks = StartedTicks;
            this.EarliestTouchTicks = EarliestTouchTicks;
            this.LatestTouchTicks = LatestTouchTicks;
        }

        public bool Active;
        public bool CandidateValid;
        public int ContactCount;
        public TrackpadSide Side;
        public long StartedTicks;
        public long EarliestTouchTicks;
        public long LatestTouchTicks;
    }

    private struct FiveFingerSwipeState
    {
        public bool Active;
        public bool Triggered;
        public double StartX;
        public double StartY;
    }
}

internal sealed class TouchProcessorActor : IDisposable
{
    private readonly TouchProcessorCore _core;
    private readonly object _coreGate = new();
    private readonly DispatchEventQueue? _dispatchQueue;
    private readonly FrameEnvelope[] _queue;
    private readonly object _gate = new();
    private readonly AutoResetEvent _signal = new(false);
    private readonly Thread _thread;
    private bool _disposing;
    private int _head;
    private int _tail;
    private int _count;
    private long _postedCount;
    private long _processedCount;

    public TouchProcessorActor(TouchProcessorCore core, int queueCapacity = 2048, DispatchEventQueue? dispatchQueue = null)
    {
        _core = core;
        _dispatchQueue = dispatchQueue;
        _queue = new FrameEnvelope[Math.Max(16, queueCapacity)];
        _thread = new Thread(RunLoop)
        {
            IsBackground = true,
            Name = "GlassToKey.TouchProcessor"
        };
        _thread.Start();
    }

    public bool Post(TrackpadSide side, in InputFrame frame, ushort maxX, ushort maxY, long timestampTicks)
    {
        lock (_gate)
        {
            if (_disposing)
            {
                return false;
            }

            if (_count >= _queue.Length)
            {
                _core.RecordQueueDrop();
                return false;
            }

            _queue[_tail] = new FrameEnvelope(side, frame, maxX, maxY, timestampTicks);
            _tail = (_tail + 1) % _queue.Length;
            _count++;
            _postedCount++;
            _signal.Set();
            return true;
        }
    }

    public void Configure(TouchProcessorConfig config)
    {
        lock (_coreGate)
        {
            _core.Configure(config);
        }
    }

    public void ConfigureLayouts(KeyLayout leftLayout, KeyLayout rightLayout)
    {
        lock (_coreGate)
        {
            _core.ConfigureLayouts(leftLayout, rightLayout);
        }
    }

    public void ConfigureKeymap(KeymapStore keymap)
    {
        lock (_coreGate)
        {
            _core.ConfigureKeymap(keymap);
        }
    }

    public void SetPersistentLayer(int layer)
    {
        lock (_coreGate)
        {
            _core.SetPersistentLayer(layer);
        }
    }

    public void SetTypingEnabled(bool enabled)
    {
        lock (_coreGate)
        {
            _core.SetTypingEnabled(enabled);
        }
    }

    public void SetKeyboardModeEnabled(bool enabled)
    {
        lock (_coreGate)
        {
            _core.SetKeyboardModeEnabled(enabled);
        }
    }

    public void SetAllowMouseTakeover(bool enabled)
    {
        lock (_coreGate)
        {
            _core.SetAllowMouseTakeover(enabled);
        }
    }

    public void SetDiagnosticsEnabled(bool enabled)
    {
        lock (_coreGate)
        {
            _core.SetDiagnosticsEnabled(enabled);
        }
    }

    public bool WaitForIdle(int timeoutMs = 2000)
    {
        Stopwatch sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs)
        {
            if (Volatile.Read(ref _processedCount) >= Volatile.Read(ref _postedCount))
            {
                return true;
            }

            Thread.Sleep(1);
        }

        return Volatile.Read(ref _processedCount) >= Volatile.Read(ref _postedCount);
    }

    public TouchProcessorSnapshot Snapshot()
    {
        lock (_coreGate)
        {
            return _core.Snapshot();
        }
    }

    public void ResetState()
    {
        lock (_coreGate)
        {
            _core.ResetState();
        }
    }

    public int CopyIntentTransitions(Span<IntentTransition> destination)
    {
        lock (_coreGate)
        {
            return _core.CopyIntentTransitions(destination);
        }
    }

    public int CopyDiagnostics(Span<EngineDiagnosticEvent> destination)
    {
        lock (_coreGate)
        {
            return _core.CopyDiagnostics(destination);
        }
    }

    public int DrainDispatchEvents(Span<DispatchEvent> destination)
    {
        lock (_coreGate)
        {
            return _core.DrainDispatchEvents(destination);
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            _disposing = true;
            _signal.Set();
        }

        _thread.Join();
        _signal.Dispose();
    }

    private void RunLoop()
    {
        DispatchEvent[] scratchBuffer = new DispatchEvent[16];
        while (true)
        {
            FrameEnvelope frame;
            bool hasFrame = false;
            lock (_gate)
            {
                if (_count > 0)
                {
                    frame = _queue[_head];
                    _head = (_head + 1) % _queue.Length;
                    _count--;
                    hasFrame = true;
                }
                else if (_disposing)
                {
                    return;
                }
                else
                {
                    frame = default;
                }
            }

            if (!hasFrame)
            {
                _signal.WaitOne(4);
                continue;
            }

            InputFrame payload = frame.Frame;
            lock (_coreGate)
            {
                _core.ProcessFrame(frame.Side, in payload, frame.MaxX, frame.MaxY, frame.TimestampTicks);
                if (_dispatchQueue != null)
                {
                    while (true)
                    {
                        int drained = _core.DrainDispatchEvents(scratchBuffer);
                        if (drained <= 0)
                        {
                            break;
                        }

                        for (int i = 0; i < drained; i++)
                        {
                            if (!_dispatchQueue.TryEnqueue(in scratchBuffer[i]))
                            {
                                _core.RecordDispatchDrop();
                            }
                        }
                    }
                }
            }
            Interlocked.Increment(ref _processedCount);
        }
    }

    private readonly record struct FrameEnvelope(
        TrackpadSide Side,
        InputFrame Frame,
        ushort MaxX,
        ushort MaxY,
        long TimestampTicks);
}
