using System.Text.Json;

namespace GlassToKey.Linux.Runtime;

public sealed class LinuxRuntimeStateStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public string GetStatePath()
    {
        string? stateHome = Environment.GetEnvironmentVariable("XDG_STATE_HOME");
        string root = string.IsNullOrWhiteSpace(stateHome)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "state")
            : stateHome;
        return Path.Combine(root, "GlassToKey.Linux", "runtime-state.json");
    }

    public LinuxRuntimeStateSnapshot? Load()
    {
        string path = GetStatePath();
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            string json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<LinuxRuntimeStateSnapshot>(json, SerializerOptions);
        }
        catch
        {
            return null;
        }
    }

    public void Save(LinuxRuntimeStateSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);

        string path = GetStatePath();
        string? directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        string json = JsonSerializer.Serialize(snapshot, SerializerOptions);
        File.WriteAllText(path, json);
    }
}
