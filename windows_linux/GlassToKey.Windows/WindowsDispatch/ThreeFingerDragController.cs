using System;
using System.Diagnostics;

namespace GlassToKey;

internal interface IThreeFingerDragSink
{
    void MovePointerBy(int deltaX, int deltaY);
    void NotifyPointerActivity();
    void SetLeftButtonState(bool pressed);
}

internal sealed class ThreeFingerDragController
{
    private const double ActivationMoveMm = 1.5;
    private const double PixelsPerMm = 10.0;
    private static readonly long ActivationHoldTicks = MsToTicks(80.0);

    private readonly IThreeFingerDragSink _sink;
    private TrackpadSide _ownerSide;
    private bool _enabled;
    private bool _candidate;
    private bool _dragActive;
    private long _candidateStartedTicks;
    private double _anchorCentroidXMm;
    private double _anchorCentroidYMm;
    private double _lastCentroidXMm;
    private double _lastCentroidYMm;
    private double _pendingPixelsX;
    private double _pendingPixelsY;

    public ThreeFingerDragController(IThreeFingerDragSink sink)
    {
        _sink = sink ?? throw new ArgumentNullException(nameof(sink));
    }

    public void SetEnabled(bool enabled)
    {
        if (_enabled == enabled)
        {
            return;
        }

        _enabled = enabled;
        if (!enabled)
        {
            Reset(releaseButton: true);
        }
    }

    public bool ProcessFrame(TrackpadSide side, in InputFrame frame, ushort maxX, ushort maxY, long timestampTicks)
    {
        if (!_enabled)
        {
            return false;
        }

        if (!TryGetThreeFingerCentroid(in frame, maxX, maxY, out double centroidXMm, out double centroidYMm))
        {
            if (_candidate && side == _ownerSide)
            {
                Reset(releaseButton: true);
                return true;
            }

            return false;
        }

        if (_candidate && side != _ownerSide)
        {
            return false;
        }

        if (!_candidate)
        {
            BeginCandidate(side, timestampTicks, centroidXMm, centroidYMm);
            return true;
        }

        double deltaFromAnchorX = centroidXMm - _anchorCentroidXMm;
        double deltaFromAnchorY = centroidYMm - _anchorCentroidYMm;
        double distanceSq = (deltaFromAnchorX * deltaFromAnchorX) + (deltaFromAnchorY * deltaFromAnchorY);
        bool activateByMove = distanceSq >= (ActivationMoveMm * ActivationMoveMm);
        bool activateByHold = !activateByMove && (timestampTicks - _candidateStartedTicks) >= ActivationHoldTicks;

        if (!_dragActive && (activateByMove || activateByHold))
        {
            _dragActive = true;
            _sink.SetLeftButtonState(true);
            _sink.NotifyPointerActivity();

            if (!activateByMove)
            {
                _lastCentroidXMm = centroidXMm;
                _lastCentroidYMm = centroidYMm;
            }
        }

        if (_dragActive)
        {
            EmitMovement(centroidXMm - _lastCentroidXMm, centroidYMm - _lastCentroidYMm);
            _lastCentroidXMm = centroidXMm;
            _lastCentroidYMm = centroidYMm;
        }

        return true;
    }

    private void BeginCandidate(TrackpadSide side, long timestampTicks, double centroidXMm, double centroidYMm)
    {
        _ownerSide = side;
        _candidate = true;
        _dragActive = false;
        _candidateStartedTicks = timestampTicks;
        _anchorCentroidXMm = centroidXMm;
        _anchorCentroidYMm = centroidYMm;
        _lastCentroidXMm = centroidXMm;
        _lastCentroidYMm = centroidYMm;
        _pendingPixelsX = 0.0;
        _pendingPixelsY = 0.0;
    }

    private void EmitMovement(double deltaXMm, double deltaYMm)
    {
        _pendingPixelsX += deltaXMm * PixelsPerMm;
        _pendingPixelsY += deltaYMm * PixelsPerMm;

        int deltaXPixels = (int)_pendingPixelsX;
        int deltaYPixels = (int)_pendingPixelsY;
        if (deltaXPixels == 0 && deltaYPixels == 0)
        {
            return;
        }

        _pendingPixelsX -= deltaXPixels;
        _pendingPixelsY -= deltaYPixels;
        _sink.MovePointerBy(deltaXPixels, deltaYPixels);
        _sink.NotifyPointerActivity();
    }

    private void Reset(bool releaseButton)
    {
        if (releaseButton && _dragActive)
        {
            _sink.SetLeftButtonState(false);
            _sink.NotifyPointerActivity();
        }

        _candidate = false;
        _dragActive = false;
        _candidateStartedTicks = 0;
        _anchorCentroidXMm = 0.0;
        _anchorCentroidYMm = 0.0;
        _lastCentroidXMm = 0.0;
        _lastCentroidYMm = 0.0;
        _pendingPixelsX = 0.0;
        _pendingPixelsY = 0.0;
    }

    private static bool TryGetThreeFingerCentroid(in InputFrame frame, ushort maxX, ushort maxY, out double centroidXMm, out double centroidYMm)
    {
        centroidXMm = 0.0;
        centroidYMm = 0.0;

        double sumX = 0.0;
        double sumY = 0.0;
        int tipCount = 0;
        int count = frame.GetClampedContactCount();
        for (int i = 0; i < count; i++)
        {
            ContactFrame contact = frame.GetContact(i);
            if (!contact.TipSwitch)
            {
                continue;
            }

            sumX += contact.X;
            sumY += contact.Y;
            tipCount++;
        }

        if (tipCount != 3)
        {
            return false;
        }

        double scaledMaxX = maxX == 0 ? 1.0 : maxX;
        double scaledMaxY = maxY == 0 ? 1.0 : maxY;
        centroidXMm = ((sumX / tipCount) / scaledMaxX) * RuntimeConfigurationFactory.TrackpadWidthMm;
        centroidYMm = ((sumY / tipCount) / scaledMaxY) * RuntimeConfigurationFactory.TrackpadHeightMm;
        return true;
    }

    private static long MsToTicks(double milliseconds)
    {
        if (milliseconds <= 0)
        {
            return 0;
        }

        return (long)Math.Round(milliseconds * Stopwatch.Frequency / 1000.0);
    }
}
