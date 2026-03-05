using System.ComponentModel;
using System.Diagnostics;

namespace GlassToKey.Linux.Runtime;

public static class LinuxGuiLauncher
{
    public static bool IsGraphicalSession()
    {
        return !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("WAYLAND_DISPLAY")) ||
               !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DISPLAY")) ||
               string.Equals(Environment.GetEnvironmentVariable("XDG_SESSION_TYPE"), "wayland", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(Environment.GetEnvironmentVariable("XDG_SESSION_TYPE"), "x11", StringComparison.OrdinalIgnoreCase);
    }

    public static bool TryLaunch()
    {
        foreach (string candidate in GetLaunchCandidates())
        {
            if (TryLaunchCandidate(candidate))
            {
                return true;
            }
        }

        return false;
    }

    private static IEnumerable<string> GetLaunchCandidates()
    {
        string baseDirectory = AppContext.BaseDirectory;
        string installedGuiExecutable = Path.GetFullPath(Path.Combine(baseDirectory, "..", "GlassToKey.Linux.Gui", "GlassToKey.Linux.Gui"));
        if (File.Exists(installedGuiExecutable))
        {
            yield return installedGuiExecutable;
        }

        yield return "glasstokey-gui";
        yield return "glasstokey-linux-gui";
    }

    private static bool TryLaunchCandidate(string candidate)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = candidate,
                ArgumentList = { "--show" },
                UseShellExecute = false
            });
            return true;
        }
        catch (Win32Exception)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }
}
