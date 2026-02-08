using System;
using System.Diagnostics;

namespace AmtPtpVisualizer;

public sealed class TouchState
{
    private readonly object _lock = new();
    private readonly TouchContact[] _contacts = new TouchContact[PtpReport.MaxContacts];
    private int _contactCount;
    private ushort _maxX = 1;
    private ushort _maxY = 1;
    private long _lastFrameTicks;
    private readonly long _stateStaleTicks = Stopwatch.Frequency / 6;

    public int SnapshotContacts(Span<TouchContact> destination)
    {
        lock (_lock)
        {
            if (_contactCount > 0 &&
                _lastFrameTicks > 0 &&
                Stopwatch.GetTimestamp() - _lastFrameTicks > _stateStaleTicks)
            {
                _contactCount = 0;
            }

            int count = _contactCount <= destination.Length ? _contactCount : destination.Length;
            _contacts.AsSpan(0, count).CopyTo(destination);
            return count;
        }
    }

    public (ushort MaxX, ushort MaxY) SnapshotMax()
    {
        lock (_lock)
        {
            return (_maxX, _maxY);
        }
    }

    public void Update(in InputFrame report)
    {
        lock (_lock)
        {
            _lastFrameTicks = report.ArrivalQpcTicks;
            _contactCount = 0;
            int count = report.GetClampedContactCount();
            for (int i = 0; i < count; i++)
            {
                ContactFrame c = report.GetContact(i);
                // Visualizer policy: render only physical-touch contacts.
                if (!c.TipSwitch)
                {
                    continue;
                }

                _contacts[_contactCount++] = new TouchContact(c.Id, c.X, c.Y, c.TipSwitch, c.Confidence);
                if (c.X > _maxX) _maxX = c.X;
                if (c.Y > _maxY) _maxY = c.Y;
            }
        }
    }

    public void Clear()
    {
        lock (_lock)
        {
            _contactCount = 0;
            _maxX = 1;
            _maxY = 1;
            _lastFrameTicks = 0;
        }
    }
}

public readonly record struct TouchContact(uint Id, ushort X, ushort Y, bool Tip, bool Confidence);
