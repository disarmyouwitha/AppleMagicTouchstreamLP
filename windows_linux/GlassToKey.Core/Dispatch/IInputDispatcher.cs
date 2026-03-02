using System;

namespace GlassToKey;

public interface IInputDispatcher : IDisposable
{
    void Dispatch(in DispatchEvent dispatchEvent);
    void Tick(long nowTicks);
}
