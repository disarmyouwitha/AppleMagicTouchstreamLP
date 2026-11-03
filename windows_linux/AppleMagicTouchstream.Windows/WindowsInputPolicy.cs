namespace AppleMagicTouchstream;

internal static class WindowsInputPolicy
{
    internal static TrackpadLayoutPreset[] SelectableLayouts { get; }=[..TrackpadLayoutPreset.Selectable.Where(p=>p!=TrackpadLayoutPreset.FiveByThree && p!=TrackpadLayoutPreset.FiveByFour),TrackpadLayoutPreset.Steno,TrackpadLayoutPreset.StenoVoyager,TrackpadLayoutPreset.StenoSingle];
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
        if(TrackpadLayoutPreset.ResolveByNameOrDefault(settings.LayoutPresetName).IsSteno)settings.StenoLayoutVariantName=TrackpadLayoutPreset.ResolveByNameOrDefault(settings.LayoutPresetName).Name;
        if(!TrackpadLayoutPreset.ResolveByNameOrDefault(settings.StenoLayoutVariantName).IsSteno)settings.StenoLayoutVariantName="STENO";
        if(settings.StenoConnectionMode is not ("javelin" or "javelinPlover" or "plugin"))settings.StenoConnectionMode="javelin";
        MacLayoutTemplates.Seed(settings);
        settings.HandGesturesV1.Left.PointerResponse = settings.HandGesturesV1.Right.PointerResponse = HandPointerResponse.AppleReference;
    }
}
