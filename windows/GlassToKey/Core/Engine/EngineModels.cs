using System;
using System.Globalization;

namespace GlassToKey;

internal enum IntentMode
{
    Idle = 0,
    KeyCandidate = 1,
    TypingCommitted = 2,
    MouseCandidate = 3,
    MouseActive = 4,
    GestureCandidate = 5
}

internal enum EngineTouchLifecycle
{
    Pending = 0,
    Active = 1
}

internal enum EngineActionKind
{
    None = 0,
    Key = 1,
    MomentaryLayer = 2,
    LayerSet = 3,
    LayerToggle = 4,
    TypingToggle = 5,
    Modifier = 6,
    Continuous = 7,
    MouseButton = 8,
    KeyChord = 9
}

internal enum TypingToggleSource : byte
{
    Api = 0,
    KeyAction = 1,
    FiveFingerSwipe = 2
}

internal enum EngineDiagnosticEventKind : byte
{
    Frame = 0,
    IntentTransition = 1,
    DispatchEnqueued = 2,
    DispatchSuppressed = 3,
    TypingToggle = 4,
    FiveFingerState = 5,
    ChordShiftState = 6,
    TapGesture = 7,
    ReleaseDropped = 8
}

internal enum DispatchSuppressReason : byte
{
    None = 0,
    TypingDisabled = 1,
    DispatchRingFull = 2,
    ForceThreshold = 3
}

internal readonly record struct EngineKeyAction(
    EngineActionKind Kind,
    string Label,
    int LayerTarget = 0,
    ushort VirtualKey = 0,
    DispatchMouseButton MouseButton = DispatchMouseButton.None,
    ushort ModifierVirtualKey = 0)
{
    public static EngineKeyAction None => new(EngineActionKind.None, "None");
}

internal readonly record struct EngineKeyMapping(
    EngineKeyAction Primary,
    EngineKeyAction Hold,
    bool HasHold);

internal readonly record struct EngineKeyBinding(
    TrackpadSide Side,
    int Row,
    int Column,
    string StorageKey,
    string Label,
    NormalizedRect Rect,
    EngineKeyMapping Mapping);

internal readonly record struct EngineCustomButton(
    int Layer,
    TrackpadSide Side,
    string Id,
    string Label,
    NormalizedRect Rect,
    EngineKeyMapping Mapping);

internal readonly record struct EngineLayeredMappings(
    int Layer,
    EngineKeyBinding[] Keys,
    EngineCustomButton[] CustomButtons);

internal readonly record struct EngineBindingHit(bool Found, int BindingIndex)
{
    public static EngineBindingHit Miss => new(false, -1);
}

internal readonly record struct TouchProcessorSnapshot(
    IntentMode IntentMode,
    int ActiveLayer,
    bool MomentaryLayerActive,
    bool TypingEnabled,
    bool KeyboardModeEnabled,
    int ContactCount,
    int LeftContacts,
    int RightContacts,
    bool FiveFingerSwipeTriggered,
    bool ChordShiftLeft,
    bool ChordShiftRight,
    long FramesProcessed,
    long QueueDrops,
    long DispatchEnqueued,
    long DispatchSuppressedTypingDisabled,
    long DispatchSuppressedRingFull,
    long SnapAttempts,
    long SnapAccepted,
    long SnapRejected,
    ulong IntentTraceFingerprint)
{
    public string ToSummary()
    {
        return string.Create(
            CultureInfo.InvariantCulture,
            $"intent={IntentMode}, layer={ActiveLayer}, mo={MomentaryLayerActive}, typing={TypingEnabled}, contacts={ContactCount} (L={LeftContacts}, R={RightContacts}), frames={FramesProcessed}, drops={QueueDrops}, dispatch={DispatchEnqueued} (suppressed:{DispatchSuppressedTypingDisabled}, ring:{DispatchSuppressedRingFull}), snap={SnapAccepted}/{SnapAttempts}, trace=0x{IntentTraceFingerprint:X16}");
    }
}

internal readonly record struct EngineDiagnosticEvent(
    long TimestampTicks,
    EngineDiagnosticEventKind Kind,
    TrackpadSide Side,
    IntentMode IntentMode,
    DispatchEventKind DispatchKind,
    DispatchSuppressReason SuppressReason,
    TypingToggleSource ToggleSource,
    ushort VirtualKey,
    DispatchMouseButton MouseButton,
    bool TypingEnabled,
    bool ChordSourceSuppressed,
    bool FiveFingerActive,
    bool FiveFingerTriggered,
    int ContactCount,
    int TipContactCount,
    int LeftRawContacts,
    int RightRawContacts,
    string DispatchLabel,
    string Reason);

internal readonly record struct IntentTransition(
    long TimestampTicks,
    IntentMode Previous,
    IntentMode Current,
    string Reason);

internal readonly record struct TouchProcessorConfig(
    double TrackpadWidthMm,
    double TrackpadHeightMm,
    double HoldDurationMs,
    double DragCancelMm,
    double TypingGraceMs,
    double IntentMoveMm,
    double IntentVelocityMmPerSec,
    double SnapRadiusPercent,
    double SnapAmbiguityRatio,
    double KeyBufferMs,
    bool TapClickEnabled,
    bool TwoFingerTapEnabled,
    bool ThreeFingerTapEnabled,
    string TwoFingerTapAction,
    string ThreeFingerTapAction,
    string FiveFingerSwipeLeftAction,
    string FiveFingerSwipeRightAction,
    string FourFingerHoldAction,
    string OuterCornersAction,
    string InnerCornersAction,
    double TapStaggerToleranceMs,
    double TapCadenceWindowMs,
    double TapMoveThresholdMm,
    int ForceMin,
    int ForceCap,
    bool ChordShiftEnabled)
{
    public static TouchProcessorConfig Default => new(
        TrackpadWidthMm: 160.0,
        TrackpadHeightMm: 114.9,
        HoldDurationMs: 120.0,
        DragCancelMm: 3.0,
        TypingGraceMs: 120.0,
        IntentMoveMm: 3.0,
        IntentVelocityMmPerSec: 50.0,
        SnapRadiusPercent: 35.0,
        SnapAmbiguityRatio: 1.15,
        KeyBufferMs: 40.0,
        TapClickEnabled: true,
        TwoFingerTapEnabled: true,
        ThreeFingerTapEnabled: true,
        TwoFingerTapAction: "Left Click",
        ThreeFingerTapAction: "Right Click",
        FiveFingerSwipeLeftAction: "Typing Toggle",
        FiveFingerSwipeRightAction: "Typing Toggle",
        FourFingerHoldAction: "Chordal Shift",
        OuterCornersAction: "None",
        InnerCornersAction: "None",
        TapStaggerToleranceMs: 40.0,
        TapCadenceWindowMs: 260.0,
        TapMoveThresholdMm: 2.2,
        ForceMin: 0,
        ForceCap: 255,
        ChordShiftEnabled: true);
}
