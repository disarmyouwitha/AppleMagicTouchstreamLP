namespace GlassToKey;

internal static class WindowsInputPolicy
{
    // Retained fields belong to the shared Linux/profile format. Windows ignores
    // the removed mode and exports neutral values when old profiles are loaded.
    internal static void NormalizeLegacyModes(UserSettings settings)
    {
        settings.KeyboardModeEnabled = false;
        settings.TypingEnabled = true;
        settings.HandGesturesV1 ??= new();
        settings.HandGesturesV1.Normalize();
        settings.HandGesturesV1.Left.PointerResponse = settings.HandGesturesV1.Right.PointerResponse = HandPointerResponse.AppleReference;
    }
}
