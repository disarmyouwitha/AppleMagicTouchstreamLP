using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Controls.Shapes;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using Avalonia.Media;
using System.Text.Json;
using GlassToKey.Linux.Config;
using GlassToKey.Linux.Runtime;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Gui;

public partial class MainWindow : Window
{
    private const double TrackpadWidthMm = 160.0;
    private const double TrackpadHeightMm = 114.9;
    private const double KeyWidthMm = 18.0;
    private const double KeyHeightMm = 17.0;
    private readonly LinuxAppRuntime _runtime = new();
    private readonly LinuxDesktopRuntimeController _desktopRuntime;
    private KeyLayout _leftRenderedLayout = new(Array.Empty<NormalizedRect[]>(), Array.Empty<string[]>());
    private KeyLayout _rightRenderedLayout = new(Array.Empty<NormalizedRect[]>(), Array.Empty<string[]>());
    private KeymapStore _renderedKeymap = KeymapStore.LoadBundledDefault();
    private readonly ComboBox _leftDeviceCombo;
    private readonly ComboBox _rightDeviceCombo;
    private readonly ComboBox _layoutPresetCombo;
    private readonly ComboBox _fiveFingerSwipeLeftCombo;
    private readonly ComboBox _fiveFingerSwipeRightCombo;
    private readonly ComboBox _fiveFingerSwipeUpCombo;
    private readonly ComboBox _fiveFingerSwipeDownCombo;
    private readonly TextBlock _runtimeTypingStatusText;
    private readonly TextBlock _leftPreviewText;
    private readonly TextBlock _rightPreviewText;
    private readonly Canvas _leftPreviewCanvas;
    private readonly Canvas _rightPreviewCanvas;
    private bool _allowExit;
    private bool _runtimeOwnedByTray;
    private bool _loadingScreen;
    private bool _settingsApplyPending;
    private LinuxInputPreviewSnapshot _previewSnapshot = new(
        LinuxInputPreviewStatus.Stopped,
        "The Linux tray runtime is stopped.",
        null,
        Array.Empty<LinuxInputPreviewTrackpadState>());

    public MainWindow()
        : this(LinuxDesktopRuntimeEnvironment.SharedController)
    {
    }

    public MainWindow(LinuxDesktopRuntimeController desktopRuntime)
    {
        _desktopRuntime = desktopRuntime ?? throw new ArgumentNullException(nameof(desktopRuntime));
        InitializeComponent();
        _leftDeviceCombo = RequireControl<ComboBox>("LeftDeviceCombo");
        _rightDeviceCombo = RequireControl<ComboBox>("RightDeviceCombo");
        _layoutPresetCombo = RequireControl<ComboBox>("LayoutPresetCombo");
        _fiveFingerSwipeLeftCombo = RequireControl<ComboBox>("FiveFingerSwipeLeftCombo");
        _fiveFingerSwipeRightCombo = RequireControl<ComboBox>("FiveFingerSwipeRightCombo");
        _fiveFingerSwipeUpCombo = RequireControl<ComboBox>("FiveFingerSwipeUpCombo");
        _fiveFingerSwipeDownCombo = RequireControl<ComboBox>("FiveFingerSwipeDownCombo");
        _runtimeTypingStatusText = RequireControl<TextBlock>("RuntimeTypingStatusText");
        _leftPreviewText = RequireControl<TextBlock>("LeftPreviewText");
        _rightPreviewText = RequireControl<TextBlock>("RightPreviewText");
        _leftPreviewCanvas = RequireControl<Canvas>("LeftPreviewCanvas");
        _rightPreviewCanvas = RequireControl<Canvas>("RightPreviewCanvas");
        _desktopRuntime.PreviewSnapshotChanged += OnPreviewSnapshotChanged;
        _desktopRuntime.RuntimeSnapshotChanged += OnRuntimeSnapshotChanged;
        Closing += OnWindowClosing;
        Opened += OnWindowOpened;
        WireEvents();
        LoadScreen();
        ApplyPreviewSnapshot(_desktopRuntime.PreviewSnapshot);
        ApplyRuntimeStatus(_desktopRuntime.RuntimeSnapshot);
    }

    private void InitializeComponent()
    {
        AvaloniaXamlLoader.Load(this);
    }

    private void WireEvents()
    {
        RequireControl<Button>("RefreshDevicesButton").Click += OnRefreshDevicesClick;
        RequireControl<Button>("SwapSidesButton").Click += OnSwapSidesClick;
        RequireControl<Button>("ImportSettingsButton").Click += OnImportSettingsClick;
        RequireControl<Button>("ExportSettingsButton").Click += OnExportSettingsClick;
        _leftDeviceCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
        _rightDeviceCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
        _layoutPresetCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
        _fiveFingerSwipeLeftCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
        _fiveFingerSwipeRightCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
        _fiveFingerSwipeUpCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
        _fiveFingerSwipeDownCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
    }

    private void LoadScreen()
    {
        _loadingScreen = true;
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

        List<GestureActionChoice> gestureChoices = BuildGestureActionChoices();
        _fiveFingerSwipeLeftCombo.ItemsSource = gestureChoices;
        _fiveFingerSwipeRightCombo.ItemsSource = gestureChoices;
        _fiveFingerSwipeUpCombo.ItemsSource = gestureChoices;
        _fiveFingerSwipeDownCombo.ItemsSource = gestureChoices;
        _fiveFingerSwipeLeftCombo.SelectedItem = SelectGestureActionChoice(gestureChoices, settings.SharedProfile.FiveFingerSwipeLeftAction, "Typing Toggle");
        _fiveFingerSwipeRightCombo.SelectedItem = SelectGestureActionChoice(gestureChoices, settings.SharedProfile.FiveFingerSwipeRightAction, "Typing Toggle");
        _fiveFingerSwipeUpCombo.SelectedItem = SelectGestureActionChoice(gestureChoices, settings.SharedProfile.FiveFingerSwipeUpAction, "None");
        _fiveFingerSwipeDownCombo.SelectedItem = SelectGestureActionChoice(gestureChoices, settings.SharedProfile.FiveFingerSwipeDownAction, "None");
        RenderKeymapPreview(configuration);
        ApplyPreviewSnapshot(_previewSnapshot);

        _loadingScreen = false;
    }

    private void OnRefreshDevicesClick(object? sender, RoutedEventArgs e)
    {
        LoadScreen();
    }

    private void OnSwapSidesClick(object? sender, RoutedEventArgs e)
    {
        _runtime.SwapTrackpadBindings();
        LoadScreen();
    }

    private async void OnLiveSettingsSelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_loadingScreen)
        {
            return;
        }

        await SaveLiveSettingsAsync();
    }

    private Task SaveLiveSettingsAsync()
    {
        if (_settingsApplyPending)
        {
            return Task.CompletedTask;
        }

        _settingsApplyPending = true;
        LinuxHostSettings settings = _runtime.LoadSettings();
        settings.LeftTrackpadStableId = (_leftDeviceCombo.SelectedItem as DeviceChoice)?.StableId;
        settings.RightTrackpadStableId = (_rightDeviceCombo.SelectedItem as DeviceChoice)?.StableId;
        settings.LayoutPresetName = (_layoutPresetCombo.SelectedItem as PresetChoice)?.Name ?? TrackpadLayoutPreset.SixByThree.Name;
        settings.SharedProfile.LayoutPresetName = settings.LayoutPresetName;
        settings.SharedProfile.FiveFingerSwipeLeftAction = (_fiveFingerSwipeLeftCombo.SelectedItem as GestureActionChoice)?.Value ?? "Typing Toggle";
        settings.SharedProfile.FiveFingerSwipeRightAction = (_fiveFingerSwipeRightCombo.SelectedItem as GestureActionChoice)?.Value ?? "Typing Toggle";
        settings.SharedProfile.FiveFingerSwipeUpAction = (_fiveFingerSwipeUpCombo.SelectedItem as GestureActionChoice)?.Value ?? "None";
        settings.SharedProfile.FiveFingerSwipeDownAction = (_fiveFingerSwipeDownCombo.SelectedItem as GestureActionChoice)?.Value ?? "None";
        settings.SharedProfile.TypingEnabled = true;
        try
        {
            settings.Normalize();
            _runtime.SaveSettings(settings);
            LoadScreen();
        }
        finally
        {
            _settingsApplyPending = false;
        }

        return Task.CompletedTask;
    }

    private async void OnImportSettingsClick(object? sender, RoutedEventArgs e)
    {
        if (!StorageProvider.CanOpen)
        {
            ShowNoticeDialog(
                "Import Unavailable",
                "This Linux GUI session cannot open a file picker on the current platform backend.");
            return;
        }

        IReadOnlyList<IStorageFile> files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Import GlassToKey Linux settings",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("JSON") { Patterns = ["*.json"] },
                new FilePickerFileType("All Files") { Patterns = ["*"] }
            ]
        });

        if (files.Count == 0)
        {
            return;
        }

        string? localPath = files[0].TryGetLocalPath();
        if (string.IsNullOrWhiteSpace(localPath))
        {
            ShowNoticeDialog(
                "Import Failed",
                "The selected settings file could not be resolved to a local file path.");
            return;
        }

        if (!TryImportSettings(localPath, out string message))
        {
            ShowNoticeDialog("Import Failed", message);
            return;
        }

        LoadScreen();
    }

    private async void OnExportSettingsClick(object? sender, RoutedEventArgs e)
    {
        if (!StorageProvider.CanSave)
        {
            ShowNoticeDialog(
                "Export Unavailable",
                "This Linux GUI session cannot open a save picker on the current platform backend.");
            return;
        }

        IStorageFile? file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Export GlassToKey Linux settings",
            SuggestedFileName = $"GlassToKey-linux-settings-{DateTime.Now:yyyyMMdd-HHmmss}.json",
            DefaultExtension = "json",
            FileTypeChoices =
            [
                new FilePickerFileType("JSON") { Patterns = ["*.json"] }
            ]
        });

        string? localPath = file?.TryGetLocalPath();
        if (string.IsNullOrWhiteSpace(localPath))
        {
            return;
        }

        if (!TryExportSettings(localPath, out string message))
        {
            ShowNoticeDialog("Export Failed", message);
        }
    }

    public void RunDoctorFromStatusArea()
    {
        LinuxDoctorResult result = LinuxDoctorRunner.Run();
        ShowDoctorReportWindow(result);
    }

    public async Task CaptureAtpCapFromStatusAreaAsync()
    {
        if (!StorageProvider.CanSave)
        {
            ShowNoticeDialog(
                "Capture Unavailable",
                "This Linux GUI session cannot open a save picker on the current platform backend.");
            return;
        }

        IStorageFile? file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Capture GlassToKey Linux .atpcap",
            SuggestedFileName = $"glasstokey-linux-{DateTime.Now:yyyyMMdd-HHmmss}.atpcap",
            DefaultExtension = "atpcap",
            FileTypeChoices =
            [
                new FilePickerFileType("ATPCAP") { Patterns = ["*.atpcap"] }
            ]
        });

        string? localPath = file?.TryGetLocalPath();
        if (string.IsNullOrWhiteSpace(localPath))
        {
            return;
        }

        LinuxDesktopAtpCapCaptureResult result = _desktopRuntime.StartAtpCapCapture(localPath);
        if (!result.Success)
        {
            ShowNoticeDialog("Capture Failed", result.Summary);
        }
    }

    public async Task StopAtpCapFromStatusAreaAsync()
    {
        LinuxDesktopAtpCapCaptureResult result = await _desktopRuntime.StopAtpCapCaptureAsync();
        ShowNoticeDialog(result.Success ? "Capture Complete" : "Capture Failed", result.Summary);
    }

    public async Task ReplayAtpCapFromStatusAreaAsync()
    {
        if (!StorageProvider.CanOpen)
        {
            ShowNoticeDialog(
                "Replay Unavailable",
                "This Linux GUI session cannot open a file picker on the current platform backend.");
            return;
        }

        IReadOnlyList<IStorageFile> files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Replay GlassToKey Linux .atpcap",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("ATPCAP") { Patterns = ["*.atpcap"] },
                new FilePickerFileType("All Files") { Patterns = ["*"] }
            ]
        });

        string? localPath = files.Count > 0 ? files[0].TryGetLocalPath() : null;
        if (string.IsNullOrWhiteSpace(localPath))
        {
            return;
        }

        try
        {
            LinuxRuntimeConfiguration configuration = _runtime.LoadReplayConfiguration();
            string traceOutputPath = System.IO.Path.ChangeExtension(localPath, ".trace.json");
            LinuxAtpCapReplayResult result = LinuxAtpCapTools.Replay(localPath, configuration, traceOutputPath);
            string message = result.Success
                ? $"{result.Summary}\nReplay trace written: {traceOutputPath}"
                : result.Summary;
            ShowNoticeDialog(result.Success ? "Replay Complete" : "Replay Failed", message);
        }
        catch (Exception ex)
        {
            ShowNoticeDialog("Replay Failed", ex.Message);
        }
    }

    public async Task SummarizeAtpCapFromStatusAreaAsync()
    {
        if (!StorageProvider.CanOpen)
        {
            ShowNoticeDialog(
                "Summary Unavailable",
                "This Linux GUI session cannot open a file picker on the current platform backend.");
            return;
        }

        IReadOnlyList<IStorageFile> files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Summarize GlassToKey Linux .atpcap",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("ATPCAP") { Patterns = ["*.atpcap"] },
                new FilePickerFileType("All Files") { Patterns = ["*"] }
            ]
        });

        string? localPath = files.Count > 0 ? files[0].TryGetLocalPath() : null;
        if (string.IsNullOrWhiteSpace(localPath))
        {
            return;
        }

        try
        {
            LinuxAtpCapSummaryResult result = LinuxAtpCapTools.Summarize(localPath);
            ShowNoticeDialog(result.Success ? "Capture Summary" : "Summary Failed", result.Summary);
        }
        catch (Exception ex)
        {
            ShowNoticeDialog("Summary Failed", ex.Message);
        }
    }

    public void HideToStatusArea()
    {
        _ = HideToStatusAreaAsync();
    }

    private async Task HideToStatusAreaAsync()
    {
        if (_desktopRuntime.IsCapturingAtpCap)
        {
            LinuxDesktopAtpCapCaptureResult result = await _desktopRuntime.StopAtpCapCaptureAsync();
            ShowNoticeDialog(result.Success ? "Capture Complete" : "Capture Failed", result.Summary);
        }

        Hide();
    }

    public void BeginTrayRuntimeOwnership()
    {
        if (_runtimeOwnedByTray)
        {
            return;
        }

        _runtimeOwnedByTray = true;
        _ = _desktopRuntime.StartAsync();
    }

    public async Task RequestExitAsync()
    {
        _runtimeOwnedByTray = false;
        _allowExit = true;
        if (_desktopRuntime.IsCapturingAtpCap)
        {
            await _desktopRuntime.StopAtpCapCaptureAsync(canceled: true);
        }
        _desktopRuntime.RequestStop();
        if (!Dispatcher.UIThread.CheckAccess())
        {
            await Dispatcher.UIThread.InvokeAsync(Close);
            return;
        }

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

    private static List<GestureActionChoice> BuildGestureActionChoices()
    {
        return
        [
            new GestureActionChoice("None", "None"),
            new GestureActionChoice("Typing Toggle", "Typing Toggle"),
            new GestureActionChoice("Chordal Shift", "Chordal Shift")
        ];
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

    private static GestureActionChoice SelectGestureActionChoice(
        IEnumerable<GestureActionChoice> choices,
        string? action,
        string fallback)
    {
        string resolved = string.IsNullOrWhiteSpace(action) ? fallback : action.Trim();
        foreach (GestureActionChoice choice in choices)
        {
            if (string.Equals(choice.Value, resolved, StringComparison.OrdinalIgnoreCase))
            {
                return choice;
            }
        }

        return new GestureActionChoice(resolved, resolved);
    }

    private bool TryImportSettings(string path, out string message)
    {
        try
        {
            string json = File.ReadAllText(path);
            LinuxHostSettings? imported = JsonSerializer.Deserialize<LinuxHostSettings>(json, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });
            if (imported == null)
            {
                message = $"Failed to import settings from '{path}'.";
                return false;
            }

            imported.Normalize();
            string savedPath = _runtime.SaveSettings(imported);
            message = $"Imported Linux settings from '{path}' into {savedPath}.";
            return true;
        }
        catch (Exception ex)
        {
            message = $"Failed to import settings from '{path}': {ex.Message}";
            return false;
        }
    }

    private bool TryExportSettings(string path, out string message)
    {
        try
        {
            LinuxHostSettings settings = _runtime.LoadSettings();
            string json = JsonSerializer.Serialize(settings, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                WriteIndented = true
            });
            File.WriteAllText(path, json);
            message = $"Exported Linux settings to '{path}'.";
            return true;
        }
        catch (Exception ex)
        {
            message = $"Failed to export settings to '{path}': {ex.Message}";
            return false;
        }
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
            return;
        }

        if (Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime)
        {
            e.Cancel = true;
            HideToStatusArea();
        }
    }

    private void OnWindowOpened(object? sender, EventArgs e)
    {
        ApplyPreviewSnapshot(_desktopRuntime.PreviewSnapshot);
        ApplyRuntimeStatus(_desktopRuntime.RuntimeSnapshot);
    }

    public void EnsurePreviewActive()
    {
        ApplyPreviewSnapshot(_desktopRuntime.PreviewSnapshot);
    }

    private void ApplyRuntimeStatus(LinuxDesktopRuntimeSnapshot runtimeSnapshot)
    {
        string text;
        Color color;

        switch (runtimeSnapshot.Status)
        {
            case LinuxDesktopRuntimeStatus.Running:
                text = runtimeSnapshot.TypingEnabled ? "Typing: on" : "Typing: off";
                color = runtimeSnapshot.TypingEnabled
                    ? Color.Parse("#CFECCB")
                    : Color.Parse("#FFD1C2");
                break;
            case LinuxDesktopRuntimeStatus.Starting:
                text = "Typing: runtime starting...";
                color = Color.Parse("#F7F2EA");
                break;
            case LinuxDesktopRuntimeStatus.Stopping:
                text = "Typing: runtime stopping...";
                color = Color.Parse("#F7F2EA");
                break;
            case LinuxDesktopRuntimeStatus.WaitingForBindings:
                text = "Typing: waiting for bindings";
                color = Color.Parse("#D9C7B5");
                break;
            case LinuxDesktopRuntimeStatus.Faulted:
                text = "Typing: runtime faulted";
                color = Color.Parse("#FFD1C2");
                break;
            default:
                text = "Typing: runtime stopped";
                color = Color.Parse("#D9C7B5");
                break;
        }

        _runtimeTypingStatusText.Text = text;
        _runtimeTypingStatusText.Foreground = new SolidColorBrush(color);
    }

    private void ShowNoticeDialog(string title, string message)
    {
        Window dialog = new()
        {
            Width = 520,
            Height = 220,
            MinWidth = 420,
            MinHeight = 180,
            Title = title
        };

        TextBlock messageBlock = new()
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap
        };

        Button closeButton = new()
        {
            Content = "Close",
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right
        };

        StackPanel root = new()
        {
            Spacing = 12,
            Margin = new Thickness(18)
        };
        root.Children.Add(messageBlock);
        root.Children.Add(closeButton);
        closeButton.Click += (_, _) => dialog.Close();
        dialog.Content = root;

        if (IsVisible)
        {
            dialog.Show(this);
        }
        else
        {
            dialog.Show();
        }

        dialog.Activate();
    }

    private void ShowDoctorReportWindow(LinuxDoctorResult result)
    {
        Window dialog = new()
        {
            Width = 760,
            Height = 560,
            MinWidth = 620,
            MinHeight = 420,
            Title = result.Success ? "GlassToKey Linux Doctor" : "GlassToKey Linux Doctor Issues"
        };
        dialog.Content = BuildDoctorDialogContent(dialog, result);

        if (IsVisible)
        {
            dialog.Show(this);
        }
        else
        {
            dialog.Show();
        }

        dialog.Activate();
    }

    private static Control BuildDoctorDialogContent(Window dialog, LinuxDoctorResult result)
    {
        TextBox reportBox = new()
        {
            Text = result.Report,
            IsReadOnly = true,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = FontFamily.Parse("avares://Avalonia.Fonts.Inter/Assets#Inter")
        };

        Button closeButton = new()
        {
            Content = "Close",
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right
        };

        StackPanel root = new()
        {
            Spacing = 12,
            Margin = new Thickness(18)
        };
        root.Children.Add(new TextBlock
        {
            Text = result.Success
                ? "Doctor completed successfully."
                : "Doctor found issues that should be reviewed before trusting the runtime.",
            TextWrapping = TextWrapping.Wrap,
            FontWeight = FontWeight.SemiBold
        });
        root.Children.Add(reportBox);
        root.Children.Add(closeButton);
        closeButton.Click += (_, _) => dialog.Close();

        return root;
    }

    private void OnRuntimeSnapshotChanged(LinuxDesktopRuntimeSnapshot snapshot)
    {
        if (!Dispatcher.UIThread.CheckAccess())
        {
            Dispatcher.UIThread.Post(() => OnRuntimeSnapshotChanged(snapshot));
            return;
        }

        ApplyRuntimeStatus(snapshot);
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private void OnPreviewSnapshotChanged(LinuxInputPreviewSnapshot snapshot)
    {
        ApplyPreviewSnapshot(snapshot);
    }

    private void ApplyPreviewSnapshot(LinuxInputPreviewSnapshot snapshot)
    {
        if (!Dispatcher.UIThread.CheckAccess())
        {
            Dispatcher.UIThread.Post(() => ApplyPreviewSnapshot(snapshot));
            return;
        }

        _previewSnapshot = snapshot;
        int activeLayer = Math.Clamp(_desktopRuntime.RuntimeSnapshot.ActiveLayer, 0, 7);
        LinuxInputPreviewTrackpadState? left = GetPreviewState(snapshot, TrackpadSide.Left);
        LinuxInputPreviewTrackpadState? right = GetPreviewState(snapshot, TrackpadSide.Right);
        _leftPreviewText.Text = BuildPreviewDetails(left, _leftRenderedLayout, _renderedKeymap, TrackpadSide.Left, activeLayer);
        _rightPreviewText.Text = BuildPreviewDetails(right, _rightRenderedLayout, _renderedKeymap, TrackpadSide.Right, activeLayer);
        RenderPreviewCanvas(_leftPreviewCanvas, left, _leftRenderedLayout, _renderedKeymap, TrackpadSide.Left, activeLayer, "#D05A2A");
        RenderPreviewCanvas(_rightPreviewCanvas, right, _rightRenderedLayout, _renderedKeymap, TrackpadSide.Right, activeLayer, "#246A73");

    }

    private static LinuxInputPreviewTrackpadState? GetPreviewState(
        LinuxInputPreviewSnapshot snapshot,
        TrackpadSide side)
    {
        for (int index = 0; index < snapshot.Trackpads.Count; index++)
        {
            if (snapshot.Trackpads[index].Side == side)
            {
                return snapshot.Trackpads[index];
            }
        }

        return null;
    }

    private static string BuildPreviewDetails(LinuxInputPreviewTrackpadState? state, KeyLayout layout, KeymapStore keymap, TrackpadSide side, int activeLayer)
    {
        if (state == null)
        {
            return "No bound trackpad on this side.";
        }

        LinuxInputPreviewContact[] visibleContacts = GetVisibleContacts(state);
        LinuxInputPreviewContact[] activeContacts = GetTipContacts(state);
        int activeTipContacts = activeContacts.Length;

        List<string> lines =
        [
            $"Binding: {state.BindingStatus}",
            $"Node: {state.DeviceNode ?? "no-node"}",
            $"Frame: {state.FrameSequence}",
            $"Layer: {activeLayer}",
            $"Contacts: {visibleContacts.Length} ({activeTipContacts} active tip)",
            $"Button: {(state.IsButtonPressed ? "down" : "up")}",
            $"Range: {state.MaxX} x {state.MaxY}",
            state.BindingMessage
        ];

        if (visibleContacts.Length > 0)
        {
            LinuxInputPreviewContact contact = visibleContacts[0];
            lines.Add($"First contact: id {contact.Id} @ ({contact.X},{contact.Y}) pressure {contact.Pressure} tip={(contact.TipSwitch ? "down" : "up")}");
            string[] hits = ResolveTouchedLabels(state, layout, keymap, side, activeLayer);
            if (hits.Length > 0)
            {
                lines.Add($"Touched keys: {string.Join(", ", hits)}");
            }
        }

        return string.Join(Environment.NewLine, lines);
    }

    private static void RenderPreviewCanvas(
        Canvas canvas,
        LinuxInputPreviewTrackpadState? state,
        KeyLayout layout,
        KeymapStore keymap,
        TrackpadSide side,
        int activeLayer,
        string accentHex)
    {
        canvas.Children.Clear();

        double width = canvas.Width > 0 ? canvas.Width : 300;
        double height = canvas.Height > 0 ? canvas.Height : 180;
        canvas.Children.Add(new Rectangle
        {
            Width = width,
            Height = height,
            RadiusX = 14,
            RadiusY = 14,
            Stroke = new SolidColorBrush(Color.Parse("#D9C7B5")),
            StrokeThickness = 1
        });

        RenderPreviewKeymapOverlay(canvas, layout, keymap, side, activeLayer, width, height, accentHex);
        LinuxInputPreviewContact[] visibleContacts = state == null
            ? Array.Empty<LinuxInputPreviewContact>()
            : GetVisibleContacts(state);
        LinuxInputPreviewContact[] activeContacts = state == null
            ? Array.Empty<LinuxInputPreviewContact>()
            : GetTipContacts(state);

        if (state == null)
        {
            canvas.Children.Add(new TextBlock
            {
                Text = "No trackpad bound.",
                Foreground = new SolidColorBrush(Color.Parse("#6A4533"))
            });
            Canvas.SetLeft(canvas.Children[^1], 12);
            Canvas.SetTop(canvas.Children[^1], 12);
            return;
        }

        if (visibleContacts.Length == 0)
        {
            canvas.Children.Add(new TextBlock
            {
                Text = state.BindingStatus == LinuxRuntimeBindingStatus.Streaming
                    ? "Touch the trackpad to see contacts."
                    : state.BindingMessage,
                Foreground = new SolidColorBrush(Color.Parse("#6A4533")),
                Width = width - 24,
                TextWrapping = TextWrapping.Wrap
            });
            Canvas.SetLeft(canvas.Children[^1], 12);
            Canvas.SetTop(canvas.Children[^1], 12);
            return;
        }

        Color accent = Color.Parse(accentHex);
        for (int index = 0; index < visibleContacts.Length; index++)
        {
            LinuxInputPreviewContact contact = visibleContacts[index];
            double xRatio = state.MaxX > 0 ? contact.X / (double)state.MaxX : 0.5;
            double yRatio = state.MaxY > 0 ? contact.Y / (double)state.MaxY : 0.5;
            double centerX = 12 + xRatio * (width - 24);
            double centerY = 12 + yRatio * (height - 24);
            double radius = 18 + Math.Min(24, contact.Pressure / 10.0);
            bool activeTouch = contact.TipSwitch;

            Ellipse ellipse = new()
            {
                Width = radius * 2,
                Height = radius * 2,
                Fill = new SolidColorBrush(accent, activeTouch ? 0.55 : 0.12),
                Stroke = new SolidColorBrush(accent),
                StrokeThickness = activeTouch ? 2.5 : 1
            };
            canvas.Children.Add(ellipse);
            Canvas.SetLeft(ellipse, centerX - radius);
            Canvas.SetTop(ellipse, centerY - radius);

            TextBlock label = new()
            {
                Text = $"f:{contact.Pressure}",
                Foreground = new SolidColorBrush(Color.Parse("#1E2328")),
                FontWeight = FontWeight.SemiBold
            };
            canvas.Children.Add(label);
            Canvas.SetLeft(label, centerX - 16);
            Canvas.SetTop(label, centerY - 8);
        }
    }

    private static LinuxInputPreviewContact[] GetVisibleContacts(LinuxInputPreviewTrackpadState state)
    {
        if (state.Contacts.Count == 0)
        {
            return Array.Empty<LinuxInputPreviewContact>();
        }

        List<LinuxInputPreviewContact> visibleContacts = [];
        for (int index = 0; index < state.Contacts.Count; index++)
        {
            LinuxInputPreviewContact contact = state.Contacts[index];
            if (contact.TipSwitch || contact.Confidence || contact.Pressure > 0)
            {
                visibleContacts.Add(contact);
            }
        }

        return visibleContacts.Count == 0 ? [.. state.Contacts] : [.. visibleContacts];
    }

    private static LinuxInputPreviewContact[] GetTipContacts(LinuxInputPreviewTrackpadState state)
    {
        if (state.Contacts.Count == 0)
        {
            return Array.Empty<LinuxInputPreviewContact>();
        }

        List<LinuxInputPreviewContact> activeContacts = [];
        for (int index = 0; index < state.Contacts.Count; index++)
        {
            if (state.Contacts[index].TipSwitch)
            {
                activeContacts.Add(state.Contacts[index]);
            }
        }

        return [.. activeContacts];
    }

    private void RenderKeymapPreview(LinuxRuntimeConfiguration configuration)
    {
        ColumnLayoutSettings[] columns = RuntimeConfigurationFactory.BuildColumnSettingsForPreset(
            configuration.SharedProfile,
            configuration.LayoutPreset);
        RuntimeConfigurationFactory.BuildLayouts(
            configuration.SharedProfile,
            configuration.Keymap,
            configuration.LayoutPreset,
            columns,
            out KeyLayout leftLayout,
            out KeyLayout rightLayout);

        _leftRenderedLayout = leftLayout;
        _rightRenderedLayout = rightLayout;
        _renderedKeymap = configuration.Keymap;
    }

    private static void RenderPreviewKeymapOverlay(
        Canvas canvas,
        KeyLayout layout,
        KeymapStore keymap,
        TrackpadSide side,
        int activeLayer,
        double width,
        double height,
        string accentHex)
    {
        if (layout.Rects.Length == 0)
        {
            return;
        }

        Color accent = Color.Parse(accentHex);
        for (int row = 0; row < layout.Rects.Length; row++)
        {
            for (int col = 0; col < layout.Rects[row].Length; col++)
            {
                NormalizedRect rect = layout.Rects[row][col];
                string storageKey = GridKeyPosition.StorageKey(side, row, col);
                string label = keymap.ResolveMapping(activeLayer, storageKey, layout.Labels[row][col]).Primary.Label;

                Border keyBorder = new()
                {
                    Width = Math.Max(22, rect.Width * width),
                    Height = Math.Max(20, rect.Height * height),
                    Background = new SolidColorBrush(accent, 0.08),
                    BorderBrush = new SolidColorBrush(accent, 0.25),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(8),
                    Child = new TextBlock
                    {
                        Text = label,
                        Foreground = new SolidColorBrush(Color.Parse("#6A4533")),
                        FontSize = 11,
                        FontWeight = FontWeight.SemiBold,
                        TextAlignment = TextAlignment.Center,
                        TextWrapping = TextWrapping.Wrap,
                        MaxWidth = Math.Max(18, rect.Width * width - 8),
                        VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                        HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center
                    },
                    RenderTransformOrigin = RelativePoint.Center
                };
                if (Math.Abs(rect.RotationDegrees) >= 0.00001)
                {
                    keyBorder.RenderTransform = new RotateTransform(rect.RotationDegrees);
                }

                canvas.Children.Add(keyBorder);
                Canvas.SetLeft(keyBorder, rect.X * width);
                Canvas.SetTop(keyBorder, rect.Y * height);
            }
        }

        IReadOnlyList<CustomButton> customButtons = keymap.ResolveCustomButtons(activeLayer, side);
        for (int index = 0; index < customButtons.Count; index++)
        {
            CustomButton button = customButtons[index];
            Border customBorder = new()
            {
                Width = Math.Max(24, button.Rect.Width * width),
                Height = Math.Max(20, button.Rect.Height * height),
                Background = new SolidColorBrush(Color.Parse("#E07845"), 0.20),
                BorderBrush = new SolidColorBrush(Color.Parse("#E07845"), 0.65),
                BorderThickness = new Thickness(1.5),
                CornerRadius = new CornerRadius(10),
                Child = new TextBlock
                {
                    Text = button.Primary?.Label ?? "None",
                    Foreground = new SolidColorBrush(Color.Parse("#6A4533")),
                    FontSize = 11,
                    FontWeight = FontWeight.SemiBold,
                    TextAlignment = TextAlignment.Center,
                    TextWrapping = TextWrapping.Wrap,
                    MaxWidth = Math.Max(18, button.Rect.Width * width - 8),
                    VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                    HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center
                }
            };

            canvas.Children.Add(customBorder);
            Canvas.SetLeft(customBorder, button.Rect.X * width);
            Canvas.SetTop(customBorder, button.Rect.Y * height);
        }
    }

    private static string[] ResolveTouchedLabels(
        LinuxInputPreviewTrackpadState state,
        KeyLayout layout,
        KeymapStore keymap,
        TrackpadSide side,
        int activeLayer)
    {
        if (layout.HitGeometries.Length == 0 || state.Contacts.Count == 0 || state.MaxX == 0 || state.MaxY == 0)
        {
            return Array.Empty<string>();
        }

        HashSet<string> labels = new(StringComparer.OrdinalIgnoreCase);
        for (int index = 0; index < state.Contacts.Count; index++)
        {
            LinuxInputPreviewContact contact = state.Contacts[index];
            if (!contact.TipSwitch)
            {
                continue;
            }

            double x = contact.X / (double)state.MaxX;
            double y = contact.Y / (double)state.MaxY;
            for (int row = 0; row < layout.HitGeometries.Length; row++)
            {
                for (int col = 0; col < layout.HitGeometries[row].Length; col++)
                {
                    if (!layout.HitGeometries[row][col].Contains(x, y))
                    {
                        continue;
                    }

                    string storageKey = GridKeyPosition.StorageKey(side, row, col);
                    labels.Add(keymap.ResolveMapping(activeLayer, storageKey, layout.Labels[row][col]).Primary.Label);
                }
            }
        }

        IReadOnlyList<CustomButton> customButtons = keymap.ResolveCustomButtons(activeLayer, side);
        for (int index = 0; index < state.Contacts.Count; index++)
        {
            LinuxInputPreviewContact contact = state.Contacts[index];
            if (!contact.TipSwitch)
            {
                continue;
            }

            double x = contact.X / (double)state.MaxX;
            double y = contact.Y / (double)state.MaxY;
            for (int buttonIndex = 0; buttonIndex < customButtons.Count; buttonIndex++)
            {
                CustomButton button = customButtons[buttonIndex];
                if (button.Rect.Contains(x, y))
                {
                    labels.Add(button.Primary?.Label ?? "None");
                }
            }
        }

        return labels.Count == 0 ? Array.Empty<string>() : [.. labels];
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

    private sealed record GestureActionChoice(string Label, string Value)
    {
        public override string ToString()
        {
            return Label;
        }
    }
}
