using System.IO;
namespace AppleMagicTouchstream;

// Additive profile companion preserves the existing ATPCAP byte format. Secrets
// stay in the host vault: this file contains only their opaque action references.
public static class CaptureProfileSidecar
{
    public static string PathFor(string capture)=>capture+".settings.json";
    public static void Write(string capture,UserSettings settings,KeymapStore keymap)
    {File.WriteAllText(PathFor(capture),AppleMagicTouchstreamProfileBundle.Create(settings,keymap).SerializeToJson());}
    public static bool TryRead(string capture,out UserSettings settings,out KeymapStore map)
    {
        settings=new();map=KeymapStore.LoadBundledDefault();string path=PathFor(capture);
        if(!File.Exists(path))return false;
        if(new FileInfo(path).Length>32*1024*1024)throw new InvalidDataException("Capture settings companion exceeds 32 MB.");
        if(!AppleMagicTouchstreamProfileBundle.TryParse(File.ReadAllText(path),out var bundle,out var error) || !bundle.TryLoadPortableProfile(out settings,out map,out error))throw new InvalidDataException("Invalid capture settings companion: "+error);
        return true;
    }
}
