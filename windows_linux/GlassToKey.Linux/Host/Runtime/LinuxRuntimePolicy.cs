namespace GlassToKey.Linux.Runtime;

public enum LinuxRuntimePolicy
{
    DesktopInteractive = 0,
    HeadlessPureKeyboard = 1
}

public static class LinuxRuntimePolicyExtensions
{
    public static bool AllowsAutomaticBindingSelection(this LinuxRuntimePolicy policy)
    {
        return policy == LinuxRuntimePolicy.HeadlessPureKeyboard;
    }

    public static bool AllowsAutomaticBindingSelection(this LinuxRuntimePolicy policy, bool hasSavedBindings)
    {
        return policy == LinuxRuntimePolicy.HeadlessPureKeyboard && !hasSavedBindings;
    }

    public static bool IgnoresTypingToggleActions(this LinuxRuntimePolicy policy)
    {
        return policy == LinuxRuntimePolicy.HeadlessPureKeyboard;
    }

    public static UserSettings ApplyToProfile(this LinuxRuntimePolicy policy, UserSettings profile)
    {
        ArgumentNullException.ThrowIfNull(profile);

        UserSettings effective = profile.Clone();
        if (policy == LinuxRuntimePolicy.HeadlessPureKeyboard)
        {
            effective.KeyboardModeEnabled = true;
            effective.TypingEnabled = true;
            effective.ThreeFingerDragEnabled = false;
        }

        effective.NormalizeRanges();
        return effective;
    }
}
