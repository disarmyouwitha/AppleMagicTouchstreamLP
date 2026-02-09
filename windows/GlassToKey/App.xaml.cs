using System;
using System.IO;
using System.Linq;
using System.Windows;

namespace GlassToKey;

public partial class App : Application
{
    private TouchRuntimeService? _runtimeService;
    private StatusTrayController? _trayController;
    private MainWindow? _configWindow;
    private ReaderOptions? _startupOptions;

    protected override void OnStartup(StartupEventArgs e)
    {
        bool showErrorDialogs = ShouldShowErrorDialogs(e.Args);
        DispatcherUnhandledException += (_, args) =>
        {
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

        _trayController = new StatusTrayController(OpenConfigWindow, ExitApplicationFromTray);
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
        return !(listOnly || selfTestOnly || (hasReplay && !replayInUi));
    }
}
