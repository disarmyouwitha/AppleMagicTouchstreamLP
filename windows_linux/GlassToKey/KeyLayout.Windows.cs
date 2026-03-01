using System.Windows;

namespace GlassToKey;

public readonly partial record struct NormalizedRect
{
    public Rect ToRect(Rect bounds)
    {
        return new Rect(
            bounds.Left + X * bounds.Width,
            bounds.Top + Y * bounds.Height,
            Width * bounds.Width,
            Height * bounds.Height);
    }

    public Rect ToBoundsRect(Rect bounds)
    {
        if (Math.Abs(RotationDegrees) < 0.00001)
        {
            return ToRect(bounds);
        }

        GeometryPoint[] points = GetCorners();
        double minX = double.PositiveInfinity;
        double maxX = double.NegativeInfinity;
        double minY = double.PositiveInfinity;
        double maxY = double.NegativeInfinity;
        for (int i = 0; i < points.Length; i++)
        {
            GeometryPoint point = points[i];
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
