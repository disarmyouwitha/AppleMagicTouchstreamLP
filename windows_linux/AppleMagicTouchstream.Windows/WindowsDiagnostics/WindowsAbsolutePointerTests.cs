namespace AppleMagicTouchstream;

internal static class WindowsAbsolutePointerTests
{
    internal static void Run()
    {
        // Exercise every destination, especially single-pixel moves on the left
        // half of a display where endpoint interpolation can round down a pixel.
        foreach (int extent in new[] { 2, 1080, 1440, 1920, 2560, 3440, 3840, 5120, 7680, 15360 })
        foreach (int origin in new[] { 0, -3840, 1920 })
        {
            for (int offset=0; offset<extent; offset++)
            {
                int normalized=WindowsAbsolutePointer.Normalize(origin+offset,origin,extent);
                int actual=(int)((long)normalized*extent/65536);
                if (actual!=offset)
                    throw new InvalidOperationException($"Absolute pointer missed pixel {offset} at origin {origin}, extent {extent}: {actual}");
            }
            if (WindowsAbsolutePointer.Normalize(origin-1,origin,extent)!=WindowsAbsolutePointer.Normalize(origin,origin,extent)
                || WindowsAbsolutePointer.Normalize(origin+extent,origin,extent)!=WindowsAbsolutePointer.Normalize(origin+extent-1,origin,extent))
                throw new InvalidOperationException("Absolute pointer did not clamp to display bounds");
        }
    }
}
