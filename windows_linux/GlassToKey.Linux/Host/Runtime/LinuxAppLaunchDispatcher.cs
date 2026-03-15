using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using GlassToKey.Platform.Linux.Uinput;

namespace GlassToKey.Linux.Runtime;

internal sealed class LinuxAppLaunchDispatcher : IInputDispatcher, IInputDispatcherDiagnosticsProvider, IAutocorrectController, IThreeFingerDragSink
{
    private const string EmojiActionLabel = "EMOJI";
    private const string BrightnessUpActionLabel = "BRIGHT_UP";
    private const string BrightnessDownActionLabel = "BRIGHT_DOWN";
    private const string EmojiPickerExecutable = "/usr/libexec/ibus-ui-emojier";
    private const string EmojiCopiedMessage = "Copied an emoji to your clipboard.";
    private const string XpropExecutable = "/usr/bin/xprop";
    private static readonly Regex QuotedValueRegex = new("\"([^\"]+)\"", RegexOptions.Compiled);
    private static readonly TimeSpan EmojiExitGracePeriod = TimeSpan.FromMilliseconds(500);
    private static readonly TimeSpan EmojiPasteDelay = TimeSpan.FromMilliseconds(125);
    private static readonly string[] TerminalWindowClassMarkers =
    [
        "gnome-terminal",
        "gnome-console",
        "org.gnome.console",
        "kgx",
        "ptyxis",
        "kitty",
        "alacritty",
        "wezterm",
        "xterm",
        "xfce4-terminal",
        "konsole",
        "tilix",
        "terminator",
        "lxterminal",
        "mate-terminal",
        "qterminal",
        "io.elementary.terminal",
        "deepin-terminal"
    ];

    private readonly LinuxUinputDispatcher _inner;
    private int _emojiPickerActive;

    public LinuxAppLaunchDispatcher(LinuxUinputDispatcher inner)
    {
        _inner = inner ?? throw new ArgumentNullException(nameof(inner));
    }

    public void Dispatch(in DispatchEvent dispatchEvent)
    {
        if (TryGetBrightnessDelta(dispatchEvent.SemanticAction, out double brightnessDelta))
        {
            HandleBrightnessDispatch(dispatchEvent, brightnessDelta);
            return;
        }

        if (IsEmojiAction(dispatchEvent.SemanticAction))
        {
            HandleEmojiDispatch(dispatchEvent);
            return;
        }

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

    private void HandleBrightnessDispatch(in DispatchEvent dispatchEvent, double brightnessDelta)
    {
        if (dispatchEvent.Kind != DispatchEventKind.KeyTap)
        {
            return;
        }

        if (LinuxBrightnessController.ShouldUseNativeBrightnessPath())
        {
            _inner.Dispatch(in dispatchEvent);
            return;
        }

        if (!LinuxBrightnessController.CanUseXrandrFallback())
        {
            return;
        }

        ThreadPool.UnsafeQueueUserWorkItem(
            static state => LinuxBrightnessController.AdjustBrightnessBy((double)state!),
            brightnessDelta,
            preferLocal: false);
    }

    private void HandleEmojiDispatch(in DispatchEvent dispatchEvent)
    {
        if (dispatchEvent.Kind != DispatchEventKind.KeyTap ||
            Interlocked.CompareExchange(ref _emojiPickerActive, 1, 0) != 0)
        {
            return;
        }

        ThreadPool.UnsafeQueueUserWorkItem(
            static state => ((LinuxAppLaunchDispatcher)state!).RunEmojiPickerAndPasteBackground(),
            this,
            preferLocal: false);
    }

    private void RunEmojiPickerAndPasteBackground()
    {
        _ = LaunchEmojiPickerAndPasteAsync();
    }

    private async Task LaunchEmojiPickerAndPasteAsync()
    {
        try
        {
            using Process? process = TryStartEmojiPicker();
            if (process is null)
            {
                return;
            }

            Task<bool> signalTask = WaitForEmojiClipboardSignalAsync(process);
            Task exitTask = process.WaitForExitAsync();
            Task completed = await Task.WhenAny(signalTask, exitTask).ConfigureAwait(false);

            if (completed == signalTask && await signalTask.ConfigureAwait(false) && !process.HasExited)
            {
                await Task.WhenAny(exitTask, Task.Delay(EmojiExitGracePeriod)).ConfigureAwait(false);
            }

            await Task.Delay(EmojiPasteDelay).ConfigureAwait(false);
            EmitPasteShortcut();

            if (!process.HasExited)
            {
                await exitTask.ConfigureAwait(false);
            }
        }
        catch
        {
            // Best-effort runtime action.
        }
        finally
        {
            Interlocked.Exchange(ref _emojiPickerActive, 0);
        }
    }

    private static Process? TryStartEmojiPicker()
    {
        if (!File.Exists(EmojiPickerExecutable))
        {
            return null;
        }

        try
        {
            ProcessStartInfo startInfo = new()
            {
                FileName = EmojiPickerExecutable,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            return Process.Start(startInfo);
        }
        catch (Win32Exception)
        {
            return null;
        }
        catch (InvalidOperationException)
        {
            return null;
        }
    }

    private static async Task<bool> WaitForEmojiClipboardSignalAsync(Process process)
    {
        Task<bool> stdoutTask = WaitForEmojiClipboardSignalAsync(process.StandardOutput);
        Task<bool> stderrTask = WaitForEmojiClipboardSignalAsync(process.StandardError);
        Task<bool> firstCompleted = await Task.WhenAny(stdoutTask, stderrTask).ConfigureAwait(false);
        if (await firstCompleted.ConfigureAwait(false))
        {
            return true;
        }

        Task<bool> remaining = firstCompleted == stdoutTask ? stderrTask : stdoutTask;
        return await remaining.ConfigureAwait(false);
    }

    private static async Task<bool> WaitForEmojiClipboardSignalAsync(StreamReader reader)
    {
        while (true)
        {
            string? line = await reader.ReadLineAsync().ConfigureAwait(false);
            if (line is null)
            {
                return false;
            }

            if (line.Contains(EmojiCopiedMessage, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
    }

    private void EmitPasteShortcut()
    {
        DispatchSemanticAction semanticAction = ResolvePasteSemanticAction();
        _inner.Dispatch(new DispatchEvent(
            TimestampTicks: Stopwatch.GetTimestamp(),
            Kind: DispatchEventKind.KeyTap,
            VirtualKey: 0x56,
            MouseButton: DispatchMouseButton.None,
            RepeatToken: 0,
            Flags: DispatchEventFlags.None,
            Side: TrackpadSide.Left,
            DispatchLabel: "Paste",
            SemanticAction: semanticAction));
    }

    private static DispatchSemanticAction ResolvePasteSemanticAction()
    {
        if (TryGetFocusedWindowClass(out string windowClass) &&
            LooksLikeTerminalWindowClass(windowClass))
        {
            return new DispatchSemanticAction(
                DispatchSemanticKind.KeyChord,
                "Ctrl+Shift+V",
                PrimaryCode: DispatchSemanticCode.V,
                SecondaryCode: DispatchSemanticCode.None,
                MouseButton: DispatchMouseButton.None,
                Modifiers: DispatchModifierFlags.Ctrl | DispatchModifierFlags.Shift);
        }

        return new DispatchSemanticAction(
            DispatchSemanticKind.KeyChord,
            "Ctrl+V",
            PrimaryCode: DispatchSemanticCode.V,
            SecondaryCode: DispatchSemanticCode.Ctrl,
            MouseButton: DispatchMouseButton.None,
            Modifiers: DispatchModifierFlags.Ctrl);
    }

    private static bool TryGetFocusedWindowClass(out string windowClass)
    {
        windowClass = string.Empty;
        if (!OperatingSystem.IsLinux() ||
            !string.Equals(Environment.GetEnvironmentVariable("XDG_SESSION_TYPE"), "x11", StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DISPLAY")) ||
            !File.Exists(XpropExecutable) ||
            !TryRunProcess(XpropExecutable, ["-root", "_NET_ACTIVE_WINDOW"], out string activeWindowOutput))
        {
            return false;
        }

        string windowId = ExtractWindowId(activeWindowOutput);
        if (string.IsNullOrWhiteSpace(windowId) ||
            !TryRunProcess(XpropExecutable, ["-id", windowId, "WM_CLASS"], out string classOutput))
        {
            return false;
        }

        MatchCollection matches = QuotedValueRegex.Matches(classOutput);
        if (matches.Count == 0)
        {
            return false;
        }

        string[] values = new string[matches.Count];
        for (int index = 0; index < matches.Count; index++)
        {
            values[index] = matches[index].Groups[1].Value;
        }

        windowClass = string.Join('\n', values);
        return true;
    }

    private static bool TryRunProcess(string fileName, string[] arguments, out string output)
    {
        output = string.Empty;

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

            output = process.StandardOutput.ReadToEnd();
            if (!process.WaitForExit(milliseconds: 750))
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
        catch (Win32Exception)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    private static string ExtractWindowId(string output)
    {
        int marker = output.IndexOf("0x", StringComparison.OrdinalIgnoreCase);
        if (marker < 0)
        {
            return string.Empty;
        }

        int end = marker + 2;
        while (end < output.Length && Uri.IsHexDigit(output[end]))
        {
            end++;
        }

        return end > marker + 2 ? output[marker..end] : string.Empty;
    }

    private static bool LooksLikeTerminalWindowClass(string windowClass)
    {
        string normalized = windowClass.ToLowerInvariant();
        for (int index = 0; index < TerminalWindowClassMarkers.Length; index++)
        {
            if (normalized.Contains(TerminalWindowClassMarkers[index], StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsEmojiAction(DispatchSemanticAction semanticAction)
    {
        return semanticAction.Label.Equals(EmojiActionLabel, StringComparison.OrdinalIgnoreCase);
    }

    private static bool TryGetBrightnessDelta(DispatchSemanticAction semanticAction, out double delta)
    {
        if (semanticAction.Label.Equals(BrightnessUpActionLabel, StringComparison.OrdinalIgnoreCase))
        {
            delta = 0.1;
            return true;
        }

        if (semanticAction.Label.Equals(BrightnessDownActionLabel, StringComparison.OrdinalIgnoreCase))
        {
            delta = -0.1;
            return true;
        }

        delta = 0;
        return false;
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
