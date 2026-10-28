using System.IO;

namespace AppleMagicTouchstream;

public static class ApplicationDataPaths
{
    public static string UserFile(string fileName)
    {
        string root=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return MigrateLegacyFile(Path.Combine(root,"AppleMagicTouchstream",fileName),Path.Combine(root,"GlassToKey",fileName));
    }

    // Copy once; never overwrite current data or delete the previous app's files.
    public static string MigrateLegacyFile(string currentPath,string legacyPath)
    {
        if(File.Exists(currentPath) || !File.Exists(legacyPath)) return currentPath;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(currentPath)!);
            File.Copy(legacyPath,currentPath,overwrite:false);
            return currentPath;
        }
        catch { return File.Exists(currentPath) ? currentPath : legacyPath; }
    }
}
