using System.Diagnostics;
namespace GlassToKey.Linux.Runtime;

public sealed class LinuxSystemdServiceController
{
    private const string SystemctlExecutable = "systemctl";
    private const string UnitPattern = "*glasstokey*.service";

    public IReadOnlyList<LinuxSystemdServiceStatus> Query()
    {
        CommandResult unitsResult = RunSystemctl(
            "--user",
            "--plain",
            "--no-legend",
            "--type=service",
            "--all",
            "--full",
            "list-units",
            UnitPattern);
        if (!unitsResult.Success)
        {
            return Array.Empty<LinuxSystemdServiceStatus>();
        }

        List<string> units = ParseUnitNames(unitsResult.StandardOutput);
        if (units.Count == 0)
        {
            return Array.Empty<LinuxSystemdServiceStatus>();
        }

        List<LinuxSystemdServiceStatus> statuses = new(units.Count);
        foreach (string unit in units)
        {
            statuses.Add(QueryUnit(unit));
        }

        return statuses;
    }

    public async Task<IReadOnlyList<LinuxSystemdServiceStatus>> StopAsync(CancellationToken cancellationToken = default)
    {
        IReadOnlyList<LinuxSystemdServiceStatus> current = Query();
        string[] runningUnits = [.. current.Where(static status => status.IsRunning).Select(static status => status.UnitName)];
        if (runningUnits.Length == 0)
        {
            return Array.Empty<LinuxSystemdServiceStatus>();
        }

        List<string> stopArguments =
        [
            "--user",
            "stop"
        ];
        stopArguments.AddRange(runningUnits);

        CommandResult stopResult = await RunSystemctlAsync(stopArguments, cancellationToken).ConfigureAwait(false);
        Dictionary<string, LinuxSystemdServiceStatus> refreshed = Query()
            .ToDictionary(static status => status.UnitName, StringComparer.OrdinalIgnoreCase);
        List<LinuxSystemdServiceStatus> statuses = new(runningUnits.Length);
        foreach (string unit in runningUnits)
        {
            if (refreshed.TryGetValue(unit, out LinuxSystemdServiceStatus? status))
            {
                statuses.Add(status with
                {
                    Message = status.IsRunning
                        ? BuildFailureMessage(unit, stopResult)
                        : $"The user service {unit} has stopped."
                });
                continue;
            }

            statuses.Add(new LinuxSystemdServiceStatus(
                unit,
                IsRunning: false,
                ProcessId: null,
                ActiveState: "inactive",
                SubState: "dead",
                Message: $"The user service {unit} has stopped."));
        }

        return statuses;
    }

    private LinuxSystemdServiceStatus QueryUnit(string unitName)
    {
        CommandResult showResult = RunSystemctl(
            "--user",
            "show",
            unitName,
            "-p",
            "Id",
            "-p",
            "ActiveState",
            "-p",
            "SubState",
            "-p",
            "MainPID");
        if (!showResult.Success)
        {
            return new LinuxSystemdServiceStatus(
                unitName,
                IsRunning: false,
                ProcessId: null,
                ActiveState: "unknown",
                SubState: "unknown",
                Message: $"Could not inspect user service {unitName}.");
        }

        Dictionary<string, string> properties = ParseProperties(showResult.StandardOutput);
        string activeState = GetProperty(properties, "ActiveState", "unknown");
        string subState = GetProperty(properties, "SubState", "unknown");
        int? processId = TryParseProcessId(GetProperty(properties, "MainPID", "0"));
        bool isRunning = string.Equals(activeState, "active", StringComparison.OrdinalIgnoreCase) &&
                         !string.Equals(subState, "dead", StringComparison.OrdinalIgnoreCase) &&
                         !string.Equals(subState, "failed", StringComparison.OrdinalIgnoreCase);

        string message = isRunning
            ? processId.HasValue
                ? $"The user service {unitName} is running as PID {processId.Value}."
                : $"The user service {unitName} is running."
            : $"The user service {unitName} is not running.";
        return new LinuxSystemdServiceStatus(unitName, isRunning, processId, activeState, subState, message);
    }

    private static string BuildFailureMessage(string unitName, CommandResult stopResult)
    {
        if (!string.IsNullOrWhiteSpace(stopResult.StandardError))
        {
            return $"The user service {unitName} did not stop: {stopResult.StandardError.Trim()}";
        }

        return $"The user service {unitName} did not stop.";
    }

    private static List<string> ParseUnitNames(string stdout)
    {
        List<string> units = new();
        using StringReader reader = new(stdout);
        while (reader.ReadLine() is { } line)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            string[] parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0)
            {
                continue;
            }

            string unitName = parts[0];
            if (!unitName.EndsWith(".service", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            units.Add(unitName);
        }

        return units;
    }

    private static Dictionary<string, string> ParseProperties(string stdout)
    {
        Dictionary<string, string> properties = new(StringComparer.OrdinalIgnoreCase);
        using StringReader reader = new(stdout);
        while (reader.ReadLine() is { } line)
        {
            int separator = line.IndexOf('=');
            if (separator <= 0)
            {
                continue;
            }

            string key = line[..separator].Trim();
            string value = line[(separator + 1)..].Trim();
            properties[key] = value;
        }

        return properties;
    }

    private static string GetProperty(IReadOnlyDictionary<string, string> properties, string key, string fallback)
    {
        return properties.TryGetValue(key, out string? value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : fallback;
    }

    private static int? TryParseProcessId(string value)
    {
        if (!int.TryParse(value, out int processId) || processId <= 0)
        {
            return null;
        }

        return processId;
    }

    private static CommandResult RunSystemctl(params string[] arguments)
    {
        using Process process = CreateSystemctlProcess(arguments);
        try
        {
            process.Start();
        }
        catch
        {
            return CommandResult.Failure;
        }

        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();
        return new CommandResult(process.ExitCode == 0, stdout, stderr);
    }

    private static async Task<CommandResult> RunSystemctlAsync(
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        using Process process = CreateSystemctlProcess(arguments);
        try
        {
            process.Start();
        }
        catch
        {
            return CommandResult.Failure;
        }

        Task<string> stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        Task<string> stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        string stdout = await stdoutTask.ConfigureAwait(false);
        string stderr = await stderrTask.ConfigureAwait(false);
        return new CommandResult(process.ExitCode == 0, stdout, stderr);
    }

    private static Process CreateSystemctlProcess(IReadOnlyList<string> arguments)
    {
        ProcessStartInfo startInfo = new()
        {
            FileName = SystemctlExecutable,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        foreach (string argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        return new Process
        {
            StartInfo = startInfo
        };
    }

    private readonly record struct CommandResult(
        bool Success,
        string StandardOutput,
        string StandardError)
    {
        public static CommandResult Failure => new(false, string.Empty, string.Empty);
    }
}
