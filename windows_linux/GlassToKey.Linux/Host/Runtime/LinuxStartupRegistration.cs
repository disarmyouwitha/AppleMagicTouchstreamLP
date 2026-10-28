using System.Reflection;
using System.Text;

namespace GlassToKey.Linux.Runtime;

public static class LinuxStartupRegistration
{
    private const string AutostartFileName = "glasstokey-linux-autostart.desktop";

    public static bool IsEnabled()
    {
        return File.Exists(GetAutostartDesktopPath());
    }

    public static bool TrySetEnabled(bool enabled, out string? error)
    {
        error = null;
        string path = GetAutostartDesktopPath();

        try
        {
            if (!enabled)
            {
                if (File.Exists(path))
                {
                    File.Delete(path);
                }

                return true;
            }

            string exec = ResolveAutostartExec();
            if (string.IsNullOrWhiteSpace(exec))
            {
                error = "Could not resolve a runnable GlassToKey Linux GUI command for autostart.";
                return false;
            }

            string? directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(path, BuildDesktopEntry(exec), Encoding.UTF8);
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    private static string GetAutostartDesktopPath()
    {
        string? configHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        string root = string.IsNullOrWhiteSpace(configHome)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config")
            : configHome;
        return Path.Combine(root, "autostart", AutostartFileName);
    }

    private static string BuildDesktopEntry(string exec)
    {
        StringBuilder builder = new();
        builder.AppendLine("[Desktop Entry]");
        builder.AppendLine("Type=Application");
        builder.AppendLine("Name=GlassToKey Linux");
        builder.AppendLine("Comment=Start GlassToKey Linux in the background");
        builder.Append("Exec=").AppendLine(exec);
        builder.AppendLine("Terminal=false");
        builder.AppendLine("X-GNOME-Autostart-enabled=true");
        return builder.ToString();
    }

    private static string ResolveAutostartExec()
    {
        if (TryFindOnPath("glasstokey-gui", out string? wrapperPath))
        {
            return $"{EscapeDesktopEntryArgument(wrapperPath!)} --background";
        }

        string? processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath) && !IsDotnetHost(processPath))
        {
            return $"{EscapeDesktopEntryArgument(processPath)} --background";
        }

        string? entryAssemblyPath = Assembly.GetEntryAssembly()?.Location;
        if (!string.IsNullOrWhiteSpace(entryAssemblyPath) &&
            File.Exists(entryAssemblyPath))
        {
            if (entryAssemblyPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
            {
                string? siblingAppHost = TryResolveSiblingExecutable(entryAssemblyPath);
                if (!string.IsNullOrWhiteSpace(siblingAppHost))
                {
                    return $"{EscapeDesktopEntryArgument(siblingAppHost)} --background";
                }

                return $"dotnet {EscapeDesktopEntryArgument(entryAssemblyPath)} --background";
            }

            return $"{EscapeDesktopEntryArgument(entryAssemblyPath)} --background";
        }

        string publishedAppHost = Path.Combine(AppContext.BaseDirectory, "GlassToKey.Linux.Gui");
        if (File.Exists(publishedAppHost))
        {
            return $"{EscapeDesktopEntryArgument(publishedAppHost)} --background";
        }

        string publishedDll = Path.Combine(AppContext.BaseDirectory, "GlassToKey.Linux.Gui.dll");
        if (File.Exists(publishedDll))
        {
            return $"dotnet {EscapeDesktopEntryArgument(publishedDll)} --background";
        }

        return string.Empty;
    }

    private static string? TryResolveSiblingExecutable(string assemblyPath)
    {
        string directory = Path.GetDirectoryName(assemblyPath) ?? string.Empty;
        string fileName = Path.GetFileNameWithoutExtension(assemblyPath);
        if (string.IsNullOrWhiteSpace(directory) || string.IsNullOrWhiteSpace(fileName))
        {
            return null;
        }

        string candidate = Path.Combine(directory, fileName);
        return File.Exists(candidate) ? candidate : null;
    }

    private static bool TryFindOnPath(string fileName, out string? resolvedPath)
    {
        resolvedPath = null;
        string? path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        string[] segments = path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        for (int index = 0; index < segments.Length; index++)
        {
            string candidate = Path.Combine(segments[index], fileName);
            if (File.Exists(candidate))
            {
                resolvedPath = candidate;
                return true;
            }
        }

        return false;
    }

    private static bool IsDotnetHost(string processPath)
    {
        return string.Equals(
            Path.GetFileNameWithoutExtension(processPath),
            "dotnet",
            StringComparison.OrdinalIgnoreCase);
    }

    private static string EscapeDesktopEntryArgument(string value)
    {
        return "\"" + value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal) + "\"";
    }
}
