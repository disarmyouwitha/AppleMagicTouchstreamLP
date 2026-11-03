using System.Text.Json;

namespace AppleMagicTouchstream;

// Loaded/validated once on the configuration path. No registry, disk or JSON work
// occurs while contacts are processed. This resource contains no hardware IDs.
internal static class CapturedMacMotionProfiles
{
    internal sealed record Device
    {
        public string Side { get; init; } = "";
        public ApplePointerProfile Pointer { get; init; } = new();
        public AppleScrollProfile Scroll { get; init; } = new();
        public double PointerSensitivity { get; init; } = 1;
        public double ScrollSensitivity { get; init; } = 1;
    }
    private static readonly Lazy<Device[]> Profiles=new(Load);
    private static Device[] Load()
    {
        using var stream=typeof(CapturedMacMotionProfiles).Assembly.GetManifestResourceStream("AppleMagicTouchstream.mac-motion.json")
            ?? throw new InvalidOperationException("Bundled Mac motion profile is missing.");
        using var json=JsonDocument.Parse(stream);
        if(json.RootElement.GetProperty("schema").GetString()!="amt.mac-motion.v1") throw new ArgumentException("Invalid bundled Mac motion schema.");
        var devices=json.RootElement.GetProperty("devices").Deserialize<Device[]>(new JsonSerializerOptions { PropertyNameCaseInsensitive=true }) ?? [];
        if(devices.Length!=2 || devices.Count(d=>d.Side=="left")!=1 || devices.Count(d=>d.Side=="right")!=1) throw new ArgumentException("Expected independent Left and Right Mac profiles.");
        foreach(var d in devices)
        {
            _=new ApplePointerAccelerator(d.Pointer); _=new AppleScrollAccelerator(d.Scroll);
            if(!double.IsFinite(d.PointerSensitivity) || d.PointerSensitivity is <.25 or >2 || !double.IsFinite(d.ScrollSensitivity) || d.ScrollSensitivity is <.25 or >2)
                throw new ArgumentException("Invalid captured Mac sensitivity.");
        }
        return devices;
    }
    internal static Device For(TrackpadSide side)=>Profiles.Value.Single(d=>d.Side==(side==TrackpadSide.Left ? "left" : "right"));
    internal static HandGestureSettings Effective(HandGestureSettings settings)
    {
        var effective=settings.Clone();
        foreach(var side in new[] { TrackpadSide.Left,TrackpadSide.Right })
        {
            var hand=side==TrackpadSide.Left ? effective.Left : effective.Right;
            // Windows uses the captured response for both hands, retaining
            // per-hand sensitivity and scrolling direction.
            var profile=For(side);
            hand.PointerResponse=HandPointerResponse.ImportedApple;
            hand.ImportedPointerProfile=profile.Pointer.Copy();
            hand.ImportedScrollProfile=profile.Scroll.Copy();
        }
        return effective;
    }
}
