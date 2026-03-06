using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Controls;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using System.Linq;
using GlassToKey.Linux.Runtime;

namespace GlassToKey.Linux.Gui;

public partial class App : Application
{
    private MainWindow? _mainWindow;
    private NativeMenuItem? _captureAtpCapMenuItem;
    private NativeMenuItem? _replayAtpCapMenuItem;
    private readonly LinuxGuiActivationSignalStore _activationSignalStore = new();
    private DispatcherTimer? _activationTimer;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
        ResolveTrayMenuItems();
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            _mainWindow = new MainWindow(LinuxDesktopRuntimeEnvironment.SharedController);
            _mainWindow.CaptureStateChanged += OnMainWindowCaptureStateChanged;
            if (Program.OwnsRuntime)
            {
                _mainWindow.BeginTrayRuntimeOwnership();
            }
            UpdateTrayCaptureState(_mainWindow.IsCapturingAtpCap);
            StartActivationPolling();
            if (!Program.StartHidden)
            {
                desktop.MainWindow = _mainWindow;
                ShowMainWindow();
            }
        }

        base.OnFrameworkInitializationCompleted();
    }

    private void OnTrayIconClicked(object? sender, EventArgs e)
    {
        ShowMainWindow();
    }

    private void OnTrayOpenClick(object? sender, EventArgs e)
    {
        ShowMainWindow();
    }

    private void OnTrayDoctorClick(object? sender, EventArgs e)
    {
        _mainWindow?.RunDoctorFromStatusArea();
    }

    private async void OnTrayCaptureAtpCapClick(object? sender, EventArgs e)
    {
        if (_mainWindow != null)
        {
            ShowMainWindow();
            await _mainWindow.CaptureAtpCapFromStatusAreaAsync();
            UpdateTrayCaptureState(_mainWindow.IsCapturingAtpCap);
        }
    }

    private async void OnTrayReplayAtpCapClick(object? sender, EventArgs e)
    {
        if (_mainWindow != null)
        {
            if (_mainWindow.IsCapturingAtpCap)
            {
                return;
            }

            ShowMainWindow();
            await _mainWindow.ReplayAtpCapFromStatusAreaAsync();
        }
    }

    private async void OnTrayQuitClick(object? sender, EventArgs e)
    {
        if (_mainWindow != null)
        {
            await _mainWindow.RequestExitAsync();
        }

        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.Shutdown();
        }
    }

    private void ShowMainWindow()
    {
        if (_mainWindow == null)
        {
            return;
        }

        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop && desktop.MainWindow != _mainWindow)
        {
            desktop.MainWindow = _mainWindow;
        }

        if (!_mainWindow.IsVisible)
        {
            _mainWindow.Show();
        }

        _mainWindow.WindowState = WindowState.Normal;
        _mainWindow.EnsurePreviewActive();
        _mainWindow.Activate();
    }

    private void OnMainWindowCaptureStateChanged(bool isCapturing)
    {
        UpdateTrayCaptureState(isCapturing);
    }

    private void UpdateTrayCaptureState(bool isCapturing)
    {
        ResolveTrayMenuItems();
        if (_captureAtpCapMenuItem != null)
        {
            _captureAtpCapMenuItem.Header = isCapturing ? "Stop Capture" : "Capture .atpcap";
        }

        if (_replayAtpCapMenuItem != null)
        {
            _replayAtpCapMenuItem.IsEnabled = !isCapturing;
        }
    }

    private void ResolveTrayMenuItems()
    {
        if (_captureAtpCapMenuItem != null && _replayAtpCapMenuItem != null)
        {
            return;
        }

        TrayIcons? icons = TrayIcon.GetIcons(this);
        if (icons == null || icons.Count == 0 || icons[0] is not TrayIcon trayIcon || trayIcon.Menu is not NativeMenu menu)
        {
            return;
        }

        _captureAtpCapMenuItem = menu.Items.OfType<NativeMenuItem>().FirstOrDefault(item =>
            string.Equals(item.Header?.ToString(), "Capture .atpcap", StringComparison.Ordinal) ||
            string.Equals(item.Header?.ToString(), "Stop Capture", StringComparison.Ordinal));
        _replayAtpCapMenuItem = menu.Items.OfType<NativeMenuItem>().FirstOrDefault(item =>
            string.Equals(item.Header?.ToString(), "Replay .atpcap", StringComparison.Ordinal));
    }

    private void StartActivationPolling()
    {
        if (_activationTimer != null)
        {
            return;
        }

        _activationTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(500)
        };
        _activationTimer.Tick += (_, _) =>
        {
            if (_activationSignalStore.TryConsumeShowRequest())
            {
                ShowMainWindow();
            }
        };
        _activationTimer.Start();

        if (_activationSignalStore.TryConsumeShowRequest())
        {
            ShowMainWindow();
        }
    }
}
