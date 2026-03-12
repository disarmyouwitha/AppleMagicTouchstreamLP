using System;
using System.IO;
using System.Text.Json;

namespace GlassToKey;

public readonly record struct AppLaunchActionSpec(string FileName, string Arguments);

public static class AppLaunchActionHelper
{
    private const string Prefix = "APP:";
    private const int MaxDisplayLength = 56;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public static string CreateActionLabel(string fileName, string? arguments = null)
    {
        if (string.IsNullOrWhiteSpace(fileName))
        {
            throw new ArgumentException("App launch file name is required.", nameof(fileName));
        }

        AppLaunchActionSpec spec = new(
            fileName.Trim(),
            string.IsNullOrWhiteSpace(arguments) ? string.Empty : arguments.Trim());
        return Prefix + JsonSerializer.Serialize(spec, JsonOptions);
    }

    public static bool TryParse(string? action, out AppLaunchActionSpec spec)
    {
        spec = default;
        if (string.IsNullOrWhiteSpace(action))
        {
            return false;
        }

        string trimmed = action.Trim();
        if (!trimmed.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        string payload = trimmed.Substring(Prefix.Length).Trim();
        if (payload.Length == 0)
        {
            return false;
        }

        try
        {
            AppLaunchActionSpec? parsed = JsonSerializer.Deserialize<AppLaunchActionSpec>(payload, JsonOptions);
            if (parsed == null || string.IsNullOrWhiteSpace(parsed.Value.FileName))
            {
                return false;
            }

            spec = new AppLaunchActionSpec(
                parsed.Value.FileName.Trim(),
                string.IsNullOrWhiteSpace(parsed.Value.Arguments) ? string.Empty : parsed.Value.Arguments.Trim());
            return true;
        }
        catch
        {
            return false;
        }
    }

    public static string GetDisplayLabel(string? action)
    {
        return TryParse(action, out AppLaunchActionSpec spec)
            ? FormatDisplayLabel(spec)
            : action?.Trim() ?? string.Empty;
    }

    public static string FormatDisplayLabel(AppLaunchActionSpec spec)
    {
        string fileName = spec.FileName.Trim();
        string leafName = Path.GetFileName(fileName.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (string.IsNullOrWhiteSpace(leafName))
        {
            leafName = fileName;
        }

        string display = string.IsNullOrWhiteSpace(spec.Arguments)
            ? $"App: {leafName}"
            : $"App: {leafName} {spec.Arguments.Trim()}";
        return display.Length <= MaxDisplayLength
            ? display
            : display.Substring(0, MaxDisplayLength - 3) + "...";
    }
}
