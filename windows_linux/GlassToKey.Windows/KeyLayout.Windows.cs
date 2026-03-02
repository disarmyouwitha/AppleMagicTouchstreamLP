using System.Windows;

namespace GlassToKey;

public static class KeyLayoutWindowsExtensions
{
    public static Rect ToRect(this NormalizedRect rect, Rect bounds)
    {
        return new Rect(
            bounds.Left + rect.X * bounds.Width,
            bounds.Top + rect.Y * bounds.Height,
            rect.Width * bounds.Width,
            rect.Height * bounds.Height);
    }

    public static Rect ToBoundsRect(this NormalizedRect rect, Rect bounds)
    {
        if (Math.Abs(rect.RotationDegrees) < 0.00001)
        {
            return rect.ToRect(bounds);
        }

        var points = rect.GetCorners();
        double minX = double.PositiveInfinity;
        double maxX = double.NegativeInfinity;
        double minY = double.PositiveInfinity;
        double maxY = double.NegativeInfinity;
        for (int i = 0; i < points.Length; i++)
        {
            var point = points[i];
            minX = Math.Min(minX, point.X);
            maxX = Math.Max(maxX, point.X);
            minY = Math.Min(minY, point.Y);
            maxY = Math.Max(maxY, point.Y);
        }

        return new Rect(
            bounds.Left + minX * bounds.Width,
            bounds.Top + minY * bounds.Height,
            (maxX - minX) * bounds.Width,
            (maxY - minY) * bounds.Height);
    }
}
