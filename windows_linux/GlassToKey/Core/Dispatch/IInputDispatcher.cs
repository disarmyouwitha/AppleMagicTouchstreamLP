using System;

namespace GlassToKey;

internal interface IInputDispatcher : IDisposable
{
    void Dispatch(in DispatchEvent dispatchEvent);
    void Tick(long nowTicks);
}
