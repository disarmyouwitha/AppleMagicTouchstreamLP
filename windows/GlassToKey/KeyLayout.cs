using System;
using System.Windows;

namespace GlassToKey;

public sealed class KeyLayout
{
    public KeyLayout(NormalizedRect[][] rects, string[][] labels)
    {
        Rects = rects;
        Labels = labels;
    }

    public NormalizedRect[][] Rects { get; }
    public string[][] Labels { get; }
}

public readonly record struct NormalizedRect(double X, double Y, double Width, double Height)
{
    public double CenterX => X + (Width * 0.5);
    public double CenterY => Y + (Height * 0.5);
    public double RotationDegrees { get; init; }

    public bool Contains(double x, double y)
    {
        if (Math.Abs(RotationDegrees) < 0.00001)
        {
            return x >= X && x <= X + Width && y >= Y && y <= Y + Height;
        }

        double radians = -(RotationDegrees * Math.PI / 180.0);
        double cos = Math.Cos(radians);
        double sin = Math.Sin(radians);
        double localX = x - CenterX;
        double localY = y - CenterY;
        double rotatedX = (localX * cos) - (localY * sin);
        double rotatedY = (localX * sin) + (localY * cos);
        return Math.Abs(rotatedX) <= Width * 0.5 && Math.Abs(rotatedY) <= Height * 0.5;
    }

    public Rect ToRect(Rect bounds)
    {
        return new Rect(
            bounds.Left + X * bounds.Width,
            bounds.Top + Y * bounds.Height,
            Width * bounds.Width,
            Height * bounds.Height
        );
    }

    public Rect ToBoundsRect(Rect bounds)
    {
        if (Math.Abs(RotationDegrees) < 0.00001)
        {
            return ToRect(bounds);
        }

        Point[] points = GetCorners();
        double minX = double.PositiveInfinity;
        double maxX = double.NegativeInfinity;
        double minY = double.PositiveInfinity;
        double maxY = double.NegativeInfinity;
        for (int i = 0; i < points.Length; i++)
        {
            Point point = points[i];
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

    public NormalizedRect RotateAround(double pivotX, double pivotY, double rotationDegrees)
    {
        if (Math.Abs(rotationDegrees) < 0.00001)
        {
            return this;
        }

        double radians = rotationDegrees * Math.PI / 180.0;
        double cos = Math.Cos(radians);
        double sin = Math.Sin(radians);
        double localX = CenterX - pivotX;
        double localY = CenterY - pivotY;
        double rotatedCenterX = pivotX + (localX * cos) - (localY * sin);
        double rotatedCenterY = pivotY + (localX * sin) + (localY * cos);
        return this with
        {
            X = rotatedCenterX - (Width * 0.5),
            Y = rotatedCenterY - (Height * 0.5),
            RotationDegrees = NormalizeDegrees(RotationDegrees + rotationDegrees)
        };
    }

    public NormalizedRect MirrorHorizontally()
    {
        return this with
        {
            X = 1.0 - X - Width,
            RotationDegrees = NormalizeDegrees(-RotationDegrees)
        };
    }

    public double DistanceToEdge(double x, double y)
    {
        double radians = -(RotationDegrees * Math.PI / 180.0);
        double cos = Math.Cos(radians);
        double sin = Math.Sin(radians);
        double localX = x - CenterX;
        double localY = y - CenterY;
        double rotatedX = (localX * cos) - (localY * sin);
        double rotatedY = (localX * sin) + (localY * cos);
        double dx = (Width * 0.5) - Math.Abs(rotatedX);
        double dy = (Height * 0.5) - Math.Abs(rotatedY);
        return Math.Min(dx, dy);
    }

    public double Area => Width * Height;

    public double MinX
    {
        get
        {
            GetBounds(out double minX, out _, out _, out _);
            return minX;
        }
    }

    public double MaxX
    {
        get
        {
            GetBounds(out _, out double maxX, out _, out _);
            return maxX;
        }
    }

    public double MinY
    {
        get
        {
            GetBounds(out _, out _, out double minY, out _);
            return minY;
        }
    }

    public double MaxY
    {
        get
        {
            GetBounds(out _, out _, out _, out double maxY);
            return maxY;
        }
    }

    private Point[] GetCorners()
    {
        double halfWidth = Width * 0.5;
        double halfHeight = Height * 0.5;
        Point[] corners =
        {
            new(CenterX - halfWidth, CenterY - halfHeight),
            new(CenterX + halfWidth, CenterY - halfHeight),
            new(CenterX + halfWidth, CenterY + halfHeight),
            new(CenterX - halfWidth, CenterY + halfHeight)
        };

        if (Math.Abs(RotationDegrees) < 0.00001)
        {
            return corners;
        }

        double radians = RotationDegrees * Math.PI / 180.0;
        double cos = Math.Cos(radians);
        double sin = Math.Sin(radians);
        for (int i = 0; i < corners.Length; i++)
        {
            double localX = corners[i].X - CenterX;
            double localY = corners[i].Y - CenterY;
            corners[i] = new Point(
                CenterX + (localX * cos) - (localY * sin),
                CenterY + (localX * sin) + (localY * cos));
        }

        return corners;
    }

    private void GetBounds(out double minX, out double maxX, out double minY, out double maxY)
    {
        if (Math.Abs(RotationDegrees) < 0.00001)
        {
            minX = X;
            maxX = X + Width;
            minY = Y;
            maxY = Y + Height;
            return;
        }

        Point[] points = GetCorners();
        minX = double.PositiveInfinity;
        maxX = double.NegativeInfinity;
        minY = double.PositiveInfinity;
        maxY = double.NegativeInfinity;
        for (int i = 0; i < points.Length; i++)
        {
            Point point = points[i];
            minX = Math.Min(minX, point.X);
            maxX = Math.Max(maxX, point.X);
            minY = Math.Min(minY, point.Y);
            maxY = Math.Max(maxY, point.Y);
        }
    }

    private static double NormalizeDegrees(double value)
    {
        double normalized = value % 360.0;
        if (normalized <= -180.0)
        {
            normalized += 360.0;
        }
        else if (normalized > 180.0)
        {
            normalized -= 360.0;
        }

        return normalized;
    }
}
