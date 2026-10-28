using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Runtime;

internal static class LinuxRuntimeConfigurationComparer
{
    public static bool HaveEquivalentBindings(
        IReadOnlyList<LinuxTrackpadBinding> left,
        IReadOnlyList<LinuxTrackpadBinding> right)
    {
        if (ReferenceEquals(left, right))
        {
            return true;
        }

        if (left.Count != right.Count)
        {
            return false;
        }

        for (int index = 0; index < left.Count; index++)
        {
            LinuxTrackpadBinding candidate = left[index];
            bool matched = false;
            for (int otherIndex = 0; otherIndex < right.Count; otherIndex++)
            {
                LinuxTrackpadBinding other = right[otherIndex];
                if (candidate.Side != other.Side)
                {
                    continue;
                }

                if (!string.Equals(candidate.Device.StableId, other.Device.StableId, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                matched = true;
                break;
            }

            if (!matched)
            {
                return false;
            }
        }

        return true;
    }
}
