using System.Diagnostics;

namespace GlassToKey;

public readonly record struct DispatchRepeatProfile(
    double InitialDelayMs,
    double IntervalMs)
{
    public static DispatchRepeatProfile Default { get; } = new(275.0, 33.0);

    public long GetInitialDelayTicks()
    {
        return MsToTicks(InitialDelayMs);
    }

    public long GetIntervalTicks()
    {
        return MsToTicks(IntervalMs);
    }

    private static long MsToTicks(double milliseconds)
    {
        return (long)(milliseconds * Stopwatch.Frequency / 1000.0);
    }
}
