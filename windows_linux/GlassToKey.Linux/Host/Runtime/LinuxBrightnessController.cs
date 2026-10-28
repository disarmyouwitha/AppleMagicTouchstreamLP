using System.Diagnostics;
using System.Globalization;

namespace GlassToKey.Linux.Runtime;

internal static class LinuxBrightnessController
{
    private const string BacklightDirectory = "/sys/class/backlight";
    private const string XrandrExecutable = "/usr/bin/xrandr";

    private static readonly object Gate = new();
    private static int _nativeBrightnessAvailability = -1;

    public static bool ShouldUseNativeBrightnessPath()
    {
        int cached = Volatile.Read(ref _nativeBrightnessAvailability);
        if (cached >= 0)
        {
            return cached == 1;
        }

        bool available = DetectNativeBrightnessAvailability();
        Volatile.Write(ref _nativeBrightnessAvailability, available ? 1 : 0);
        return available;
    }

    public static bool CanUseXrandrFallback()
    {
        return OperatingSystem.IsLinux() &&
               string.Equals(Environment.GetEnvironmentVariable("XDG_SESSION_TYPE"), "x11", StringComparison.OrdinalIgnoreCase) &&
               !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DISPLAY")) &&
               File.Exists(XrandrExecutable);
    }

    public static void AdjustBrightnessBy(double delta)
    {
        if (delta == 0 || !CanUseXrandrFallback())
        {
            return;
        }

        lock (Gate)
        {
            if (!TryReadCurrentBrightness(out string outputName, out double currentBrightness))
            {
                return;
            }

            double nextBrightness = Math.Clamp(currentBrightness + delta, 0.0, 1.0);
            if (Math.Abs(nextBrightness - currentBrightness) < 0.0001)
            {
                return;
            }

            RunProcess(
                XrandrExecutable,
                ["--output", outputName, "--brightness", nextBrightness.ToString("0.###", CultureInfo.InvariantCulture)],
                timeoutMs: 1500,
                out _);
        }
    }

    private static bool DetectNativeBrightnessAvailability()
    {
        try
        {
            return Directory.Exists(BacklightDirectory) &&
                   Directory.EnumerateFileSystemEntries(BacklightDirectory).Any();
        }
        catch
        {
            return false;
        }
    }

    private static bool TryReadCurrentBrightness(out string outputName, out double brightness)
    {
        outputName = string.Empty;
        brightness = 1.0;

        if (!RunProcess(XrandrExecutable, ["--verbose"], timeoutMs: 1500, out string output))
        {
            return false;
        }

        string? currentOutput = null;
        string? primaryOutput = null;
        string? firstConnectedOutput = null;
        Dictionary<string, double> brightnessByOutput = new(StringComparer.Ordinal);

        string[] lines = output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries);
        for (int index = 0; index < lines.Length; index++)
        {
            string line = lines[index];
            if (!char.IsWhiteSpace(line, 0))
            {
                string trimmed = line.Trim();
                int connectedIndex = trimmed.IndexOf(" connected", StringComparison.Ordinal);
                if (connectedIndex <= 0)
                {
                    currentOutput = null;
                    continue;
                }

                currentOutput = trimmed[..connectedIndex];
                firstConnectedOutput ??= currentOutput;
                if (trimmed.Contains(" connected primary ", StringComparison.Ordinal))
                {
                    primaryOutput = currentOutput;
                }

                continue;
            }

            if (currentOutput is null)
            {
                continue;
            }

            string trimmedLine = line.Trim();
            if (!trimmedLine.StartsWith("Brightness:", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            string value = trimmedLine["Brightness:".Length..].Trim();
            if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out double parsedBrightness))
            {
                brightnessByOutput[currentOutput] = parsedBrightness;
            }
        }

        outputName = primaryOutput ?? firstConnectedOutput ?? string.Empty;
        if (string.IsNullOrWhiteSpace(outputName))
        {
            return false;
        }

        if (!brightnessByOutput.TryGetValue(outputName, out brightness))
        {
            brightness = 1.0;
        }

        return true;
    }

    private static bool RunProcess(string fileName, string[] arguments, int timeoutMs, out string stdout)
    {
        stdout = string.Empty;

        try
        {
            ProcessStartInfo startInfo = new()
            {
                FileName = fileName,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            for (int index = 0; index < arguments.Length; index++)
            {
                startInfo.ArgumentList.Add(arguments[index]);
            }

            using Process? process = Process.Start(startInfo);
            if (process is null)
            {
                return false;
            }

            stdout = process.StandardOutput.ReadToEnd();
            if (!process.WaitForExit(timeoutMs))
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // Best-effort cleanup.
                }

                return false;
            }

            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }
}
