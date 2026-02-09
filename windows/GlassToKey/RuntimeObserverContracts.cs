namespace GlassToKey;

internal enum RuntimeModeIndicator : byte
{
    Unknown = 0,
    Mouse = 1,
    Mixed = 2,
    Keyboard = 3,
    LayerActive = 4
}

internal interface IRuntimeFrameObserver
{
    void OnRuntimeFrame(TrackpadSide side, in InputFrame frame, RawInputDeviceTag tag);
}
