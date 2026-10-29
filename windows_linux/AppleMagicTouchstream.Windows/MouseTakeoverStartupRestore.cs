using System.Diagnostics;

namespace AppleMagicTouchstream;

// Only initial saved opt-in waits/retries. Activation or explicit release ends it.
internal sealed class MouseTakeoverStartupRestore
{
    public bool Pending { get; private set; }
    private long _nextAttempt;
    public void Begin(bool remembered) { Pending=remembered; _nextAttempt=0; }
    public void Cancel() => Pending=false;
    public bool Due(long now)
    {
        if(!Pending || now<_nextAttempt) return false;
        _nextAttempt=now+2*Stopwatch.Frequency;
        return true;
    }
}
