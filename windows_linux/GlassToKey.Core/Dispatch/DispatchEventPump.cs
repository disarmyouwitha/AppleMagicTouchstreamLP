using System;
using System.Diagnostics;
using System.Threading;

namespace GlassToKey;

internal sealed class DispatchEventPump : IDisposable
{
    private readonly DispatchEventQueue _queue;
    private readonly IInputDispatcher _dispatcher;
    private readonly Thread _thread;
    private long _dispatchCalls;
    private long _tickCalls;
    private long _lastDispatchTicks;
    private long _lastTickTicks;
    private long _lastFaultTicks;
    private string _lastFaultMessage = string.Empty;
    private int _loopExited;
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
                try
                {
                    _dispatcher.Dispatch(in dispatchEvent);
                    Interlocked.Increment(ref _dispatchCalls);
                    Volatile.Write(ref _lastDispatchTicks, nowTicks);
                }
                catch (Exception ex)
                {
                    Volatile.Write(ref _lastFaultTicks, nowTicks);
                    Volatile.Write(ref _lastFaultMessage, $"{ex.GetType().Name}: {ex.Message}");
                    Thread.Sleep(2);
                }

                try
                {
                    _dispatcher.Tick(nowTicks);
                    Interlocked.Increment(ref _tickCalls);
                    Volatile.Write(ref _lastTickTicks, nowTicks);
                }
                catch (Exception ex)
                {
                    Volatile.Write(ref _lastFaultTicks, nowTicks);
                    Volatile.Write(ref _lastFaultMessage, $"{ex.GetType().Name}: {ex.Message}");
                    Thread.Sleep(2);
                }

                continue;
            }

            try
            {
                _dispatcher.Tick(nowTicks);
                Interlocked.Increment(ref _tickCalls);
                Volatile.Write(ref _lastTickTicks, nowTicks);
            }
            catch (Exception ex)
            {
                Volatile.Write(ref _lastFaultTicks, nowTicks);
                Volatile.Write(ref _lastFaultMessage, $"{ex.GetType().Name}: {ex.Message}");
                Thread.Sleep(2);
            }

            if (_queue.IsCompleted && _queue.Count == 0)
            {
                Volatile.Write(ref _loopExited, 1);
                return;
            }
        }
    }

    public DispatchEventPumpDiagnostics Snapshot()
    {
        return new DispatchEventPumpDiagnostics(
            IsAlive: Volatile.Read(ref _loopExited) == 0,
            DispatchCalls: Interlocked.Read(ref _dispatchCalls),
            TickCalls: Interlocked.Read(ref _tickCalls),
            LastDispatchTicks: Volatile.Read(ref _lastDispatchTicks),
            LastTickTicks: Volatile.Read(ref _lastTickTicks),
            LastFaultTicks: Volatile.Read(ref _lastFaultTicks),
            LastFaultMessage: Volatile.Read(ref _lastFaultMessage) ?? string.Empty);
    }
}

internal readonly record struct DispatchEventPumpDiagnostics(
    bool IsAlive,
    long DispatchCalls,
    long TickCalls,
    long LastDispatchTicks,
    long LastTickTicks,
    long LastFaultTicks,
    string LastFaultMessage);
