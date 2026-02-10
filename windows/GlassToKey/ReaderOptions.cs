using System;

namespace GlassToKey;

public sealed class ReaderOptions
{
    public bool ListDevices { get; private set; }
    public bool RunSelfTest { get; private set; }
    public ushort? MaxX { get; private set; }
    public ushort? MaxY { get; private set; }
    public string? CapturePath { get; private set; }
    public string? ReplayPath { get; private set; }
    public string? ReplayFixturePath { get; private set; }
    public string? MetricsOutputPath { get; private set; }
    public string? ReplayTraceOutputPath { get; private set; }
    public bool ReplayInUi { get; private set; }
    public double ReplaySpeed { get; private set; } = 1.0;
    public bool StartInConfigUi { get; private set; }

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
                case "--metrics-out" when i + 1 < args.Length:
                    options.MetricsOutputPath = args[++i];
                    break;
                case "--replay-trace-out" when i + 1 < args.Length:
                    options.ReplayTraceOutputPath = args[++i];
                    break;
                case "--help":
                case "-h":
                case "/?":
                    throw new ArgumentException("Usage: GlassToKey [--maxx <value>] [--maxy <value>] [--list] [--capture <path>] [--replay <capturePath>] [--replay-ui] [--replay-speed <x>] [--fixture <fixturePath>] [--selftest] [--metrics-out <path>] [--replay-trace-out <path>] [--config]");
                default:
                    break;
            }
        }

        return options;
    }
}
