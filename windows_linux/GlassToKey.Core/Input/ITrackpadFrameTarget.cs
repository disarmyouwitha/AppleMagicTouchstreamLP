namespace GlassToKey;

public readonly record struct TrackpadFrameEnvelope(
    TrackpadSide Side,
    InputFrame Frame,
    ushort MaxX,
    ushort MaxY,
    long TimestampTicks);

public interface ITrackpadFrameTarget
{
    bool Post(in TrackpadFrameEnvelope frame);
}
