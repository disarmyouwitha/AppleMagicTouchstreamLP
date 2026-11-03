namespace AppleMagicTouchstream;

internal static class WindowsAbsolutePointer
{
    // SendInput divides the normalized [0,65536) range into display pixels.
    // Aim at each pixel's centre: endpoint interpolation can land just before
    // a pixel boundary, losing a one-pixel move when the next move reads it back.
    internal static int Normalize(int pixel, int origin, int extent)
    {
        if (extent < 2) throw new ArgumentOutOfRangeException(nameof(extent));
        double offset = Math.Clamp((double)pixel-origin, 0, extent-1);
        return Math.Clamp((int)((offset+.5)*65536/extent), 0, 65535);
    }
}
