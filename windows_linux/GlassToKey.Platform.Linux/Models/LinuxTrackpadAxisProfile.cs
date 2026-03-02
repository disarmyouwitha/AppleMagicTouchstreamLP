namespace GlassToKey.Platform.Linux.Models;

public sealed record LinuxTrackpadAxisProfile(
    LinuxInputAxisInfo? Slot,
    LinuxInputAxisInfo? X,
    LinuxInputAxisInfo? Y,
    LinuxInputAxisInfo? Pressure,
    bool UsesMtPositionAxes,
    bool UsesLegacyPositionAxes)
{
    public int SlotCount => Slot == null ? 1 : Math.Max(1, Slot.Maximum - Slot.Minimum + 1);

    public int MinX => GetAxis(X, nameof(X)).Minimum;

    public int MinY => GetAxis(Y, nameof(Y)).Minimum;

    public ushort MaxX => GetAxisSpan(X, nameof(X));

    public ushort MaxY => GetAxisSpan(Y, nameof(Y));

    public ushort NormalizeX(int rawValue)
    {
        return Normalize(rawValue, GetAxis(X, nameof(X)));
    }

    public ushort NormalizeY(int rawValue)
    {
        return Normalize(rawValue, GetAxis(Y, nameof(Y)));
    }

    private static LinuxInputAxisInfo GetAxis(LinuxInputAxisInfo? axis, string axisName)
    {
        if (axis == null)
        {
            throw new InvalidOperationException($"Axis metadata for '{axisName}' is unavailable.");
        }

        return axis;
    }

    private static ushort GetAxisSpan(LinuxInputAxisInfo? axis, string axisName)
    {
        LinuxInputAxisInfo requiredAxis = GetAxis(axis, axisName);
        int span = requiredAxis.Maximum - requiredAxis.Minimum;
        if (span <= 0)
        {
            throw new InvalidOperationException($"Axis metadata for '{axisName}' has an invalid span.");
        }

        return (ushort)Math.Min(span, ushort.MaxValue);
    }

    private static ushort Normalize(int rawValue, LinuxInputAxisInfo axis)
    {
        int span = axis.Maximum - axis.Minimum;
        if (span <= 0)
        {
            return 0;
        }

        int shifted = rawValue - axis.Minimum;
        return (ushort)Math.Clamp(shifted, 0, span);
    }
}
