using System;

namespace GlassToKey;

public sealed class ReaderOptions
{
    public bool ListDevices { get; private set; }
    public bool HidProbe { get; private set; }
    public int HidDeviceIndex { get; private set; }
    public bool HidIndexSpecified { get; private set; }
    public string? HidFeaturePayloadHex { get; private set; }
    public string? HidOutputPayloadHex { get; private set; }
    public string? HidWritePayloadHex { get; private set; }
    public int HidRepeat { get; private set; } = 1;
    public int HidIntervalMs { get; private set; }
    public bool HidAutoProbe { get; private set; }
    public int HidAutoReportMax { get; private set; } = 15;
    public int HidAutoIntervalMs { get; private set; } = 10;
    public string? HidAutoLogPath { get; private set; }
    public bool HidActuatorPulse { get; private set; }
    public bool HidActuatorVibrate { get; private set; }
    public int HidActuatorCount { get; private set; } = 10;
    public int HidActuatorIntervalMs { get; private set; } = 60;
    public uint HidActuatorParam32 { get; private set; } = 0x00026C15u;
    public bool RunSelfTest { get; private set; }
    public ushort? MaxX { get; private set; }
    public ushort? MaxY { get; private set; }
    public string? CapturePath { get; private set; }
    public string? ReplayPath { get; private set; }
    public string? ReplayFixturePath { get; private set; }
    public string? MetricsOutputPath { get; private set; }
    public string? ReplayTraceOutputPath { get; private set; }
    public string? RawAnalyzePath { get; private set; }
    public string? RawAnalyzeOutputPath { get; private set; }
    public string? RawAnalyzeContactsOutputPath { get; private set; }
    public bool DecoderDebug { get; private set; }
    public bool ReplayInUi { get; private set; }
    public double ReplaySpeed { get; private set; } = 1.0;
    public bool StartInConfigUi { get; private set; }
    public bool RelaunchTrayOnClose { get; private set; }
    public bool HasHidResearchCommand =>
        HidProbe ||
        HidAutoProbe ||
        HidActuatorPulse ||
        HidActuatorVibrate ||
        !string.IsNullOrWhiteSpace(HidFeaturePayloadHex) ||
        !string.IsNullOrWhiteSpace(HidOutputPayloadHex) ||
        !string.IsNullOrWhiteSpace(HidWritePayloadHex);
    public bool RequiresHidWriteAccess =>
        HidAutoProbe ||
        HidActuatorPulse ||
        HidActuatorVibrate ||
        !string.IsNullOrWhiteSpace(HidFeaturePayloadHex) ||
        !string.IsNullOrWhiteSpace(HidOutputPayloadHex) ||
        !string.IsNullOrWhiteSpace(HidWritePayloadHex);

    public static ReaderOptions Parse(string[] args)
    {
        ReaderOptions options = new();

        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i];
            switch (arg)
            {
                case "--list":
                    options.ListDevices = true;
                    break;
                case "--hid-probe":
                    options.HidProbe = true;
                    break;
                case "--hid-index" when i + 1 < args.Length:
                    if (!int.TryParse(args[++i], out int hidIndex) || hidIndex < 0)
                    {
                        throw new ArgumentException("--hid-index requires a non-negative integer.");
                    }
                    options.HidDeviceIndex = hidIndex;
                    options.HidIndexSpecified = true;
                    break;
                case "--hid-feature" when i + 1 < args.Length:
                    options.HidFeaturePayloadHex = args[++i];
                    break;
                case "--hid-output" when i + 1 < args.Length:
                    options.HidOutputPayloadHex = args[++i];
                    break;
                case "--hid-write" when i + 1 < args.Length:
                    options.HidWritePayloadHex = args[++i];
                    break;
                case "--hid-repeat" when i + 1 < args.Length:
                    if (!int.TryParse(args[++i], out int hidRepeat) || hidRepeat <= 0)
                    {
                        throw new ArgumentException("--hid-repeat requires a positive integer.");
                    }
                    options.HidRepeat = hidRepeat;
                    break;
                case "--hid-interval-ms" when i + 1 < args.Length:
                    if (!int.TryParse(args[++i], out int hidIntervalMs) || hidIntervalMs < 0)
                    {
                        throw new ArgumentException("--hid-interval-ms requires a non-negative integer.");
                    }
                    options.HidIntervalMs = hidIntervalMs;
                    break;
                case "--hid-auto-probe":
                    options.HidAutoProbe = true;
                    break;
                case "--hid-auto-report-max" when i + 1 < args.Length:
                    if (!int.TryParse(args[++i], out int hidAutoReportMax) || hidAutoReportMax < 0 || hidAutoReportMax > 255)
                    {
                        throw new ArgumentException("--hid-auto-report-max requires an integer in range 0..255.");
                    }
                    options.HidAutoReportMax = hidAutoReportMax;
                    break;
                case "--hid-auto-interval-ms" when i + 1 < args.Length:
                    if (!int.TryParse(args[++i], out int hidAutoIntervalMs) || hidAutoIntervalMs < 0)
                    {
                        throw new ArgumentException("--hid-auto-interval-ms requires a non-negative integer.");
                    }
                    options.HidAutoIntervalMs = hidAutoIntervalMs;
                    break;
                case "--hid-auto-log" when i + 1 < args.Length:
                    options.HidAutoLogPath = args[++i];
                    break;
                case "--hid-actuator-pulse":
                    options.HidActuatorPulse = true;
                    break;
                case "--hid-actuator-vibrate":
                    options.HidActuatorVibrate = true;
                    break;
                case "--hid-actuator-count" when i + 1 < args.Length:
                    if (!int.TryParse(args[++i], out int hidActuatorCount) || hidActuatorCount <= 0)
                    {
                        throw new ArgumentException("--hid-actuator-count requires a positive integer.");
                    }
                    options.HidActuatorCount = hidActuatorCount;
                    break;
                case "--hid-actuator-interval-ms" when i + 1 < args.Length:
                    if (!int.TryParse(args[++i], out int hidActuatorIntervalMs) || hidActuatorIntervalMs < 0)
                    {
                        throw new ArgumentException("--hid-actuator-interval-ms requires a non-negative integer.");
                    }
                    options.HidActuatorIntervalMs = hidActuatorIntervalMs;
                    break;
                case "--hid-actuator-param32" when i + 1 < args.Length:
                    string token = args[++i];
                    if (token.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
                    {
                        token = token.Substring(2);
                    }
                    if (!uint.TryParse(token, System.Globalization.NumberStyles.HexNumber, System.Globalization.CultureInfo.InvariantCulture, out uint param32))
                    {
                        throw new ArgumentException("--hid-actuator-param32 requires a hex uint32 (for example 0x00026C15).");
                    }
                    options.HidActuatorParam32 = param32;
                    break;
                case "--selftest":
                    options.RunSelfTest = true;
                    break;
                case "--maxx" when i + 1 < args.Length:
                    if (!ushort.TryParse(args[++i], out ushort maxX))
                    {
                        throw new ArgumentException("--maxx requires a valid ushort value.");
                    }
                    options.MaxX = maxX;
                    break;
                case "--maxy" when i + 1 < args.Length:
                    if (!ushort.TryParse(args[++i], out ushort maxY))
                    {
                        throw new ArgumentException("--maxy requires a valid ushort value.");
                    }
                    options.MaxY = maxY;
                    break;
                case "--capture" when i + 1 < args.Length:
                    options.CapturePath = args[++i];
                    break;
                case "--replay" when i + 1 < args.Length:
                    options.ReplayPath = args[++i];
                    break;
                case "--replay-ui":
                    options.ReplayInUi = true;
                    break;
                case "--fixture" when i + 1 < args.Length:
                    options.ReplayFixturePath = args[++i];
                    break;
                case "--replay-speed" when i + 1 < args.Length:
                    if (!double.TryParse(args[++i], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double replaySpeed) || replaySpeed <= 0)
                    {
                        throw new ArgumentException("--replay-speed requires a positive number.");
                    }
                    options.ReplaySpeed = replaySpeed;
                    break;
                case "--config":
                    options.StartInConfigUi = true;
                    break;
                case "--relaunch-tray-on-close":
                    options.RelaunchTrayOnClose = true;
                    break;
                case "--metrics-out" when i + 1 < args.Length:
                    options.MetricsOutputPath = args[++i];
                    break;
                case "--replay-trace-out" when i + 1 < args.Length:
                    options.ReplayTraceOutputPath = args[++i];
                    break;
                case "--raw-analyze" when i + 1 < args.Length:
                    options.RawAnalyzePath = args[++i];
                    break;
                case "--raw-analyze-out" when i + 1 < args.Length:
                    options.RawAnalyzeOutputPath = args[++i];
                    break;
                case "--raw-analyze-contacts-out" when i + 1 < args.Length:
                    options.RawAnalyzeContactsOutputPath = args[++i];
                    break;
                case "--decoder-debug":
                    options.DecoderDebug = true;
                    break;
                case "--help":
                case "-h":
                case "/?":
                    throw new ArgumentException("Usage: GlassToKey [--maxx <value>] [--maxy <value>] [--list] [--hid-probe] [--hid-index <n>] [--hid-feature <hex-bytes>] [--hid-output <hex-bytes>] [--hid-write <hex-bytes>] [--hid-repeat <n>] [--hid-interval-ms <ms>] [--hid-auto-probe] [--hid-auto-report-max <0..255>] [--hid-auto-interval-ms <ms>] [--hid-auto-log <path>] [--hid-actuator-pulse] [--hid-actuator-vibrate] [--hid-actuator-count <n>] [--hid-actuator-interval-ms <ms>] [--hid-actuator-param32 <hex>] [--capture <path>] [--replay <capturePath>] [--replay-ui] [--replay-speed <x>] [--fixture <fixturePath>] [--selftest] [--metrics-out <path>] [--replay-trace-out <path>] [--raw-analyze <capturePath>] [--raw-analyze-out <path>] [--raw-analyze-contacts-out <path>] [--decoder-debug] [--config] [--relaunch-tray-on-close]");
                default:
                    break;
            }
        }

        return options;
    }
}
