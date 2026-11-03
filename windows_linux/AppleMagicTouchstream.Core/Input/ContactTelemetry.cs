namespace AppleMagicTouchstream;

// Optional sensor-reported shape/classification. Tracking Id remains separate;
// missing telemetry must never be interpreted as an anatomical classification.
public readonly record struct ContactTelemetry(
    ushort Width, ushort Height, byte Size, byte TouchMajor, byte TouchMinor,
    byte Orientation, byte FingerType, byte State);
