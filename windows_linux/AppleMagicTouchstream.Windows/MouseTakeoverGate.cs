using System;
using System.Diagnostics;
using System.Threading;

namespace AppleMagicTouchstream;

// Pure deadline/filter policy; ordinary production input is unchanged while unarmed.
internal sealed class MouseTakeoverGate
{
    private long _deadline;
    public bool IsActive(long now) => now < Interlocked.Read(ref _deadline);
    public long Arm(long now, TimeSpan duration)
    {
        if (duration <= TimeSpan.Zero || duration > TimeSpan.FromSeconds(30))
            throw new ArgumentOutOfRangeException(nameof(duration));
        long deadline = checked(now + (long)(duration.TotalSeconds * Stopwatch.Frequency));
        Interlocked.Exchange(ref _deadline, deadline);
        return deadline;
    }
    public void Release() => Interlocked.Exchange(ref _deadline, 0);
    public void Release(long expectedDeadline) => Interlocked.CompareExchange(ref _deadline, 0, expectedDeadline);
    public bool ShouldBlock(bool isMouseEvent, bool isInjected, long now, bool emergencyRelease)
    {
        if (emergencyRelease) Release();
        return isMouseEvent && !isInjected && IsActive(now);
    }
}
