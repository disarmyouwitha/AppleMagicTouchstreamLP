using System.IO;

namespace AppleMagicTouchstream;

internal static class BrandingMigrationTests
{
    public static void Run()
    {
        if(typeof(App).Assembly.GetName().Name!="AppleMagicTouchstream"
            || typeof(UserSettings).Assembly.GetName().Name!="AppleMagicTouchstream.Core")
            throw new InvalidOperationException("Renamed app/core assembly identities are incorrect");
        if(Path.GetFileName(KeymapStore.GetDefaultKeymapPath())!="DEFAULT_KEYMAP.json"
            || !File.Exists(KeymapStore.GetDefaultKeymapPath()))
            throw new InvalidOperationException("Renamed bundled keymap is missing");
        string root=Path.Combine(Path.GetTempPath(),"AppleMagicTouchstream-migration-"+Guid.NewGuid().ToString("N"));
        string legacy=Path.Combine(root,"old","keymap.json"), current=Path.Combine(root,"new","keymap.json");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(legacy)!);
            File.WriteAllText(legacy,"saved user keymap");
            if(ApplicationDataPaths.MigrateLegacyFile(current,legacy)!=current || File.ReadAllText(current)!="saved user keymap")
                throw new InvalidOperationException("Legacy user data was not migrated");
            File.WriteAllText(current,"new user edit");
            ApplicationDataPaths.MigrateLegacyFile(current,legacy);
            if(File.ReadAllText(current)!="new user edit" || File.ReadAllText(legacy)!="saved user keymap")
                throw new InvalidOperationException("Migration overwrote current or legacy user data");
        }
        finally
        {
            File.Delete(current); File.Delete(legacy);
            if(Directory.Exists(Path.GetDirectoryName(current)!)) Directory.Delete(Path.GetDirectoryName(current)!);
            if(Directory.Exists(Path.GetDirectoryName(legacy)!)) Directory.Delete(Path.GetDirectoryName(legacy)!);
            if(Directory.Exists(root)) Directory.Delete(root);
        }
    }
}
