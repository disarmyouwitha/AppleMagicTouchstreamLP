using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Controls;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using System.Linq;
using GlassToKey.Linux.Config;
using GlassToKey.Linux.Runtime;

namespace GlassToKey.Linux.Gui;

internal enum LinuxTrayModeIndicator : byte
{
    Unknown = 0,
    Mouse = 1,
    Mixed = 2,
    Keyboard = 3,
    LayerActive = 4
}

public partial class App : Application
{
    private readonly LinuxDesktopRuntimeController _desktopRuntime = LinuxDesktopRuntimeEnvironment.SharedController;
    private readonly WindowIcon _iconUnknown = TrayModeIconFactory.CreateUnknown();
    private readonly WindowIcon _iconMouse = TrayModeIconFactory.CreateMouse();
    private readonly WindowIcon _iconMixed = TrayModeIconFactory.CreateMixed();
    private readonly WindowIcon _iconKeyboard = TrayModeIconFactory.CreateKeyboard();
    private readonly WindowIcon _iconLayerActive = TrayModeIconFactory.CreateLayerActive();
    private MainWindow? _mainWindow;
    private TrayIcon? _trayIcon;
    private NativeMenuItem? _captureAtpCapMenuItem;
    private NativeMenuItem? _replayAtpCapMenuItem;
    private readonly LinuxGuiActivationSignalStore _activationSignalStore = new();
    private DispatcherTimer? _activationTimer;
    private LinuxTrayModeIndicator _currentModeIndicator = LinuxTrayModeIndicator.Unknown;
    private bool _hasAppliedTrayModeIndicator;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
        ResolveTrayMenuItems();
        ApplyTrayModeIndicator(_desktopRuntime.RuntimeSnapshot);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            _mainWindow = new MainWindow(_desktopRuntime);
            _mainWindow.CaptureStateChanged += OnMainWindowCaptureStateChanged;
            _desktopRuntime.RuntimeSnapshotChanged += OnRuntimeSnapshotChanged;
            if (Program.OwnsRuntime)
            {
                _mainWindow.BeginTrayRuntimeOwnership();
            }
            UpdateTrayCaptureState(_mainWindow.IsCapturingAtpCap);
            StartActivationPolling();
            LinuxHostSettings settings = new LinuxAppRuntime().LoadSettings();
            bool startHiddenFromSettings = settings.GetSharedProfile().StartInTrayOnLaunch;
            bool startHidden = Program.StartHidden || (!Program.ShowRequested && startHiddenFromSettings);
            if (!startHidden)
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
        if (_trayIcon != null && _captureAtpCapMenuItem != null && _replayAtpCapMenuItem != null)
        {
            return;
        }

        TrayIcons? icons = TrayIcon.GetIcons(this);
        if (icons == null || icons.Count == 0 || icons[0] is not TrayIcon trayIcon || trayIcon.Menu is not NativeMenu menu)
        {
            return;
        }

        _trayIcon = trayIcon;
        _captureAtpCapMenuItem = menu.Items.OfType<NativeMenuItem>().FirstOrDefault(item =>
            string.Equals(item.Header?.ToString(), "Capture .atpcap", StringComparison.Ordinal) ||
            string.Equals(item.Header?.ToString(), "Stop Capture", StringComparison.Ordinal));
        _replayAtpCapMenuItem = menu.Items.OfType<NativeMenuItem>().FirstOrDefault(item =>
            string.Equals(item.Header?.ToString(), "Replay .atpcap", StringComparison.Ordinal));
    }

    private void OnRuntimeSnapshotChanged(LinuxDesktopRuntimeSnapshot snapshot)
    {
        if (!Dispatcher.UIThread.CheckAccess())
        {
            Dispatcher.UIThread.Post(() => ApplyTrayModeIndicator(snapshot));
            return;
        }

        ApplyTrayModeIndicator(snapshot);
    }

    private void ApplyTrayModeIndicator(LinuxDesktopRuntimeSnapshot snapshot)
    {
        ResolveTrayMenuItems();
        if (_trayIcon == null)
        {
            return;
        }

        LinuxTrayModeIndicator mode = ToModeIndicator(snapshot);
        if (_hasAppliedTrayModeIndicator && _currentModeIndicator == mode)
        {
            return;
        }

        _hasAppliedTrayModeIndicator = true;
        _currentModeIndicator = mode;
        _trayIcon.Icon = mode switch
        {
            LinuxTrayModeIndicator.Mouse => _iconMouse,
            LinuxTrayModeIndicator.Mixed => _iconMixed,
            LinuxTrayModeIndicator.Keyboard => _iconKeyboard,
            LinuxTrayModeIndicator.LayerActive => _iconLayerActive,
            _ => _iconUnknown
        };
        _trayIcon.ToolTipText = mode switch
        {
            LinuxTrayModeIndicator.Mouse => "GlassToKey Linux (Mouse)",
            LinuxTrayModeIndicator.Mixed => "GlassToKey Linux (Mixed)",
            LinuxTrayModeIndicator.Keyboard => "GlassToKey Linux (Keyboard)",
            LinuxTrayModeIndicator.LayerActive => "GlassToKey Linux (Layer Active)",
            _ => "GlassToKey Linux (Unknown)"
        };
    }

    private static LinuxTrayModeIndicator ToModeIndicator(LinuxDesktopRuntimeSnapshot snapshot)
    {
        if (snapshot.Status != LinuxDesktopRuntimeStatus.Running)
        {
            return LinuxTrayModeIndicator.Unknown;
        }

        if (snapshot.ActiveLayer > 0)
        {
            return LinuxTrayModeIndicator.LayerActive;
        }

        if (!snapshot.TypingEnabled)
        {
            return LinuxTrayModeIndicator.Mouse;
        }

        return snapshot.KeyboardModeEnabled
            ? LinuxTrayModeIndicator.Keyboard
            : LinuxTrayModeIndicator.Mixed;
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
