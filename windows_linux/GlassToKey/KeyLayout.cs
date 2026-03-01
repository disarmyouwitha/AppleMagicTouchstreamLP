using System;

namespace GlassToKey;

public sealed class KeyLayout
{
    public KeyLayout(NormalizedRect[][] rects, string[][] labels)
    {
        Rects = rects;
        Labels = labels;
        HitGeometries = BuildHitGeometries(rects);
    }

    public NormalizedRect[][] Rects { get; }
    public string[][] Labels { get; }
    public KeyHitGeometry[][] HitGeometries { get; }

    private static KeyHitGeometry[][] BuildHitGeometries(NormalizedRect[][] rects)
    {
        KeyHitGeometry[][] geometries = new KeyHitGeometry[rects.Length][];
        for (int row = 0; row < rects.Length; row++)
        {
            NormalizedRect[] rowRects = rects[row];
            geometries[row] = new KeyHitGeometry[rowRects.Length];
            for (int col = 0; col < rowRects.Length; col++)
            {
                geometries[row][col] = KeyHitGeometry.FromRect(rowRects[col]);
            }
        }

        return geometries;
    }
}

public readonly record struct KeyHitGeometry(
    double CenterX,
    double CenterY,
    double HalfWidth,
    double HalfHeight,
    double Cos,
    double Sin,
    double MinX,
    double MaxX,
    double MinY,
    double MaxY,
    double Area,
    bool IsRotated)
{
    public static KeyHitGeometry FromRect(NormalizedRect rect)
    {
        double centerX = rect.CenterX;
        double centerY = rect.CenterY;
        double halfWidth = rect.Width * 0.5;
        double halfHeight = rect.Height * 0.5;
        double area = rect.Width * rect.Height;
        bool isRotated = Math.Abs(rect.RotationDegrees) >= 0.00001;

        if (!isRotated)
        {
            return new KeyHitGeometry(
                centerX,
                centerY,
                halfWidth,
                halfHeight,
                Cos: 1.0,
                Sin: 0.0,
                MinX: rect.X,
                MaxX: rect.X + rect.Width,
                MinY: rect.Y,
                MaxY: rect.Y + rect.Height,
                Area: area,
                IsRotated: false);
        }

        double radians = -(rect.RotationDegrees * Math.PI / 180.0);
        double cos = Math.Cos(radians);
        double sin = Math.Sin(radians);

        GeometryPoint[] corners =
        {
            RotateCorner(-halfWidth, -halfHeight, centerX, centerY, cos, -sin),
            RotateCorner(halfWidth, -halfHeight, centerX, centerY, cos, -sin),
            RotateCorner(halfWidth, halfHeight, centerX, centerY, cos, -sin),
            RotateCorner(-halfWidth, halfHeight, centerX, centerY, cos, -sin)
        };

        double minX = double.PositiveInfinity;
        double maxX = double.NegativeInfinity;
        double minY = double.PositiveInfinity;
        double maxY = double.NegativeInfinity;
        for (int i = 0; i < corners.Length; i++)
        {
            GeometryPoint point = corners[i];
            minX = Math.Min(minX, point.X);
            maxX = Math.Max(maxX, point.X);
            minY = Math.Min(minY, point.Y);
            maxY = Math.Max(maxY, point.Y);
        }

        return new KeyHitGeometry(centerX, centerY, halfWidth, halfHeight, cos, sin, minX, maxX, minY, maxY, area, true);
    }

    public bool Contains(double x, double y)
    {
        (double localX, double localY) = ToLocal(x, y);
        return Math.Abs(localX) <= HalfWidth && Math.Abs(localY) <= HalfHeight;
    }

    public double DistanceToEdge(double x, double y)
    {
        (double localX, double localY) = ToLocal(x, y);
        double dx = HalfWidth - Math.Abs(localX);
        double dy = HalfHeight - Math.Abs(localY);
        return Math.Min(dx, dy);
    }

    private (double X, double Y) ToLocal(double x, double y)
    {
        double translatedX = x - CenterX;
        double translatedY = y - CenterY;
        if (!IsRotated)
        {
            return (translatedX, translatedY);
        }

        return (
            (translatedX * Cos) - (translatedY * Sin),
            (translatedX * Sin) + (translatedY * Cos));
    }

    private static GeometryPoint RotateCorner(double localX, double localY, double centerX, double centerY, double cos, double sin)
    {
        return new(
            centerX + (localX * cos) - (localY * sin),
            centerY + (localX * sin) + (localY * cos));
    }
}

internal readonly record struct GeometryPoint(double X, double Y);

public readonly partial record struct NormalizedRect(double X, double Y, double Width, double Height)
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

    private GeometryPoint[] GetCorners()
    {
        double halfWidth = Width * 0.5;
        double halfHeight = Height * 0.5;
        GeometryPoint[] corners =
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
            corners[i] = new GeometryPoint(
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

        GeometryPoint[] points = GetCorners();
        minX = double.PositiveInfinity;
        maxX = double.NegativeInfinity;
        minY = double.PositiveInfinity;
        maxY = double.NegativeInfinity;
        for (int i = 0; i < points.Length; i++)
        {
            GeometryPoint point = points[i];
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
