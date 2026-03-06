using System;

namespace GlassToKey;

public interface IInputDispatcher : IDisposable
{
    void Dispatch(in DispatchEvent dispatchEvent);
    void Tick(long nowTicks);
}

public readonly record struct InputDispatcherDiagnostics(
    long DispatchCalls,
    long TickCalls,
    long SendFailures,
    int ActiveRepeats,
    int KeysDown,
    int ActiveModifiers,
    long LastDispatchTicks,
    long LastTickTicks,
    string LastErrorMessage);

public interface IInputDispatcherDiagnosticsProvider
{
    bool TryGetDiagnostics(out InputDispatcherDiagnostics diagnostics);
}
