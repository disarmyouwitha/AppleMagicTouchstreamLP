using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using WinForms = System.Windows.Forms;

namespace GlassToKey;

public partial class App : Application
{
    private TouchRuntimeService? _runtimeService;
    private StatusTrayController? _trayController;
    private MainWindow? _configWindow;
    private ReaderOptions? _startupOptions;
    private bool _restartRequested;

    protected override void OnStartup(StartupEventArgs e)
    {
        bool showErrorDialogs = ShouldShowErrorDialogs(e.Args);
        DispatcherUnhandledException += (_, args) =>
        {
            RuntimeFaultLogger.LogException("App.DispatcherUnhandledException", args.Exception);
            if (showErrorDialogs)
            {
                MessageBox.Show(args.Exception.ToString(), "GlassToKey Crash", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            else
            {
                Console.Error.WriteLine(args.Exception);
            }

            args.Handled = true;
            Shutdown(1);
        };

        base.OnStartup(e);

        ReaderOptions options;
        try
        {
            options = ReaderOptions.Parse(e.Args);
        }
        catch (ArgumentException ex)
        {
            if (showErrorDialogs)
            {
                MessageBox.Show(ex.Message, "GlassToKey", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            else
            {
                Console.Error.WriteLine(ex.Message);
            }

            Shutdown(2);
            return;
        }

        if (options.ListDevices)
        {
            HidDeviceInfo[] devices = RawInputInterop.EnumerateTrackpads();
            string message = devices.Length == 0
                ? "No trackpads detected."
                : string.Join(Environment.NewLine, devices.Select(d => $"{d.DisplayName} :: {d.Path}"));
            foreach (HidDeviceInfo device in devices)
            {
                Console.WriteLine($"{device.DisplayName} :: {device.Path}");
            }
            if (devices.Length == 0)
            {
                Console.WriteLine(message);
            }
            Shutdown(0);
            return;
        }

        if (options.RunSelfTest)
        {
            SelfTestResult result = SelfTestRunner.Run();
            Console.WriteLine(result.Summary);
            Shutdown(result.Success ? 0 : 3);
            return;
        }

        if (!string.IsNullOrWhiteSpace(options.RawAnalyzePath))
        {
            try
            {
                string inputPath = Path.GetFullPath(options.RawAnalyzePath);
                string? contactOutputPath = string.IsNullOrWhiteSpace(options.RawAnalyzeContactsOutputPath)
                    ? null
                    : Path.GetFullPath(options.RawAnalyzeContactsOutputPath);
                RawCaptureAnalysisResult result = RawCaptureAnalyzer.Analyze(inputPath, contactOutputPath);
                Console.WriteLine(result.ToSummary());
                if (!string.IsNullOrWhiteSpace(options.RawAnalyzeOutputPath))
                {
                    string outputPath = Path.GetFullPath(options.RawAnalyzeOutputPath);
                    result.WriteJson(outputPath);
                }

                Shutdown(0);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                Shutdown(7);
            }

            return;
        }

        if (!string.IsNullOrWhiteSpace(options.ReplayPath) && !options.ReplayInUi)
        {
            try
            {
                string replayPath = Path.GetFullPath(options.ReplayPath);
                string? fixturePath = string.IsNullOrWhiteSpace(options.ReplayFixturePath) ? null : Path.GetFullPath(options.ReplayFixturePath);
                string? replayTracePath = string.IsNullOrWhiteSpace(options.ReplayTraceOutputPath) ? null : Path.GetFullPath(options.ReplayTraceOutputPath);
                ReplayRunner replay = new();
                ReplayRunResult result = replay.Run(replayPath, fixturePath, replayTracePath);
                string summary = result.ToSummary();
                Console.WriteLine(summary);
                if (!string.IsNullOrWhiteSpace(options.MetricsOutputPath))
                {
                    string outputPath = Path.GetFullPath(options.MetricsOutputPath);
                    result.FirstPass.Metrics.WriteSnapshotJson(outputPath);
                }

                Shutdown(result.Success ? 0 : 4);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                Shutdown(5);
            }
            return;
        }

        bool useLegacyWindowRuntime =
            (options.ReplayInUi && !string.IsNullOrWhiteSpace(options.ReplayPath)) ||
            !string.IsNullOrWhiteSpace(options.CapturePath);
        if (useLegacyWindowRuntime)
        {
            MainWindow window = new MainWindow(options);
            MainWindow = window;
            if (options.RelaunchTrayOnClose)
            {
                window.Closed += (_, _) =>
                {
                    _ = TryLaunchReplacementInstance(showErrors: true);
                };
            }
            window.Show();
            return;
        }

        _startupOptions = options;
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        _runtimeService = new TouchRuntimeService(options);
        if (!_runtimeService.Start(out string? runtimeError))
        {
            string message = string.IsNullOrWhiteSpace(runtimeError)
                ? "Failed to start tray runtime."
                : runtimeError;
            if (showErrorDialogs)
            {
                MessageBox.Show(message, "GlassToKey", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            else
            {
                Console.Error.WriteLine(message);
            }

            Shutdown(6);
            return;
        }

        _trayController = new StatusTrayController(
            OpenConfigWindow,
            StartCaptureFromTray,
            StartReplayFromTray,
            RestartApplicationFromTray,
            ExitApplicationFromTray);
        _trayController.SetModeIndicator(_runtimeService.GetCurrentModeIndicator());
        _runtimeService.ModeIndicatorChanged += OnRuntimeModeIndicatorChanged;
        if (options.StartInConfigUi)
        {
            OpenConfigWindow();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (_runtimeService != null)
        {
            _runtimeService.ModeIndicatorChanged -= OnRuntimeModeIndicatorChanged;
        }
        _trayController?.Dispose();
        _trayController = null;
        _runtimeService?.Dispose();
        _runtimeService = null;
        MagicTrackpadActuatorHaptics.Dispose();
        base.OnExit(e);
    }

    private void OpenConfigWindow()
    {
        if (_startupOptions == null)
        {
            return;
        }

        if (_configWindow == null)
        {
            _configWindow = new MainWindow(_startupOptions, _runtimeService);
            MainWindow = _configWindow;
            _configWindow.Closed += (_, _) =>
            {
                if (ReferenceEquals(MainWindow, _configWindow))
                {
                    MainWindow = null;
                }
                _configWindow = null;
            };
        }

        if (!_configWindow.IsVisible)
        {
            _configWindow.Show();
        }

        if (_configWindow.WindowState == WindowState.Minimized)
        {
            _configWindow.WindowState = WindowState.Normal;
        }

        _configWindow.Activate();
    }

    private void ExitApplicationFromTray()
    {
        _configWindow?.Close();
        _configWindow = null;
        Shutdown(0);
    }

    private void StartCaptureFromTray()
    {
        using WinForms.SaveFileDialog dialog = new()
        {
            Title = "Capture Output",
            Filter = "Trackpad Capture (*.atpcap)|*.atpcap|All files (*.*)|*.*",
            DefaultExt = "atpcap",
            AddExtension = true,
            OverwritePrompt = true,
            FileName = $"capture-{DateTime.Now:yyyyMMdd-HHmmss}.atpcap",
            InitialDirectory = ResolveReplayArtifactsDirectory()
        };

        if (dialog.ShowDialog() != WinForms.DialogResult.OK || string.IsNullOrWhiteSpace(dialog.FileName))
        {
            return;
        }

        RestartApplicationWithArgs("--capture", dialog.FileName, "--relaunch-tray-on-close");
    }

    private void StartReplayFromTray()
    {
        using WinForms.OpenFileDialog dialog = new()
        {
            Title = "Replay Capture",
            Filter = "Trackpad Capture (*.atpcap)|*.atpcap|All files (*.*)|*.*",
            CheckFileExists = true,
            Multiselect = false,
            InitialDirectory = ResolveReplayArtifactsDirectory()
        };

        if (dialog.ShowDialog() != WinForms.DialogResult.OK || string.IsNullOrWhiteSpace(dialog.FileName))
        {
            return;
        }

        RestartApplicationWithArgs("--replay", dialog.FileName, "--replay-ui", "--relaunch-tray-on-close");
    }

    private void RestartApplicationFromTray()
    {
        RestartApplicationWithArgs();
    }

    private void RestartApplicationWithArgs(params string[] args)
    {
        if (TryLaunchReplacementInstance(showErrors: true, args: args))
        {
            ExitApplicationFromTray();
        }
    }

    private bool TryLaunchReplacementInstance(bool showErrors, params string[] args)
    {
        if (_restartRequested)
        {
            return false;
        }

        if (!TryBuildRestartStartInfo(out ProcessStartInfo startInfo))
        {
            if (showErrors)
            {
                MessageBox.Show("Unable to determine executable path for restart.", "GlassToKey", MessageBoxButton.OK, MessageBoxImage.Error);
            }

            return false;
        }

        for (int i = 0; i < args.Length; i++)
        {
            startInfo.ArgumentList.Add(args[i]);
        }

        try
        {
            Process.Start(startInfo);
            _restartRequested = true;
            return true;
        }
        catch (Exception ex)
        {
            if (showErrors)
            {
                MessageBox.Show(ex.Message, "GlassToKey", MessageBoxButton.OK, MessageBoxImage.Error);
            }

            return false;
        }
    }

    private static bool TryBuildRestartStartInfo(out ProcessStartInfo startInfo)
    {
        string? processPath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(processPath))
        {
            startInfo = new ProcessStartInfo();
            return false;
        }

        startInfo = new ProcessStartInfo
        {
            FileName = processPath,
            WorkingDirectory = AppContext.BaseDirectory,
            UseShellExecute = false
        };

        if (string.Equals(Path.GetFileNameWithoutExtension(processPath), "dotnet", StringComparison.OrdinalIgnoreCase))
        {
            string assemblyPath = typeof(App).Assembly.Location;
            if (string.IsNullOrWhiteSpace(assemblyPath))
            {
                startInfo = new ProcessStartInfo();
                return false;
            }

            startInfo.ArgumentList.Add(assemblyPath);
        }

        return true;
    }

    private static string ResolveReplayArtifactsDirectory()
    {
        string fixturesReplay = Path.Combine(AppContext.BaseDirectory, "fixtures", "replay");
        if (Directory.Exists(fixturesReplay))
        {
            return fixturesReplay;
        }

        string localAppData = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "GlassToKey");
        if (!Directory.Exists(localAppData))
        {
            Directory.CreateDirectory(localAppData);
        }

        return localAppData;
    }

    private void OnRuntimeModeIndicatorChanged(RuntimeModeIndicator mode)
    {
        _ = Dispatcher.BeginInvoke(() =>
        {
            _trayController?.SetModeIndicator(mode);
        });
    }

    private static bool ShouldShowErrorDialogs(string[] args)
    {
        bool hasReplay = args.Any(arg => string.Equals(arg, "--replay", StringComparison.OrdinalIgnoreCase));
        bool replayInUi = args.Any(arg => string.Equals(arg, "--replay-ui", StringComparison.OrdinalIgnoreCase));
        bool listOnly = args.Any(arg => string.Equals(arg, "--list", StringComparison.OrdinalIgnoreCase));
        bool selfTestOnly = args.Any(arg => string.Equals(arg, "--selftest", StringComparison.OrdinalIgnoreCase));
        bool rawAnalyzeOnly = args.Any(arg => string.Equals(arg, "--raw-analyze", StringComparison.OrdinalIgnoreCase));
        return !(listOnly || selfTestOnly || rawAnalyzeOnly || (hasReplay && !replayInUi));
    }
}
