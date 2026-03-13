using System.ComponentModel;
using System.Diagnostics;
using GlassToKey.Platform.Linux.Uinput;

namespace GlassToKey.Linux.Runtime;

internal sealed class LinuxAppLaunchDispatcher : IInputDispatcher, IInputDispatcherDiagnosticsProvider, IAutocorrectController, IThreeFingerDragSink
{
    private readonly LinuxUinputDispatcher _inner;

    public LinuxAppLaunchDispatcher(LinuxUinputDispatcher inner)
    {
        _inner = inner ?? throw new ArgumentNullException(nameof(inner));
    }

    public void Dispatch(in DispatchEvent dispatchEvent)
    {
        _inner.Dispatch(in dispatchEvent);
        if (dispatchEvent.Kind != DispatchEventKind.AppLaunch ||
            !AppLaunchActionHelper.TryParse(dispatchEvent.SemanticAction.Label, out AppLaunchActionSpec spec))
        {
            return;
        }

        TryLaunch(spec);
    }

    public void Tick(long nowTicks)
    {
        _inner.Tick(nowTicks);
    }

    public void Dispose()
    {
        _inner.Dispose();
    }

    public bool TryGetDiagnostics(out InputDispatcherDiagnostics diagnostics)
    {
        return _inner.TryGetDiagnostics(out diagnostics);
    }

    public void SetAutocorrectEnabled(bool enabled)
    {
        _inner.SetAutocorrectEnabled(enabled);
    }

    public void ConfigureAutocorrectOptions(AutocorrectOptions options)
    {
        _inner.ConfigureAutocorrectOptions(options);
    }

    public void NotifyPointerActivity()
    {
        _inner.NotifyPointerActivity();
    }

    public void ForceAutocorrectReset(string reason)
    {
        _inner.ForceAutocorrectReset(reason);
    }

    public AutocorrectStatusSnapshot GetAutocorrectStatus()
    {
        return _inner.GetAutocorrectStatus();
    }

    public void MovePointerBy(int deltaX, int deltaY)
    {
        _inner.MovePointerBy(deltaX, deltaY);
    }

    public void SetLeftButtonState(bool pressed)
    {
        _inner.SetLeftButtonState(pressed);
    }

    private static void TryLaunch(AppLaunchActionSpec spec)
    {
        if (TryLaunchDirect(spec))
        {
            return;
        }

        if (!string.IsNullOrWhiteSpace(spec.Arguments) || !LinuxGuiLauncher.IsGraphicalSession())
        {
            return;
        }

        _ = TryLaunchWithXdgOpen(spec.FileName);
    }

    private static bool TryLaunchDirect(AppLaunchActionSpec spec)
    {
        try
        {
            ProcessStartInfo startInfo = new()
            {
                FileName = spec.FileName,
                UseShellExecute = false
            };

            if (!string.IsNullOrWhiteSpace(spec.Arguments))
            {
                startInfo.Arguments = spec.Arguments;
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

    private static bool TryLaunchWithXdgOpen(string target)
    {
        try
        {
            ProcessStartInfo startInfo = new()
            {
                FileName = "xdg-open",
                UseShellExecute = false
            };
            startInfo.ArgumentList.Add(target);
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
