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
    public bool Contains(double x, double y)
    {
        return x >= X && x <= X + Width && y >= Y && y <= Y + Height;
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
}
