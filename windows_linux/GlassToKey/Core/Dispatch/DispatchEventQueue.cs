using System;
using System.Threading;

namespace GlassToKey;

internal sealed class DispatchEventQueue : IDisposable
{
    private readonly DispatchEvent[] _queue;
    private readonly object _gate = new();
    private readonly AutoResetEvent _signal = new(false);

    private bool _completed;
    private bool _disposed;
    private int _head;
    private int _tail;
    private int _count;
    private long _drops;

    public DispatchEventQueue(int capacity = 4096)
    {
        _queue = new DispatchEvent[Math.Max(64, capacity)];
    }

    public long Drops => Interlocked.Read(ref _drops);

    public int Count
    {
        get
        {
            lock (_gate)
            {
                return _count;
            }
        }
    }

    public bool IsCompleted
    {
        get
        {
            lock (_gate)
            {
                return _completed;
            }
        }
    }

    public bool TryEnqueue(in DispatchEvent dispatchEvent)
    {
        lock (_gate)
        {
            if (_completed)
            {
                Interlocked.Increment(ref _drops);
                return false;
            }

            if (_count >= _queue.Length)
            {
                Interlocked.Increment(ref _drops);
                return false;
            }

            _queue[_tail] = dispatchEvent;
            _tail = (_tail + 1) % _queue.Length;
            _count++;
            _signal.Set();
            return true;
        }
    }

    public bool TryDequeue(out DispatchEvent dispatchEvent, int waitMs = 4)
    {
        while (true)
        {
            lock (_gate)
            {
                if (_count > 0)
                {
                    dispatchEvent = _queue[_head];
                    _head = (_head + 1) % _queue.Length;
                    _count--;
                    return true;
                }

                if (_completed)
                {
                    dispatchEvent = default;
                    return false;
                }
            }

            if (!_signal.WaitOne(waitMs))
            {
                dispatchEvent = default;
                return false;
            }
        }
    }

    public void Complete()
    {
        lock (_gate)
        {
            _completed = true;
            _signal.Set();
        }
    }

    public void Clear()
    {
        lock (_gate)
        {
            if (_completed)
            {
                return;
            }

            _head = 0;
            _tail = 0;
            _count = 0;
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        Complete();
        _signal.Dispose();
    }
}
