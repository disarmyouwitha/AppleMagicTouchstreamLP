using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using GlassToKey.Platform.Linux.Uinput;

namespace GlassToKey.Linux.Runtime;

internal sealed class LinuxAppLaunchDispatcher : IInputDispatcher, IInputDispatcherDiagnosticsProvider, IAutocorrectController, IThreeFingerDragSink
{
    private const string EmojiActionLabel = "EMOJI";
    private const string EmojiPickerExecutable = "/usr/libexec/ibus-ui-emojier";
    private const string EmojiCopiedMessage = "Copied an emoji to your clipboard.";
    private static readonly TimeSpan EmojiExitGracePeriod = TimeSpan.FromMilliseconds(500);
    private static readonly TimeSpan EmojiPasteDelay = TimeSpan.FromMilliseconds(125);

    private readonly LinuxUinputDispatcher _inner;
    private int _emojiPickerActive;

    public LinuxAppLaunchDispatcher(LinuxUinputDispatcher inner)
    {
        _inner = inner ?? throw new ArgumentNullException(nameof(inner));
    }

    public void Dispatch(in DispatchEvent dispatchEvent)
    {
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
        _inner.Dispatch(new DispatchEvent(
            TimestampTicks: Stopwatch.GetTimestamp(),
            Kind: DispatchEventKind.KeyTap,
            VirtualKey: 0x56,
            MouseButton: DispatchMouseButton.None,
            RepeatToken: 0,
            Flags: DispatchEventFlags.None,
            Side: TrackpadSide.Left,
            DispatchLabel: "Paste",
            SemanticAction: new DispatchSemanticAction(
                DispatchSemanticKind.KeyChord,
                "Ctrl+V",
                PrimaryCode: DispatchSemanticCode.V,
                SecondaryCode: DispatchSemanticCode.Ctrl,
                MouseButton: DispatchMouseButton.None,
                Modifiers: DispatchModifierFlags.Ctrl)));
    }

    private static bool IsEmojiAction(DispatchSemanticAction semanticAction)
    {
        return semanticAction.Label.Equals(EmojiActionLabel, StringComparison.OrdinalIgnoreCase);
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
