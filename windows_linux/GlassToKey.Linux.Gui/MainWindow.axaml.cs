using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using GlassToKey.Linux;
using GlassToKey.Linux.Config;
using GlassToKey.Linux.Runtime;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Gui;

public partial class MainWindow : Window
{
    private readonly LinuxAppRuntime _runtime = new();
    private readonly LinuxEngineRuntimeController _runtimeController = new();
    private readonly ComboBox _leftDeviceCombo;
    private readonly ComboBox _rightDeviceCombo;
    private readonly ComboBox _layoutPresetCombo;
    private readonly TextBox _keymapPathBox;
    private readonly TextBlock _keymapStatusText;
    private readonly TextBlock _runtimeSummaryText;
    private readonly TextBlock _runtimeBindingsText;
    private readonly TextBlock _settingsPathText;
    private readonly TextBlock _resolvedBindingsText;
    private readonly TextBlock _warningsText;
    private readonly TextBlock _statusText;
    private readonly TextBox _doctorReportBox;
    private bool _allowExit;

    public MainWindow()
    {
        InitializeComponent();
        _leftDeviceCombo = RequireControl<ComboBox>("LeftDeviceCombo");
        _rightDeviceCombo = RequireControl<ComboBox>("RightDeviceCombo");
        _layoutPresetCombo = RequireControl<ComboBox>("LayoutPresetCombo");
        _keymapPathBox = RequireControl<TextBox>("KeymapPathBox");
        _keymapStatusText = RequireControl<TextBlock>("KeymapStatusText");
        _runtimeSummaryText = RequireControl<TextBlock>("RuntimeSummaryText");
        _runtimeBindingsText = RequireControl<TextBlock>("RuntimeBindingsText");
        _settingsPathText = RequireControl<TextBlock>("SettingsPathText");
        _resolvedBindingsText = RequireControl<TextBlock>("ResolvedBindingsText");
        _warningsText = RequireControl<TextBlock>("WarningsText");
        _statusText = RequireControl<TextBlock>("StatusText");
        _doctorReportBox = RequireControl<TextBox>("DoctorReportBox");
        _runtimeController.SnapshotChanged += OnRuntimeSnapshotChanged;
        Closing += OnWindowClosing;
        WireEvents();
        LoadScreen();
        ApplyRuntimeSnapshot(_runtimeController.Snapshot);
    }

    private void InitializeComponent()
    {
        AvaloniaXamlLoader.Load(this);
    }

    private void WireEvents()
    {
        RequireControl<Button>("RefreshDevicesButton").Click += OnRefreshDevicesClick;
        RequireControl<Button>("SwapSidesButton").Click += OnSwapSidesClick;
        RequireControl<Button>("StartRuntimeButton").Click += OnStartRuntimeClick;
        RequireControl<Button>("StopRuntimeButton").Click += OnStopRuntimeClick;
        RequireControl<Button>("SaveSettingsButton").Click += OnSaveSettingsClick;
        RequireControl<Button>("InitializeDefaultsButton").Click += OnInitializeDefaultsClick;
        RequireControl<Button>("BrowseKeymapButton").Click += OnBrowseKeymapClick;
        RequireControl<Button>("ClearKeymapButton").Click += OnClearKeymapClick;
        RequireControl<Button>("RunDoctorButton").Click += OnRunDoctorClick;
    }

    private void LoadScreen(string? statusOverride = null)
    {
        LinuxRuntimeConfiguration configuration = _runtime.LoadConfiguration();
        LinuxHostSettings settings = configuration.Settings;

        List<DeviceChoice> deviceChoices = BuildDeviceChoices(configuration.Devices);
        DeviceChoice autoChoice = deviceChoices[0];
        _leftDeviceCombo.ItemsSource = deviceChoices;
        _rightDeviceCombo.ItemsSource = deviceChoices;
        _leftDeviceCombo.SelectedItem = SelectDeviceChoice(deviceChoices, settings.LeftTrackpadStableId) ?? autoChoice;
        _rightDeviceCombo.SelectedItem = SelectDeviceChoice(deviceChoices, settings.RightTrackpadStableId) ?? autoChoice;

        List<PresetChoice> presetChoices = BuildPresetChoices();
        _layoutPresetCombo.ItemsSource = presetChoices;
        _layoutPresetCombo.SelectedItem = SelectPresetChoice(presetChoices, settings.LayoutPresetName) ?? presetChoices[0];
        _keymapPathBox.Text = settings.KeymapPath ?? string.Empty;
        _keymapStatusText.Text = BuildKeymapStatusText(settings.KeymapPath);

        _settingsPathText.Text = $"Settings: {configuration.SettingsPath}";
        _resolvedBindingsText.Text = BuildResolvedBindingsText(configuration);
        _warningsText.Text = configuration.Warnings.Count == 0
            ? "No current warnings."
            : string.Join(Environment.NewLine, configuration.Warnings);
        _statusText.Text = statusOverride ?? $"Detected {configuration.Devices.Count} candidate trackpad(s). Save writes directly to the XDG-backed Linux settings file.";
        if (_runtimeController.Snapshot.IsActive)
        {
            _statusText.Text += " Restart the runtime to apply setting changes.";
        }

        if (string.IsNullOrWhiteSpace(_doctorReportBox.Text))
        {
            _doctorReportBox.Text = "Run Doctor to validate evdev, uinput, bundled keymap, and current device bindings.";
        }
    }

    private void OnRefreshDevicesClick(object? sender, RoutedEventArgs e)
    {
        LoadScreen("Device list refreshed from the current Linux evdev state.");
    }

    private void OnSwapSidesClick(object? sender, RoutedEventArgs e)
    {
        string path = _runtime.SwapTrackpadBindings();
        LoadScreen($"Swapped left/right bindings in {path}.");
    }

    private void OnSaveSettingsClick(object? sender, RoutedEventArgs e)
    {
        LinuxHostSettings settings = _runtime.LoadSettings();
        settings.LeftTrackpadStableId = (_leftDeviceCombo.SelectedItem as DeviceChoice)?.StableId;
        settings.RightTrackpadStableId = (_rightDeviceCombo.SelectedItem as DeviceChoice)?.StableId;
        settings.LayoutPresetName = (_layoutPresetCombo.SelectedItem as PresetChoice)?.Name ?? TrackpadLayoutPreset.SixByThree.Name;
        settings.KeymapPath = string.IsNullOrWhiteSpace(_keymapPathBox.Text) ? null : _keymapPathBox.Text.Trim();
        string path = _runtime.SaveSettings(settings);
        LoadScreen($"Saved Linux host settings to {path}.");
    }

    private void OnInitializeDefaultsClick(object? sender, RoutedEventArgs e)
    {
        string path = _runtime.InitializeSettings();
        LoadScreen($"Initialized Linux host settings at {path}.");
    }

    private async void OnBrowseKeymapClick(object? sender, RoutedEventArgs e)
    {
        if (!StorageProvider.CanOpen)
        {
            _statusText.Text = "This Linux GUI session cannot open a file picker on the current platform backend.";
            return;
        }

        IReadOnlyList<IStorageFile> files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Select a GlassToKey keymap JSON file",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("JSON") { Patterns = ["*.json"] },
                new FilePickerFileType("All Files") { Patterns = ["*"] }
            ]
        });

        if (files.Count == 0)
        {
            _statusText.Text = "Keymap selection canceled.";
            return;
        }

        string? localPath = files[0].TryGetLocalPath();
        if (string.IsNullOrWhiteSpace(localPath))
        {
            _statusText.Text = "The selected keymap could not be resolved to a local file path.";
            return;
        }

        _keymapPathBox.Text = localPath;
        _keymapStatusText.Text = BuildKeymapStatusText(localPath);
        _statusText.Text = "Selected a custom keymap. Save Settings to apply it to the Linux runtime.";
    }

    private void OnClearKeymapClick(object? sender, RoutedEventArgs e)
    {
        _keymapPathBox.Text = string.Empty;
        _keymapStatusText.Text = BuildKeymapStatusText(null);
        _statusText.Text = "Cleared the custom keymap path. Save Settings to return to the bundled Linux default.";
    }

    private void OnRunDoctorClick(object? sender, RoutedEventArgs e)
    {
        RunDoctorFromStatusArea();
    }

    private void OnStartRuntimeClick(object? sender, RoutedEventArgs e)
    {
        if (_runtimeController.TryStart(duration: null, out string message))
        {
            _statusText.Text = message;
            return;
        }

        _statusText.Text = message;
    }

    private async void OnStopRuntimeClick(object? sender, RoutedEventArgs e)
    {
        _statusText.Text = "Stopping Linux runtime.";
        await _runtimeController.StopAsync();
    }

    public void RunDoctorFromStatusArea()
    {
        LinuxDoctorResult result = LinuxDoctorRunner.Run();
        _doctorReportBox.Text = result.Report;
        _statusText.Text = result.Success
            ? "Doctor completed successfully."
            : "Doctor found issues. Review the report below before treating the runtime as ready.";
    }

    public void HideToStatusArea()
    {
        _statusText.Text = "Window hidden. Use the GlassToKey top-bar item to reopen the Linux control surface.";
        Hide();
    }

    public void RequestExit()
    {
        RequestExitAsync();
    }

    private async void RequestExitAsync()
    {
        _allowExit = true;
        await _runtimeController.StopAsync();
        Close();
    }

    private static List<DeviceChoice> BuildDeviceChoices(IReadOnlyList<LinuxInputDeviceDescriptor> devices)
    {
        List<DeviceChoice> choices =
        [
            new DeviceChoice("(Auto / first available)", null)
        ];

        for (int index = 0; index < devices.Count; index++)
        {
            LinuxInputDeviceDescriptor device = devices[index];
            choices.Add(new DeviceChoice(
                $"{device.DisplayName}  [{device.DeviceNode}]  {device.StableId}",
                device.StableId));
        }

        return choices;
    }

    private static List<PresetChoice> BuildPresetChoices()
    {
        List<PresetChoice> choices = new(TrackpadLayoutPreset.All.Length);
        for (int index = 0; index < TrackpadLayoutPreset.All.Length; index++)
        {
            TrackpadLayoutPreset preset = TrackpadLayoutPreset.All[index];
            choices.Add(new PresetChoice(preset.DisplayName, preset.Name));
        }

        return choices;
    }

    private static DeviceChoice? SelectDeviceChoice(IEnumerable<DeviceChoice> choices, string? stableId)
    {
        foreach (DeviceChoice choice in choices)
        {
            if (string.Equals(choice.StableId, stableId, StringComparison.OrdinalIgnoreCase))
            {
                return choice;
            }
        }

        return null;
    }

    private static PresetChoice? SelectPresetChoice(IEnumerable<PresetChoice> choices, string? name)
    {
        foreach (PresetChoice choice in choices)
        {
            if (string.Equals(choice.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                return choice;
            }
        }

        return null;
    }

    private static string BuildResolvedBindingsText(LinuxRuntimeConfiguration configuration)
    {
        if (configuration.Bindings.Count == 0)
        {
            return "No trackpad bindings are currently resolved.";
        }

        List<string> lines = new(configuration.Bindings.Count + 1)
        {
            $"Layout preset: {configuration.LayoutPreset.DisplayName}"
        };
        for (int index = 0; index < configuration.Bindings.Count; index++)
        {
            LinuxTrackpadBinding binding = configuration.Bindings[index];
            lines.Add($"{binding.Side}: {binding.Device.DisplayName} [{binding.Device.DeviceNode}]");
        }

        return string.Join(Environment.NewLine, lines);
    }

    private static string BuildKeymapStatusText(string? keymapPath)
    {
        if (string.IsNullOrWhiteSpace(keymapPath))
        {
            return "Keymap source: bundled Linux default.";
        }

        return File.Exists(keymapPath)
            ? $"Keymap source: custom file '{keymapPath}'."
            : $"Keymap source: missing custom file '{keymapPath}'.";
    }

    private T RequireControl<T>(string name) where T : Control
    {
        return this.FindControl<T>(name)
            ?? throw new InvalidOperationException($"Required control '{name}' was not found in the Linux GUI.");
    }

    private void OnWindowClosing(object? sender, WindowClosingEventArgs e)
    {
        if (_allowExit)
        {
            _runtimeController.Dispose();
            return;
        }

        if (Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime)
        {
            e.Cancel = true;
            HideToStatusArea();
        }
    }

    private void OnRuntimeSnapshotChanged(LinuxEngineRuntimeSnapshot snapshot)
    {
        Dispatcher.UIThread.Post(() => ApplyRuntimeSnapshot(snapshot));
    }

    private void ApplyRuntimeSnapshot(LinuxEngineRuntimeSnapshot snapshot)
    {
        _runtimeSummaryText.Text = snapshot.Failure is null
            ? $"Runtime: {snapshot.Status}. {snapshot.Message}"
            : $"Runtime: {snapshot.Status}. {snapshot.Message} Failure: {snapshot.Failure}";
        _runtimeBindingsText.Text = snapshot.BindingStates.Count == 0
            ? "No live runtime binding updates yet."
            : string.Join(
                Environment.NewLine,
                snapshot.BindingStates.Select(static state => $"{state.Side}: {state.Status} [{state.DeviceNode ?? "no-node"}] {state.Message}"));

        RequireControl<Button>("StartRuntimeButton").IsEnabled = !snapshot.IsActive;
        RequireControl<Button>("StopRuntimeButton").IsEnabled = snapshot.IsActive;
    }

    private sealed record DeviceChoice(string Label, string? StableId)
    {
        public override string ToString()
        {
            return Label;
        }
    }

    private sealed record PresetChoice(string Label, string Name)
    {
        public override string ToString()
        {
            return Label;
        }
    }
}
