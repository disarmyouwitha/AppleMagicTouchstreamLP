namespace GlassToKey;

internal static class WindowsInputPolicy
{
    internal static TouchProcessorConfig BuildTouchConfig(UserSettings settings)=>RuntimeConfigurationFactory.BuildTouchConfig(settings) with
    { SnapRadiusPercent=double.IsFinite(settings.SnapRadiusPercent) ? Math.Clamp(settings.SnapRadiusPercent,0,100) : 0 };
    // Retained fields belong to the shared Linux/profile format. Windows ignores
    // the removed mode and exports neutral values when old profiles are loaded.
    internal static void NormalizeLegacyModes(UserSettings settings)
    {
        settings.KeyboardModeEnabled = false;
        settings.TypingEnabled = true;
        // Mac's keyboard has per-key Force instead of global typing pressure gates.
        settings.ForceMin = 0;
        settings.ForceCap = 255;
        settings.HandGesturesV1 ??= new();
        settings.HandGesturesV1.Normalize();
        settings.HandGesturesV1.Left.PointerResponse = settings.HandGesturesV1.Right.PointerResponse = HandPointerResponse.AppleReference;
    }
}
