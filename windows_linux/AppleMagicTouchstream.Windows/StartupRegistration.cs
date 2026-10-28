using System;
using System.Diagnostics;
using Microsoft.Win32;

namespace AppleMagicTouchstream;

internal static class StartupRegistration
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "AppleMagicTouchstream";

    public static bool IsEnabled()
    {
        try
        {
            using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            string? value = (key?.GetValue(ValueName) ?? key?.GetValue("GlassToKey")) as string;
            return !string.IsNullOrWhiteSpace(value);
        }
        catch
        {
            return false;
        }
    }

    public static void MigrateLegacyRegistration()
    {
        try
        {
            using RegistryKey? key=Registry.CurrentUser.OpenSubKey(RunKeyPath,writable:false);
            if(key?.GetValue("GlassToKey") is string legacy && !string.IsNullOrWhiteSpace(legacy))
                TrySetEnabled(true,out _);
        }
        catch { /* An existing registration can be repaired through Options. */ }
    }

    public static bool TrySetEnabled(bool enabled, out string? error)
    {
        error = null;
        try
        {
            using RegistryKey key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
            if (enabled)
            {
                string? processPath = Environment.ProcessPath;
                if (string.IsNullOrWhiteSpace(processPath))
                {
                    processPath = Process.GetCurrentProcess().MainModule?.FileName;
                }

                if (string.IsNullOrWhiteSpace(processPath))
                {
                    error = "Unable to resolve executable path for startup registration.";
                    return false;
                }

                string command = $"\"{processPath}\"";
                key.SetValue(ValueName, command, RegistryValueKind.String);
            }
            else
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }

            key.DeleteValue("GlassToKey",throwOnMissingValue:false);
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }
}
