namespace GlassToKey;

public static class ForceNormalizer
{
    public const int PhaseSpan = 255;
    public const int LastPhaseCap = 220;
    public const int Max = (PhaseSpan * 3) + LastPhaseCap; // 985

    public static int Compute(byte pressure, byte phase)
    {
        return phase switch
        {
            0 => pressure,
            1 => PhaseSpan + pressure,
            2 => (PhaseSpan * 2) + pressure,
            3 => (PhaseSpan * 3) + System.Math.Min((int)pressure, LastPhaseCap),
            _ => pressure
        };
    }
}
