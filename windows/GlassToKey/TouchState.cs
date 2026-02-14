using System;
using System.Diagnostics;

namespace GlassToKey;

public enum PressureCapability : byte
{
    Unknown = 0,
    Supported = 1,
    Unsupported = 2
}

public sealed class TouchState
{
    private const int PressureLargeJumpThreshold = 12;
    private const int PressureEarlyDecisionSamples = 16;
    private const int PressureDecisionSamples = 40;
    private const int PressureMaxProbeSamples = 120;

    private readonly object _lock = new();
    private readonly TouchContact[] _contacts = new TouchContact[PtpReport.MaxContacts];
    private int _contactCount;
    private PressureCapability _pressureCapability;
    private bool _pressureHintUnsupported;
    private int _pressureSampleCount;
    private int _pressureNonZeroCount;
    private int _pressureComparedCount;
    private int _pressureLargeJumpCount;
    private bool _pressureHasLastSample;
    private byte _pressureLastSample;
    private ushort _maxX = 1;
    private ushort _maxY = 1;
    private long _lastFrameTicks;
    private readonly long _stateStaleTicks = Stopwatch.Frequency / 6;

    public int SnapshotContacts(Span<TouchContact> destination)
    {
        SnapshotStateCore(destination, out _, out _, out _, out int count);
        return count;
    }

    public int Snapshot(Span<TouchContact> destination, out ushort maxX, out ushort maxY, out PressureCapability pressureCapability)
    {
        SnapshotStateCore(destination, out maxX, out maxY, out pressureCapability, out int count);
        return count;
    }

    public (ushort MaxX, ushort MaxY) SnapshotMax()
    {
        lock (_lock)
        {
            return (_maxX, _maxY);
        }
    }

    public void ConfigurePressureHint(bool likelyUnsupported)
    {
        lock (_lock)
        {
            _pressureHintUnsupported = likelyUnsupported;
            ResetPressureProbeCore();
            _pressureCapability = likelyUnsupported ? PressureCapability.Unsupported : PressureCapability.Unknown;
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

                byte rawPressure = c.Pressure8;
                byte rawPressure6 = (byte)(rawPressure >> 2);
                byte rawPhase = c.Phase8;
                ObservePressureSampleCore(rawPressure6);
                byte pressure = _pressureCapability == PressureCapability.Supported ? rawPressure : (byte)0;

                _contacts[_contactCount++] = new TouchContact(c.Id, c.X, c.Y, c.TipSwitch, c.Confidence, pressure, rawPhase);
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
            _pressureHintUnsupported = false;
            _pressureCapability = PressureCapability.Unknown;
            ResetPressureProbeCore();
        }
    }

    private void SnapshotStateCore(Span<TouchContact> destination, out ushort maxX, out ushort maxY, out PressureCapability pressureCapability, out int count)
    {
        lock (_lock)
        {
            if (_contactCount > 0 &&
                _lastFrameTicks > 0 &&
                Stopwatch.GetTimestamp() - _lastFrameTicks > _stateStaleTicks)
            {
                _contactCount = 0;
            }

            count = _contactCount <= destination.Length ? _contactCount : destination.Length;
            _contacts.AsSpan(0, count).CopyTo(destination);
            maxX = _maxX;
            maxY = _maxY;
            pressureCapability = _pressureCapability;
        }
    }

    private void ObservePressureSampleCore(byte pressure6)
    {
        if (_pressureCapability != PressureCapability.Unknown)
        {
            return;
        }

        if (_pressureHintUnsupported)
        {
            _pressureCapability = PressureCapability.Unsupported;
            return;
        }

        _pressureSampleCount++;
        if (pressure6 != 0)
        {
            _pressureNonZeroCount++;
        }

        if (_pressureHasLastSample)
        {
            _pressureComparedCount++;
            int delta = pressure6 >= _pressureLastSample
                ? pressure6 - _pressureLastSample
                : _pressureLastSample - pressure6;
            if (delta >= PressureLargeJumpThreshold)
            {
                _pressureLargeJumpCount++;
            }
        }

        _pressureLastSample = pressure6;
        _pressureHasLastSample = true;

        if (_pressureSampleCount >= PressureEarlyDecisionSamples &&
            _pressureComparedCount >= 12 &&
            _pressureNonZeroCount >= 8)
        {
            int jumpPercent = (_pressureLargeJumpCount * 100) / _pressureComparedCount;
            if (jumpPercent <= 35)
            {
                _pressureCapability = PressureCapability.Supported;
                return;
            }

            if (jumpPercent >= 85)
            {
                _pressureCapability = PressureCapability.Unsupported;
                return;
            }
        }

        if (_pressureSampleCount >= PressureDecisionSamples)
        {
            if (_pressureNonZeroCount == 0)
            {
                _pressureCapability = PressureCapability.Unsupported;
                return;
            }

            if (_pressureComparedCount >= 20)
            {
                int jumpPercent = (_pressureLargeJumpCount * 100) / _pressureComparedCount;
                if (jumpPercent >= 70)
                {
                    _pressureCapability = PressureCapability.Unsupported;
                    return;
                }

                if (jumpPercent <= 50 && _pressureNonZeroCount >= 10)
                {
                    _pressureCapability = PressureCapability.Supported;
                    return;
                }
            }
        }

        if (_pressureSampleCount >= PressureMaxProbeSamples)
        {
            if (_pressureComparedCount < 20 || _pressureNonZeroCount < 20)
            {
                _pressureCapability = PressureCapability.Unsupported;
                return;
            }

            int jumpPercent = (_pressureLargeJumpCount * 100) / _pressureComparedCount;
            _pressureCapability = jumpPercent <= 45
                ? PressureCapability.Supported
                : PressureCapability.Unsupported;
        }
    }

    private void ResetPressureProbeCore()
    {
        _pressureSampleCount = 0;
        _pressureNonZeroCount = 0;
        _pressureComparedCount = 0;
        _pressureLargeJumpCount = 0;
        _pressureHasLastSample = false;
        _pressureLastSample = 0;
        if (_pressureHintUnsupported)
        {
            _pressureCapability = PressureCapability.Unsupported;
        }
    }
}

public readonly record struct TouchContact(uint Id, ushort X, ushort Y, bool Tip, bool Confidence, byte Pressure, byte Phase)
{
    public byte Pressure8 => Pressure;
    public byte Pressure6 => (byte)(Pressure >> 2);
    public byte PressureApprox => (byte)(Pressure6 << 2);
}
