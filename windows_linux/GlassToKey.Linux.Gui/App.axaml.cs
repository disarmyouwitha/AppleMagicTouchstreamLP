using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Controls;
using Avalonia.Markup.Xaml;
using GlassToKey.Linux.Runtime;

namespace GlassToKey.Linux.Gui;

public partial class App : Application
{
    private MainWindow? _mainWindow;

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            _mainWindow = new MainWindow(LinuxDesktopRuntimeEnvironment.SharedController);
            desktop.MainWindow = _mainWindow;
            _mainWindow.BeginTrayRuntimeOwnership();
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
        }
    }

    private async void OnTrayStopAtpCapClick(object? sender, EventArgs e)
    {
        if (_mainWindow != null)
        {
            await _mainWindow.StopAtpCapFromStatusAreaAsync();
        }
    }

    private async void OnTrayReplayAtpCapClick(object? sender, EventArgs e)
    {
        if (_mainWindow != null)
        {
            await _mainWindow.ReplayAtpCapFromStatusAreaAsync();
        }
    }

    private async void OnTraySummarizeAtpCapClick(object? sender, EventArgs e)
    {
        if (_mainWindow != null)
        {
            await _mainWindow.SummarizeAtpCapFromStatusAreaAsync();
        }
    }

    private void OnTrayHideClick(object? sender, EventArgs e)
    {
        _mainWindow?.HideToStatusArea();
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

        if (!_mainWindow.IsVisible)
        {
            _mainWindow.Show();
        }

        _mainWindow.WindowState = WindowState.Normal;
        _mainWindow.EnsurePreviewActive();
        _mainWindow.Activate();
    }
}
