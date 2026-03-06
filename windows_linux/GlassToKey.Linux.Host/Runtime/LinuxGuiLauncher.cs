using System.ComponentModel;
using System.Diagnostics;

namespace GlassToKey.Linux.Runtime;

public static class LinuxGuiLauncher
{
    public static bool TryLaunch()
    {
        return TryShowConfig();
    }

    public static bool TryLaunchTray(bool noRuntime = false)
    {
        return TryLaunchInternal(showConfig: false, noRuntime);
    }

    public static bool TryShowConfig(bool noRuntime = false)
    {
        return TryLaunchInternal(showConfig: true, noRuntime);
    }

    public static bool IsGraphicalSession()
    {
        return !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("WAYLAND_DISPLAY")) ||
               !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DISPLAY")) ||
               string.Equals(Environment.GetEnvironmentVariable("XDG_SESSION_TYPE"), "wayland", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(Environment.GetEnvironmentVariable("XDG_SESSION_TYPE"), "x11", StringComparison.OrdinalIgnoreCase);
    }

    private static bool TryLaunchInternal(bool showConfig, bool noRuntime)
    {
        foreach (string candidate in GetLaunchCandidates())
        {
            if (TryLaunchCandidate(candidate, showConfig, noRuntime))
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

    private static bool TryLaunchCandidate(string candidate, bool showConfig, bool noRuntime)
    {
        try
        {
            ProcessStartInfo startInfo = new()
            {
                FileName = candidate,
                UseShellExecute = false
            };
            startInfo.ArgumentList.Add(showConfig ? "--show" : "--background");
            if (noRuntime)
            {
                startInfo.ArgumentList.Add("--no-runtime");
            }

            Process.Start(startInfo);
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
