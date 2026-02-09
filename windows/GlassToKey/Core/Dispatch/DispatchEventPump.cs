using System;
using System.Diagnostics;
using System.Threading;

namespace GlassToKey;

internal sealed class DispatchEventPump : IDisposable
{
    private readonly DispatchEventQueue _queue;
    private readonly IInputDispatcher _dispatcher;
    private readonly Thread _thread;
    private bool _disposed;

    public DispatchEventPump(DispatchEventQueue queue, IInputDispatcher dispatcher)
    {
        _queue = queue;
        _dispatcher = dispatcher;
        _thread = new Thread(RunLoop)
        {
            IsBackground = true,
            Name = "GlassToKey.DispatchPump"
        };
        _thread.Start();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _queue.Complete();
        _thread.Join();
        _dispatcher.Dispose();
    }

    private void RunLoop()
    {
        while (true)
        {
            bool hasEvent = _queue.TryDequeue(out DispatchEvent dispatchEvent, waitMs: 4);
            long nowTicks = Stopwatch.GetTimestamp();
            if (hasEvent)
            {
                _dispatcher.Dispatch(in dispatchEvent);
                _dispatcher.Tick(nowTicks);
                continue;
            }

            _dispatcher.Tick(nowTicks);
            if (_queue.IsCompleted && _queue.Count == 0)
            {
                return;
            }
        }
    }
}
