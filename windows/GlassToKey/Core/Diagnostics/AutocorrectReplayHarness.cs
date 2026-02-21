using System;
using System.Diagnostics;

namespace GlassToKey;

internal sealed class AutocorrectReplayHarness
{
    public AutocorrectReplayResult Run(string script, AutocorrectOptions options)
    {
        SendInputDispatcher dispatcher = new();
        try
        {
            dispatcher.SetPhysicalOutputSuppressed(true);
            dispatcher.ConfigureAutocorrectOptions(options);
            dispatcher.SetAutocorrectEnabled(true);
            int eventCount = ExecuteScript(dispatcher, script ?? string.Empty);
            AutocorrectStatusSnapshot status = dispatcher.GetAutocorrectStatus();
            return new AutocorrectReplayResult(eventCount, status);
        }
        finally
        {
            dispatcher.Dispose();
        }
    }

    private static int ExecuteScript(SendInputDispatcher dispatcher, string script)
    {
        int eventCount = 0;
        for (int i = 0; i < script.Length; i++)
        {
            char ch = script[i];
            if ((ch == '<' || ch == '[') && TryConsumeCommand(script, ref i, out string command))
            {
                eventCount += ExecuteCommand(dispatcher, command);
                continue;
            }

            if (!TryResolveCharVirtualKey(ch, out ushort virtualKey))
            {
                continue;
            }

            DispatchEvent dispatchEvent = new(
                TimestampTicks: Stopwatch.GetTimestamp(),
                Kind: DispatchEventKind.KeyTap,
                VirtualKey: virtualKey,
                MouseButton: DispatchMouseButton.None,
                RepeatToken: 0,
                Flags: DispatchEventFlags.None,
                Side: TrackpadSide.Left,
                DispatchLabel: "autocorrect-replay");
            dispatcher.Dispatch(dispatchEvent);
            eventCount++;
        }

        return eventCount;
    }

    private static int ExecuteCommand(SendInputDispatcher dispatcher, string command)
    {
        switch (command)
        {
            case "space":
                dispatcher.Dispatch(CreateKeyTapEvent(0x20, "autocorrect-replay-space"));
                return 1;
            case "tab":
                dispatcher.Dispatch(CreateKeyTapEvent(0x09, "autocorrect-replay-tab"));
                return 1;
            case "enter":
                dispatcher.Dispatch(CreateKeyTapEvent(0x0D, "autocorrect-replay-enter"));
                return 1;
            case "backspace":
                dispatcher.Dispatch(CreateKeyTapEvent(0x08, "autocorrect-replay-backspace"));
                return 1;
            case "click":
            case "pointer_click":
                dispatcher.NotifyPointerActivity();
                dispatcher.Tick(Stopwatch.GetTimestamp());
                return 1;
            case "app-change":
            case "app_changed":
                dispatcher.ForceAutocorrectReset("app_changed");
                return 1;
            case "ctrl-down":
                dispatcher.Dispatch(CreateModifierEvent(DispatchEventKind.ModifierDown, 0x11, "autocorrect-replay-ctrl-down"));
                return 1;
            case "ctrl-up":
                dispatcher.Dispatch(CreateModifierEvent(DispatchEventKind.ModifierUp, 0x11, "autocorrect-replay-ctrl-up"));
                return 1;
            case "alt-down":
                dispatcher.Dispatch(CreateModifierEvent(DispatchEventKind.ModifierDown, 0x12, "autocorrect-replay-alt-down"));
                return 1;
            case "alt-up":
                dispatcher.Dispatch(CreateModifierEvent(DispatchEventKind.ModifierUp, 0x12, "autocorrect-replay-alt-up"));
                return 1;
            case "win-down":
                dispatcher.Dispatch(CreateModifierEvent(DispatchEventKind.ModifierDown, 0x5B, "autocorrect-replay-win-down"));
                return 1;
            case "win-up":
                dispatcher.Dispatch(CreateModifierEvent(DispatchEventKind.ModifierUp, 0x5B, "autocorrect-replay-win-up"));
                return 1;
            case "shift-down":
                dispatcher.Dispatch(CreateModifierEvent(DispatchEventKind.ModifierDown, 0x10, "autocorrect-replay-shift-down"));
                return 1;
            case "shift-up":
                dispatcher.Dispatch(CreateModifierEvent(DispatchEventKind.ModifierUp, 0x10, "autocorrect-replay-shift-up"));
                return 1;
            default:
                return 0;
        }
    }

    private static DispatchEvent CreateKeyTapEvent(ushort virtualKey, string label)
    {
        return new DispatchEvent(
            TimestampTicks: Stopwatch.GetTimestamp(),
            Kind: DispatchEventKind.KeyTap,
            VirtualKey: virtualKey,
            MouseButton: DispatchMouseButton.None,
            RepeatToken: 0,
            Flags: DispatchEventFlags.None,
            Side: TrackpadSide.Left,
            DispatchLabel: label);
    }

    private static DispatchEvent CreateModifierEvent(DispatchEventKind kind, ushort virtualKey, string label)
    {
        return new DispatchEvent(
            TimestampTicks: Stopwatch.GetTimestamp(),
            Kind: kind,
            VirtualKey: virtualKey,
            MouseButton: DispatchMouseButton.None,
            RepeatToken: 0,
            Flags: DispatchEventFlags.None,
            Side: TrackpadSide.Left,
            DispatchLabel: label);
    }

    private static bool TryConsumeCommand(string script, ref int index, out string command)
    {
        command = string.Empty;
        char open = script[index];
        char close = open == '<' ? '>' : ']';
        int closeIndex = script.IndexOf(close, index + 1);
        if (closeIndex <= index + 1)
        {
            return false;
        }

        command = script.Substring(index + 1, closeIndex - index - 1).Trim().ToLowerInvariant();
        index = closeIndex;
        return command.Length > 0;
    }

    private static bool TryResolveCharVirtualKey(char ch, out ushort virtualKey)
    {
        if (ch >= 'a' && ch <= 'z')
        {
            virtualKey = (ushort)(ch - 'a' + 0x41);
            return true;
        }

        if (ch >= 'A' && ch <= 'Z')
        {
            virtualKey = (ushort)(ch - 'A' + 0x41);
            return true;
        }

        if (ch >= '0' && ch <= '9')
        {
            virtualKey = (ushort)(ch - '0' + 0x30);
            return true;
        }

        switch (ch)
        {
            case ' ':
                virtualKey = 0x20;
                return true;
            case '\t':
                virtualKey = 0x09;
                return true;
            case '\r':
            case '\n':
                virtualKey = 0x0D;
                return true;
            case ';':
            case ':':
                virtualKey = 0xBA;
                return true;
            case ',':
            case '<':
                virtualKey = 0xBC;
                return true;
            case '-':
            case '_':
                virtualKey = 0xBD;
                return true;
            case '.':
            case '>':
                virtualKey = 0xBE;
                return true;
            case '/':
            case '?':
                virtualKey = 0xBF;
                return true;
            case '`':
            case '~':
                virtualKey = 0xC0;
                return true;
            case '[':
            case '{':
                virtualKey = 0xDB;
                return true;
            case '\\':
            case '|':
                virtualKey = 0xDC;
                return true;
            case ']':
            case '}':
                virtualKey = 0xDD;
                return true;
            case '\'':
            case '"':
                virtualKey = 0xDE;
                return true;
            default:
                virtualKey = 0;
                return false;
        }
    }
}

internal readonly record struct AutocorrectReplayResult(
    int EventCount,
    AutocorrectStatusSnapshot Status);
