using System.Text.Json;
namespace AppleMagicTouchstream;

internal static class MacLayoutTemplates
{
    private static readonly Lazy<Dictionary<string,LayoutDocument>> Saved=new(()=>
    {
        using var stream=typeof(MacLayoutTemplates).Assembly.GetManifestResourceStream("AppleMagicTouchstream.MacLayoutTemplates.json")!;
        return JsonSerializer.Deserialize<Dictionary<string,LayoutDocument>>(stream,LayoutDocument.JsonOptions)!;
    });
    private sealed record TemplateDefaults(UserSettings Settings,Dictionary<string,Dictionary<string,string>> Labels);
    private static readonly Lazy<TemplateDefaults> Defaults=new(()=>
    {
        using var stream=typeof(MacLayoutTemplates).Assembly.GetManifestResourceStream("AppleMagicTouchstream.MacTemplateSettings.json")!;
        return JsonSerializer.Deserialize<TemplateDefaults>(stream,LayoutDocument.JsonOptions)!;
    });
    internal static LayoutDocument Get(TrackpadLayoutPreset preset)
    {
        if(Saved.Value.TryGetValue(preset.Name,out var document) && document.IsValid()) return document.Copy();
        var settings=Defaults.Value.Settings;
        var columns=RuntimeConfigurationFactory.BuildColumnSettingsForPreset(settings,preset);
        double spacing=RuntimeConfigurationFactory.GetKeyPaddingPercentForPreset(settings,preset);
        var value=LayoutDocument.Seed(LayoutBuilder.BuildLayout(preset,160,114.9,18,17,columns,true,spacing),LayoutBuilder.BuildLayout(preset,160,114.9,18,17,columns,false,spacing));
        if(!preset.IsSteno && Defaults.Value.Labels.TryGetValue(preset.Name,out var labels))foreach(var key in value.Keys)
            if(labels.TryGetValue(GridKeyPosition.StorageKey(key.Right ? TrackpadSide.Right:TrackpadSide.Left,key.Row,key.Column),out var label))key.Label=label;
        return value;
    }
    internal static void Seed(UserSettings settings)
    {
        settings.LayoutDocuments ??=new(StringComparer.OrdinalIgnoreCase);
        foreach(var preset in WindowsInputPolicy.SelectableLayouts)
            if(!settings.LayoutDocuments.TryGetValue(preset.Name,out var document) || !document.IsValid()) settings.LayoutDocuments[preset.Name]=Get(preset);
    }
}
