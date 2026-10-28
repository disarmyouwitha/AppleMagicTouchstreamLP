namespace GlassToKey.Linux.Runtime;

public sealed class LinuxGuiActivationSignalStore
{
    public string GetSignalPath()
    {
        string? runtimeDirectory = Environment.GetEnvironmentVariable("XDG_RUNTIME_DIR");
        string root = string.IsNullOrWhiteSpace(runtimeDirectory)
            ? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".local",
                "state")
            : runtimeDirectory;
        return Path.Combine(root, "GlassToKey.Linux", "show-config.signal");
    }

    public void RequestShow()
    {
        string path = GetSignalPath();
        string? directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(path, DateTimeOffset.UtcNow.ToString("O"));
    }

    public bool TryConsumeShowRequest()
    {
        string path = GetSignalPath();
        if (!File.Exists(path))
        {
            return false;
        }

        try
        {
            File.Delete(path);
            return true;
        }
        catch
        {
            return false;
        }
    }
}
