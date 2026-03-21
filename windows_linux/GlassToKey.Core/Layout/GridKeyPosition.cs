using System;

namespace GlassToKey;

public enum TrackpadSide
{
    Left,
    Right
}

public static class GridKeyPosition
{
    public static string StorageKey(TrackpadSide side, int row, int column)
    {
        string s = side == TrackpadSide.Left ? "left" : "right";
        return $"{s}:{row}:{column}";
    }
}
