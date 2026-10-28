namespace AppleMagicTouchstream;

internal interface IRuntimeFrameObserver
{
    void OnDecoderProfileDetected(TrackpadSide side, TrackpadDecoderProfile profile);
    void OnRuntimeFrame(TrackpadSide side, in InputFrame frame, in ButtonEdgeState buttonState, RawInputDeviceTag tag);
}
