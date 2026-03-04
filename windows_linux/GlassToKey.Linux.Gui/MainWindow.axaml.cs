using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using Avalonia.Media;
using System.Diagnostics;
using System.Globalization;
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
    private const double MinCustomButtonPercent = 5.0;
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
    private readonly ComboBox _keymapLayerCombo;
    private readonly ComboBox _keymapPrimaryCombo;
    private readonly ComboBox _keymapHoldCombo;
    private readonly Button _keymapClearSelectionButton;
    private readonly TextBlock _keymapSelectionText;
    private readonly TextBox _keyRotationBox;
    private readonly Button _customButtonAddLeftButton;
    private readonly Button _customButtonAddRightButton;
    private readonly Button _customButtonDeleteButton;
    private readonly TextBox _customButtonXBox;
    private readonly TextBox _customButtonYBox;
    private readonly TextBox _customButtonWidthBox;
    private readonly TextBox _customButtonHeightBox;
    private readonly Border _noticeOverlay;
    private readonly TextBlock _noticeTitleText;
    private readonly TextBlock _noticeMessageText;
    private readonly Button _noticeCloseButton;
    private readonly StackPanel _replayPanel;
    private readonly Button _replayToggleButton;
    private readonly Button _replayCloseButton;
    private readonly ComboBox _replaySpeedCombo;
    private readonly Slider _replayTimelineSlider;
    private readonly TextBlock _replayTimeText;
    private readonly TextBlock _runtimeTypingStatusText;
    private readonly TextBlock _leftPreviewText;
    private readonly TextBlock _rightPreviewText;
    private readonly Canvas _leftPreviewCanvas;
    private readonly Canvas _rightPreviewCanvas;
    private readonly DispatcherTimer _replayTimer;
    private readonly List<KeyActionChoice> _keyActionChoices = BuildKeyActionChoices();
    private readonly HashSet<string> _keyActionChoiceLookup = new(StringComparer.OrdinalIgnoreCase);
    private bool _allowExit;
    private bool _runtimeOwnedByTray;
    private bool _loadingScreen;
    private bool _settingsApplyPending;
    private bool _hideInProgress;
    private bool _suppressKeymapEditorEvents;
    private bool _suppressReplayTimelineEvents;
    private bool _suppressReplaySpeedEvents;
    private bool _hasSelectedKey;
    private bool _hasSelectedCustomButton;
    private TrackpadSide _selectedKeySide = TrackpadSide.Left;
    private int _selectedKeyRow = -1;
    private int _selectedKeyColumn = -1;
    private string? _selectedCustomButtonId;
    private bool _replayRunning;
    private bool _replayCompleted;
    private int _replayFrameIndex;
    private long _replayPlayStartTicks;
    private double _replayAccumulatedTicks;
    private double _replaySpeed = 1.0;
    private LinuxAtpCapReplayVisualData? _replayData;
    private LinuxInputPreviewSnapshot _previewSnapshot = new(
        LinuxInputPreviewStatus.Stopped,
        "The Linux tray runtime is stopped.",
        null,
        Array.Empty<LinuxInputPreviewTrackpadState>());

    public event Action<bool>? CaptureStateChanged;

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
        _keymapLayerCombo = RequireControl<ComboBox>("KeymapLayerCombo");
        _keymapPrimaryCombo = RequireControl<ComboBox>("KeymapPrimaryCombo");
        _keymapHoldCombo = RequireControl<ComboBox>("KeymapHoldCombo");
        _keymapClearSelectionButton = RequireControl<Button>("KeymapClearSelectionButton");
        _keymapSelectionText = RequireControl<TextBlock>("KeymapSelectionText");
        _keyRotationBox = RequireControl<TextBox>("KeyRotationBox");
        _customButtonAddLeftButton = RequireControl<Button>("CustomButtonAddLeftButton");
        _customButtonAddRightButton = RequireControl<Button>("CustomButtonAddRightButton");
        _customButtonDeleteButton = RequireControl<Button>("CustomButtonDeleteButton");
        _customButtonXBox = RequireControl<TextBox>("CustomButtonXBox");
        _customButtonYBox = RequireControl<TextBox>("CustomButtonYBox");
        _customButtonWidthBox = RequireControl<TextBox>("CustomButtonWidthBox");
        _customButtonHeightBox = RequireControl<TextBox>("CustomButtonHeightBox");
        _noticeOverlay = RequireControl<Border>("NoticeOverlay");
        _noticeTitleText = RequireControl<TextBlock>("NoticeTitleText");
        _noticeMessageText = RequireControl<TextBlock>("NoticeMessageText");
        _noticeCloseButton = RequireControl<Button>("NoticeCloseButton");
        _replayPanel = RequireControl<StackPanel>("ReplayPanel");
        _replayToggleButton = RequireControl<Button>("ReplayToggleButton");
        _replayCloseButton = RequireControl<Button>("ReplayCloseButton");
        _replaySpeedCombo = RequireControl<ComboBox>("ReplaySpeedCombo");
        _replayTimelineSlider = RequireControl<Slider>("ReplayTimelineSlider");
        _replayTimeText = RequireControl<TextBlock>("ReplayTimeText");
        _runtimeTypingStatusText = RequireControl<TextBlock>("RuntimeTypingStatusText");
        _leftPreviewText = RequireControl<TextBlock>("LeftPreviewText");
        _rightPreviewText = RequireControl<TextBlock>("RightPreviewText");
        _leftPreviewCanvas = RequireControl<Canvas>("LeftPreviewCanvas");
        _rightPreviewCanvas = RequireControl<Canvas>("RightPreviewCanvas");
        _replayTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(8)
        };
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
        _leftPreviewCanvas.PointerPressed += OnLeftPreviewPointerPressed;
        _rightPreviewCanvas.PointerPressed += OnRightPreviewPointerPressed;
        _keymapLayerCombo.SelectionChanged += OnKeymapLayerSelectionChanged;
        _keymapPrimaryCombo.SelectionChanged += OnKeymapActionSelectionChanged;
        _keymapHoldCombo.SelectionChanged += OnKeymapActionSelectionChanged;
        _keymapClearSelectionButton.Click += OnKeymapClearSelectionClick;
        _keyRotationBox.LostFocus += OnKeyGeometryCommitted;
        _keyRotationBox.KeyDown += OnKeyGeometryKeyDown;
        _customButtonAddLeftButton.Click += OnCustomButtonAddLeftClicked;
        _customButtonAddRightButton.Click += OnCustomButtonAddRightClicked;
        _customButtonDeleteButton.Click += OnCustomButtonDeleteClicked;
        _customButtonXBox.LostFocus += OnCustomButtonGeometryCommitted;
        _customButtonYBox.LostFocus += OnCustomButtonGeometryCommitted;
        _customButtonWidthBox.LostFocus += OnCustomButtonGeometryCommitted;
        _customButtonHeightBox.LostFocus += OnCustomButtonGeometryCommitted;
        _customButtonXBox.KeyDown += OnCustomButtonGeometryKeyDown;
        _customButtonYBox.KeyDown += OnCustomButtonGeometryKeyDown;
        _customButtonWidthBox.KeyDown += OnCustomButtonGeometryKeyDown;
        _customButtonHeightBox.KeyDown += OnCustomButtonGeometryKeyDown;
        KeyDown += OnWindowKeyDown;
        _noticeCloseButton.Click += (_, _) => HideNoticeDialog();
        _replayToggleButton.Click += OnReplayToggleClick;
        _replayCloseButton.Click += OnReplayCloseClick;
        _replaySpeedCombo.SelectionChanged += OnReplaySpeedChanged;
        _replayTimelineSlider.PropertyChanged += OnReplayTimelinePropertyChanged;
        _replayTimer.Tick += OnReplayTick;
        InitializeKeymapEditorControls();
        InitializeReplayControls();
    }

    private void InitializeReplayControls()
    {
        _suppressReplaySpeedEvents = true;
        ReplaySpeedOption[] options =
        [
            new(0.25, "0.25x"),
            new(0.50, "0.5x"),
            new(1.00, "1x"),
            new(2.00, "2x"),
            new(4.00, "4x")
        ];
        _replaySpeedCombo.ItemsSource = options;
        _replaySpeedCombo.SelectedIndex = 2;
        _suppressReplaySpeedEvents = false;
        _replayTimelineSlider.Minimum = 0;
        _replayTimelineSlider.Maximum = 1000;
        _replayTimelineSlider.Value = 0;
        UpdateReplayControls();
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
        ReloadKeymapActionChoices(configuration.Keymap);
        int fallbackLayer = Math.Clamp(settings.SharedProfile.ActiveLayer, 0, 7);
        List<LayerChoice> layerChoices = BuildLayerChoices();
        _suppressKeymapEditorEvents = true;
        _keymapLayerCombo.ItemsSource = layerChoices;
        _keymapLayerCombo.SelectedItem =
            SelectLayerChoice(layerChoices, GetSelectedLayer()) ??
            SelectLayerChoice(layerChoices, fallbackLayer) ??
            layerChoices[0];
        _suppressKeymapEditorEvents = false;
        EnsureSelectedKeyStillValid();
        RefreshKeymapEditor();
        if (IsReplayMode)
        {
            ReloadReplayMode(configuration);
        }
        else
        {
            ApplyPreviewSnapshot(_previewSnapshot);
        }

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

    private void InitializeKeymapEditorControls()
    {
        for (int index = 0; index < _keyActionChoices.Count; index++)
        {
            _keyActionChoiceLookup.Add(_keyActionChoices[index].Value);
        }

        _keymapPrimaryCombo.ItemsSource = _keyActionChoices;
        _keymapHoldCombo.ItemsSource = _keyActionChoices;
        _keymapSelectionText.Text = "Selection: none";
        _keymapPrimaryCombo.IsEnabled = false;
        _keymapHoldCombo.IsEnabled = false;
        _keyRotationBox.IsEnabled = false;
        _customButtonDeleteButton.IsEnabled = false;
        SetCustomButtonGeometryEditorEnabled(false);
        ClearCustomButtonGeometryEditorValues();
    }

    private void ReloadKeymapActionChoices(KeymapStore keymap)
    {
        string? previousPrimary = (_keymapPrimaryCombo.SelectedItem as KeyActionChoice)?.Value;
        string? previousHold = (_keymapHoldCombo.SelectedItem as KeyActionChoice)?.Value;

        _keyActionChoices.Clear();
        _keyActionChoiceLookup.Clear();
        List<KeyActionChoice> defaults = BuildKeyActionChoices();
        for (int index = 0; index < defaults.Count; index++)
        {
            _keyActionChoices.Add(defaults[index]);
            _keyActionChoiceLookup.Add(defaults[index].Value);
        }

        foreach (KeyValuePair<int, Dictionary<string, KeyMapping>> layer in keymap.Mappings)
        {
            foreach (KeyValuePair<string, KeyMapping> mappingEntry in layer.Value)
            {
                EnsureActionChoice(mappingEntry.Value?.Primary?.Label);
                EnsureActionChoice(mappingEntry.Value?.Hold?.Label);
            }
        }

        foreach (KeyValuePair<int, List<CustomButton>> customButtonsByLayer in keymap.CustomButtons)
        {
            for (int index = 0; index < customButtonsByLayer.Value.Count; index++)
            {
                CustomButton button = customButtonsByLayer.Value[index];
                EnsureActionChoice(button.Primary?.Label);
                EnsureActionChoice(button.Hold?.Label);
            }
        }

        _suppressKeymapEditorEvents = true;
        _keymapPrimaryCombo.ItemsSource = null;
        _keymapHoldCombo.ItemsSource = null;
        _keymapPrimaryCombo.ItemsSource = _keyActionChoices;
        _keymapHoldCombo.ItemsSource = _keyActionChoices;
        SetActionComboSelection(_keymapPrimaryCombo, previousPrimary ?? "None");
        SetActionComboSelection(_keymapHoldCombo, previousHold ?? "None");
        _suppressKeymapEditorEvents = false;
    }

    private void EnsureActionChoice(string? action)
    {
        if (string.IsNullOrWhiteSpace(action))
        {
            return;
        }

        string value = action.Trim();
        if (!_keyActionChoiceLookup.Add(value))
        {
            return;
        }

        _keyActionChoices.Add(new KeyActionChoice(value, value));
    }

    private static List<KeyActionChoice> BuildKeyActionChoices()
    {
        List<KeyActionChoice> options = [];
        AddKeyActionChoice(options, "None");
        AddKeyActionChoice(options, "Left Click");
        AddKeyActionChoice(options, "Double Click");
        AddKeyActionChoice(options, "Right Click");
        AddKeyActionChoice(options, "Middle Click");

        for (char ch = 'A'; ch <= 'Z'; ch++)
        {
            AddKeyActionChoice(options, ch.ToString());
        }

        for (char ch = '0'; ch <= '9'; ch++)
        {
            AddKeyActionChoice(options, ch.ToString());
        }

        string[] navigationAndEditing =
        {
            "Space",
            "Tab",
            "Enter",
            "Ret",
            "Backspace",
            "Back",
            "Escape",
            "Delete",
            "Insert",
            "Home",
            "End",
            "PageUp",
            "PageDown",
            "Left",
            "Right",
            "Up",
            "Down"
        };
        for (int i = 0; i < navigationAndEditing.Length; i++)
        {
            AddKeyActionChoice(options, navigationAndEditing[i]);
        }

        string[] modifiersAndModes =
        {
            "Shift",
            "Chordal Shift",
            "Ctrl",
            "Alt",
            "LWin",
            "RWin",
            "Typing Toggle",
            "TT"
        };
        for (int i = 0; i < modifiersAndModes.Length; i++)
        {
            AddKeyActionChoice(options, modifiersAndModes[i]);
        }

        string[] symbols =
        {
            "!",
            "@",
            "#",
            "$",
            "%",
            "^",
            "&",
            "*",
            "(",
            ")",
            "~",
            ";",
            ":",
            "'",
            "\"",
            ",",
            "<",
            ".",
            ">",
            "/",
            "?",
            "\\",
            "|",
            "[",
            "{",
            "]",
            "}",
            "-",
            "_",
            "+",
            "EmDash",
            "=",
            "`"
        };
        for (int i = 0; i < symbols.Length; i++)
        {
            AddKeyActionChoice(options, symbols[i]);
        }

        for (int i = 1; i <= 12; i++)
        {
            AddKeyActionChoice(options, $"F{i}");
        }

        string[] systemAndMedia =
        {
            "EMOJI",
            "VOICE",
            "VOL_UP",
            "VOL_DOWN",
            "BRIGHT_UP",
            "BRIGHT_DOWN"
        };
        for (int i = 0; i < systemAndMedia.Length; i++)
        {
            AddKeyActionChoice(options, systemAndMedia[i]);
        }

        string[] shortcuts =
        {
            "Ctrl+C",
            "Ctrl+V",
            "Ctrl+F",
            "Ctrl+X",
            "Ctrl+S",
            "Ctrl+A",
            "Ctrl+Z",
            "Ctrl+."
        };
        for (int i = 0; i < shortcuts.Length; i++)
        {
            AddKeyActionChoice(options, shortcuts[i]);
        }

        AddKeyActionChoice(options, "TO(0)");
        for (int layer = 1; layer <= 7; layer++)
        {
            AddKeyActionChoice(options, $"MO({layer})");
            AddKeyActionChoice(options, $"TO({layer})");
            AddKeyActionChoice(options, $"TG({layer})");
        }

        return options;
    }

    private static void AddKeyActionChoice(List<KeyActionChoice> choices, string value)
    {
        choices.Add(new KeyActionChoice(value, value));
    }

    private static List<LayerChoice> BuildLayerChoices()
    {
        List<LayerChoice> layers = [];
        for (int layer = 0; layer <= 7; layer++)
        {
            layers.Add(new LayerChoice($"Layer {layer}", layer));
        }

        return layers;
    }

    private static LayerChoice? SelectLayerChoice(IEnumerable<LayerChoice> choices, int layer)
    {
        foreach (LayerChoice choice in choices)
        {
            if (choice.Layer == layer)
            {
                return choice;
            }
        }

        return null;
    }

    private int GetSelectedLayer()
    {
        if (_keymapLayerCombo.SelectedItem is LayerChoice choice)
        {
            return Math.Clamp(choice.Layer, 0, 7);
        }

        return 0;
    }

    private void OnKeymapLayerSelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_suppressKeymapEditorEvents || _loadingScreen)
        {
            return;
        }

        EnsureSelectedKeyStillValid();
        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private void OnKeymapActionSelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_suppressKeymapEditorEvents || _loadingScreen || IsReplayMode)
        {
            return;
        }

        ApplySelectedKeymapOverride();
    }

    private void OnKeymapClearSelectionClick(object? sender, RoutedEventArgs e)
    {
        ClearSelectionForEditing();
        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private void OnLeftPreviewPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        HandleSurfaceKeymapSelection(TrackpadSide.Left, _leftPreviewCanvas, _leftRenderedLayout, e);
    }

    private void OnRightPreviewPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        HandleSurfaceKeymapSelection(TrackpadSide.Right, _rightPreviewCanvas, _rightRenderedLayout, e);
    }

    private void HandleSurfaceKeymapSelection(TrackpadSide side, Canvas surface, KeyLayout layout, PointerPressedEventArgs e)
    {
        if (IsReplayMode || !e.GetCurrentPoint(surface).Properties.IsLeftButtonPressed)
        {
            return;
        }

        Point point = e.GetPosition(surface);
        IReadOnlyList<CustomButton> customButtons = _renderedKeymap.ResolveCustomButtons(GetSelectedLayer(), side);
        if (!TryHitSelectionAtPoint(layout, customButtons, point, surface.Bounds.Width, surface.Bounds.Height, out int row, out int column, out string? customButtonId))
        {
            ClearSelectionForEditing();
            RefreshKeymapEditor();
            ApplyPreviewSnapshot(_previewSnapshot);
            return;
        }

        if (!string.IsNullOrWhiteSpace(customButtonId))
        {
            SelectCustomButtonForEditing(side, customButtonId);
        }
        else
        {
            SelectKeyForEditing(side, row, column);
        }

        e.Handled = true;
    }

    private static bool TryHitSelectionAtPoint(
        KeyLayout layout,
        IReadOnlyList<CustomButton> customButtons,
        Point point,
        double surfaceWidth,
        double surfaceHeight,
        out int row,
        out int column,
        out string? customButtonId)
    {
        row = -1;
        column = -1;
        customButtonId = null;
        if (surfaceWidth <= 1 || surfaceHeight <= 1)
        {
            return false;
        }

        double xNorm = point.X / surfaceWidth;
        double yNorm = point.Y / surfaceHeight;
        if (xNorm < 0 || xNorm > 1 || yNorm < 0 || yNorm > 1)
        {
            return false;
        }

        double bestCustomArea = double.PositiveInfinity;
        for (int index = 0; index < customButtons.Count; index++)
        {
            CustomButton button = customButtons[index];
            if (!button.Rect.Contains(xNorm, yNorm))
            {
                continue;
            }

            if (button.Rect.Area < bestCustomArea)
            {
                bestCustomArea = button.Rect.Area;
                customButtonId = button.Id;
            }
        }

        if (!string.IsNullOrWhiteSpace(customButtonId))
        {
            return true;
        }

        double bestScore = double.NegativeInfinity;
        double bestArea = double.PositiveInfinity;
        for (int r = 0; r < layout.HitGeometries.Length; r++)
        {
            KeyHitGeometry[] rowGeometries = layout.HitGeometries[r];
            for (int c = 0; c < rowGeometries.Length; c++)
            {
                KeyHitGeometry geometry = rowGeometries[c];
                if (!geometry.Contains(xNorm, yNorm))
                {
                    continue;
                }

                double score = geometry.DistanceToEdge(xNorm, yNorm);
                if (score > bestScore || (Math.Abs(score - bestScore) <= 0.000001 && geometry.Area < bestArea))
                {
                    bestScore = score;
                    bestArea = geometry.Area;
                    row = r;
                    column = c;
                }
            }
        }

        return row >= 0 && column >= 0;
    }

    private void SelectKeyForEditing(TrackpadSide side, int row, int column)
    {
        _hasSelectedKey = true;
        _hasSelectedCustomButton = false;
        _selectedCustomButtonId = null;
        _selectedKeySide = side;
        _selectedKeyRow = row;
        _selectedKeyColumn = column;
        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private void SelectCustomButtonForEditing(TrackpadSide side, string buttonId)
    {
        _hasSelectedKey = false;
        _hasSelectedCustomButton = true;
        _selectedCustomButtonId = buttonId;
        _selectedKeySide = side;
        _selectedKeyRow = -1;
        _selectedKeyColumn = -1;
        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private void ClearSelectionForEditing()
    {
        _hasSelectedKey = false;
        _hasSelectedCustomButton = false;
        _selectedCustomButtonId = null;
        _selectedKeySide = TrackpadSide.Left;
        _selectedKeyRow = -1;
        _selectedKeyColumn = -1;
    }

    private void EnsureSelectedKeyStillValid()
    {
        if (!_hasSelectedKey && !_hasSelectedCustomButton)
        {
            return;
        }

        if (_hasSelectedCustomButton)
        {
            if (string.IsNullOrWhiteSpace(_selectedCustomButtonId) ||
                _renderedKeymap.FindCustomButton(GetSelectedLayer(), _selectedCustomButtonId) == null)
            {
                ClearSelectionForEditing();
            }

            return;
        }

        KeyLayout layout = _selectedKeySide == TrackpadSide.Left ? _leftRenderedLayout : _rightRenderedLayout;
        if (_selectedKeyRow < 0 ||
            _selectedKeyRow >= layout.Rects.Length ||
            _selectedKeyColumn < 0 ||
            (_selectedKeyRow < layout.Rects.Length && _selectedKeyColumn >= layout.Rects[_selectedKeyRow].Length))
        {
            ClearSelectionForEditing();
        }
    }

    private void RefreshKeymapEditor()
    {
        _suppressKeymapEditorEvents = true;
        if (IsReplayMode)
        {
            _keymapSelectionText.Text = "Selection: replay mode (editing disabled)";
            _keymapPrimaryCombo.IsEnabled = false;
            _keymapHoldCombo.IsEnabled = false;
            _customButtonDeleteButton.IsEnabled = false;
            _keyRotationBox.IsEnabled = false;
            _keymapClearSelectionButton.IsEnabled = false;
            _customButtonAddLeftButton.IsEnabled = false;
            _customButtonAddRightButton.IsEnabled = false;
            SetCustomButtonGeometryEditorEnabled(false);
            _suppressKeymapEditorEvents = false;
            return;
        }

        _keymapClearSelectionButton.IsEnabled = true;
        _customButtonAddLeftButton.IsEnabled = true;
        _customButtonAddRightButton.IsEnabled = true;
        if (TryGetSelectedCustomButton(out _, out CustomButton? selectedButton))
        {
            _keymapSelectionText.Text = $"Selection: custom button ({_selectedKeySide})";
            _keymapPrimaryCombo.IsEnabled = true;
            _keymapHoldCombo.IsEnabled = true;
            _customButtonDeleteButton.IsEnabled = true;
            _keyRotationBox.IsEnabled = false;
            SetCustomButtonGeometryEditorEnabled(true);

            string buttonPrimary = string.IsNullOrWhiteSpace(selectedButton!.Primary?.Label) ? "None" : selectedButton.Primary.Label;
            string buttonHold = selectedButton.Hold?.Label ?? "None";
            EnsureActionChoice(buttonPrimary);
            EnsureActionChoice(buttonHold);
            SetActionComboSelection(_keymapPrimaryCombo, buttonPrimary);
            SetActionComboSelection(_keymapHoldCombo, buttonHold);
            _customButtonXBox.Text = FormatNumber(selectedButton.Rect.X * 100.0);
            _customButtonYBox.Text = FormatNumber(selectedButton.Rect.Y * 100.0);
            _customButtonWidthBox.Text = FormatNumber(selectedButton.Rect.Width * 100.0);
            _customButtonHeightBox.Text = FormatNumber(selectedButton.Rect.Height * 100.0);
            _keyRotationBox.Text = string.Empty;
            _suppressKeymapEditorEvents = false;
            return;
        }

        if (!TryGetSelectedKeyPosition(out TrackpadSide side, out int row, out int column))
        {
            _keymapSelectionText.Text = "Selection: none";
            _keymapPrimaryCombo.IsEnabled = false;
            _keymapHoldCombo.IsEnabled = false;
            _customButtonDeleteButton.IsEnabled = false;
            _keyRotationBox.IsEnabled = false;
            SetCustomButtonGeometryEditorEnabled(false);
            SetActionComboSelection(_keymapPrimaryCombo, "None");
            SetActionComboSelection(_keymapHoldCombo, "None");
            ClearCustomButtonGeometryEditorValues();
            _keyRotationBox.Text = string.Empty;
            _suppressKeymapEditorEvents = false;
            return;
        }

        KeyLayout layout = side == TrackpadSide.Left ? _leftRenderedLayout : _rightRenderedLayout;
        if (row < 0 || row >= layout.Labels.Length || column < 0 || column >= layout.Labels[row].Length)
        {
            ClearSelectionForEditing();
            _keymapSelectionText.Text = "Selection: none";
            _suppressKeymapEditorEvents = false;
            return;
        }

        _keymapSelectionText.Text = $"Selection: {side} r{row + 1} c{column + 1}";
        _keymapPrimaryCombo.IsEnabled = true;
        _keymapHoldCombo.IsEnabled = true;
        _customButtonDeleteButton.IsEnabled = false;
        _keyRotationBox.IsEnabled = true;
        SetCustomButtonGeometryEditorEnabled(false);
        ClearCustomButtonGeometryEditorValues();
        string defaultLabel = layout.Labels[row][column];
        string storageKey = GridKeyPosition.StorageKey(side, row, column);
        KeyMapping mapping = _renderedKeymap.ResolveMapping(GetSelectedLayer(), storageKey, defaultLabel);
        string primary = string.IsNullOrWhiteSpace(mapping.Primary.Label) ? defaultLabel : mapping.Primary.Label;
        string hold = mapping.Hold?.Label ?? "None";
        EnsureActionChoice(primary);
        EnsureActionChoice(hold);
        SetActionComboSelection(_keymapPrimaryCombo, primary);
        SetActionComboSelection(_keymapHoldCombo, hold);
        _keyRotationBox.Text = FormatNumber(_renderedKeymap.ResolveKeyGeometry(storageKey).RotationDegrees);
        _suppressKeymapEditorEvents = false;
    }

    private void SetActionComboSelection(ComboBox combo, string value)
    {
        KeyActionChoice? choice = SelectKeyActionChoice(_keyActionChoices, value);
        if (choice != null)
        {
            combo.SelectedItem = choice;
            return;
        }

        combo.SelectedItem = SelectKeyActionChoice(_keyActionChoices, "None");
    }

    private static KeyActionChoice? SelectKeyActionChoice(IEnumerable<KeyActionChoice> choices, string? value)
    {
        string target = string.IsNullOrWhiteSpace(value) ? "None" : value.Trim();
        foreach (KeyActionChoice choice in choices)
        {
            if (string.Equals(choice.Value, target, StringComparison.OrdinalIgnoreCase))
            {
                return choice;
            }
        }

        return null;
    }

    private bool TryGetSelectedKeyPosition(out TrackpadSide side, out int row, out int column)
    {
        side = _selectedKeySide;
        row = _selectedKeyRow;
        column = _selectedKeyColumn;
        if (!_hasSelectedKey || _hasSelectedCustomButton)
        {
            return false;
        }

        return row >= 0 && column >= 0;
    }

    private bool TryGetSelectedCustomButton(out TrackpadSide side, out CustomButton? button)
    {
        side = _selectedKeySide;
        button = null;
        if (!_hasSelectedCustomButton || string.IsNullOrWhiteSpace(_selectedCustomButtonId))
        {
            return false;
        }

        button = _renderedKeymap.FindCustomButton(GetSelectedLayer(), _selectedCustomButtonId);
        return button != null;
    }

    private void SetCustomButtonGeometryEditorEnabled(bool enabled)
    {
        _customButtonXBox.IsEnabled = enabled;
        _customButtonYBox.IsEnabled = enabled;
        _customButtonWidthBox.IsEnabled = enabled;
        _customButtonHeightBox.IsEnabled = enabled;
    }

    private void ClearCustomButtonGeometryEditorValues()
    {
        _customButtonXBox.Text = string.Empty;
        _customButtonYBox.Text = string.Empty;
        _customButtonWidthBox.Text = string.Empty;
        _customButtonHeightBox.Text = string.Empty;
    }

    private void OnKeyGeometryCommitted(object? sender, RoutedEventArgs e)
    {
        if (_suppressKeymapEditorEvents || IsReplayMode)
        {
            return;
        }

        ApplySelectedKeyGeometryFromUi();
    }

    private void OnKeyGeometryKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || _suppressKeymapEditorEvents || IsReplayMode)
        {
            return;
        }

        ApplySelectedKeyGeometryFromUi();
        e.Handled = true;
    }

    private void ApplySelectedKeymapOverride()
    {
        int layer = GetSelectedLayer();
        string selectedPrimary = ReadActionSelection(_keymapPrimaryCombo, "None");
        string selectedHold = ReadActionSelection(_keymapHoldCombo, "None");
        string? hold = string.Equals(selectedHold, "None", StringComparison.OrdinalIgnoreCase) ? null : selectedHold;

        EnsureActionChoice(selectedPrimary);
        if (hold != null)
        {
            EnsureActionChoice(hold);
        }

        if (TryGetSelectedCustomButton(out _, out CustomButton? selectedButton))
        {
            selectedButton!.Primary ??= new KeyAction();
            selectedButton.Primary.Label = selectedPrimary;
            selectedButton.Hold = hold == null ? null : new KeyAction { Label = hold };
            selectedButton.Layer = layer;

            if (!TryPersistEditedKeymap(out string error))
            {
                ShowNoticeDialog("Keymap Save Failed", error);
                return;
            }

            RefreshKeymapEditor();
            ApplyPreviewSnapshot(_previewSnapshot);
            return;
        }

        if (!TryGetSelectedKeyPosition(out TrackpadSide side, out int row, out int column))
        {
            return;
        }

        string storageKey = GridKeyPosition.StorageKey(side, row, column);

        if (!_renderedKeymap.Mappings.TryGetValue(layer, out Dictionary<string, KeyMapping>? layerMap))
        {
            layerMap = new Dictionary<string, KeyMapping>();
            _renderedKeymap.Mappings[layer] = layerMap;
        }

        layerMap[storageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = selectedPrimary },
            Hold = hold == null ? null : new KeyAction { Label = hold }
        };

        if (!TryPersistEditedKeymap(out string saveError))
        {
            ShowNoticeDialog("Keymap Save Failed", saveError);
            return;
        }

        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private void ApplySelectedKeyGeometryFromUi()
    {
        if (!TryGetSelectedKeyPosition(out TrackpadSide side, out int row, out int column) || _hasSelectedCustomButton)
        {
            return;
        }

        string storageKey = GridKeyPosition.StorageKey(side, row, column);
        double currentRotation = _renderedKeymap.ResolveKeyGeometry(storageKey).RotationDegrees;
        double nextRotation = Math.Clamp(ReadDouble(_keyRotationBox, currentRotation), 0.0, 360.0);
        _renderedKeymap.SetKeyGeometry(storageKey, nextRotation);
        if (!TryPersistEditedKeymap(out string error))
        {
            ShowNoticeDialog("Keymap Save Failed", error);
            return;
        }

        RenderLayoutsFromCurrentKeymap();
        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private void OnCustomButtonAddLeftClicked(object? sender, RoutedEventArgs e)
    {
        AddCustomButton(TrackpadSide.Left);
    }

    private void OnCustomButtonAddRightClicked(object? sender, RoutedEventArgs e)
    {
        AddCustomButton(TrackpadSide.Right);
    }

    private void AddCustomButton(TrackpadSide side)
    {
        if (IsReplayMode)
        {
            return;
        }

        int layer = GetSelectedLayer();
        List<CustomButton> buttons = _renderedKeymap.GetOrCreateCustomButtons(layer);
        CustomButton button = new()
        {
            Id = Guid.NewGuid().ToString("N"),
            Side = side,
            Rect = KeymapStore.ClampCustomButtonRect(new NormalizedRect(0.41, 0.43, 0.18, 0.14)),
            Primary = new KeyAction { Label = "Space" },
            Hold = null,
            Layer = layer
        };
        buttons.Add(button);

        if (!TryPersistEditedKeymap(out string error))
        {
            buttons.Remove(button);
            ShowNoticeDialog("Keymap Save Failed", error);
            return;
        }

        SelectCustomButtonForEditing(side, button.Id);
    }

    private void OnCustomButtonDeleteClicked(object? sender, RoutedEventArgs e)
    {
        if (IsReplayMode || !TryGetSelectedCustomButton(out _, out CustomButton? selectedButton))
        {
            return;
        }

        int layer = GetSelectedLayer();
        if (!_renderedKeymap.RemoveCustomButton(layer, selectedButton!.Id))
        {
            return;
        }

        if (!TryPersistEditedKeymap(out string error))
        {
            ShowNoticeDialog("Keymap Save Failed", error);
            return;
        }

        ClearSelectionForEditing();
        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private void OnCustomButtonGeometryCommitted(object? sender, RoutedEventArgs e)
    {
        if (_suppressKeymapEditorEvents || IsReplayMode)
        {
            return;
        }

        ApplySelectedCustomButtonGeometryFromUi();
    }

    private void OnCustomButtonGeometryKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || _suppressKeymapEditorEvents || IsReplayMode)
        {
            return;
        }

        ApplySelectedCustomButtonGeometryFromUi();
        e.Handled = true;
    }

    private void OnWindowKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape || (!_hasSelectedKey && !_hasSelectedCustomButton))
        {
            return;
        }

        ClearSelectionForEditing();
        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
        e.Handled = true;
    }

    private void ApplySelectedCustomButtonGeometryFromUi()
    {
        if (!TryGetSelectedCustomButton(out _, out CustomButton? selectedButton))
        {
            return;
        }

        double xPercent = ReadDouble(_customButtonXBox, selectedButton!.Rect.X * 100.0);
        double yPercent = ReadDouble(_customButtonYBox, selectedButton.Rect.Y * 100.0);
        double widthPercent = ReadDouble(_customButtonWidthBox, selectedButton.Rect.Width * 100.0);
        double heightPercent = ReadDouble(_customButtonHeightBox, selectedButton.Rect.Height * 100.0);

        double width = Math.Clamp(widthPercent / 100.0, MinCustomButtonPercent / 100.0, 1.0);
        double height = Math.Clamp(heightPercent / 100.0, MinCustomButtonPercent / 100.0, 1.0);
        double x = Math.Clamp(xPercent / 100.0, 0.0, 1.0 - width);
        double y = Math.Clamp(yPercent / 100.0, 0.0, 1.0 - height);

        selectedButton.Rect = KeymapStore.ClampCustomButtonRect(new NormalizedRect(x, y, width, height));
        selectedButton.Layer = GetSelectedLayer();

        if (!TryPersistEditedKeymap(out string error))
        {
            ShowNoticeDialog("Keymap Save Failed", error);
            return;
        }

        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private bool TryPersistEditedKeymap(out string error)
    {
        ReloadKeymapActionChoices(_renderedKeymap);
        if (!_runtime.TrySaveKeymap(_renderedKeymap, out _, out string message))
        {
            error = message;
            return false;
        }

        error = string.Empty;
        return true;
    }

    private void RenderLayoutsFromCurrentKeymap()
    {
        TrackpadLayoutPreset preset = (_layoutPresetCombo.SelectedItem as PresetChoice)?.Name is string name
            ? TrackpadLayoutPreset.ResolveByNameOrDefault(name)
            : TrackpadLayoutPreset.SixByThree;
        LinuxHostSettings settings = _runtime.LoadSettings();
        UserSettings profile = settings.GetSharedProfile();
        _renderedKeymap.SetActiveLayout(preset.Name);
        ColumnLayoutSettings[] columns = RuntimeConfigurationFactory.BuildColumnSettingsForPreset(
            profile,
            preset);
        RuntimeConfigurationFactory.BuildLayouts(
            profile,
            _renderedKeymap,
            preset,
            columns,
            out KeyLayout leftLayout,
            out KeyLayout rightLayout);
        _leftRenderedLayout = leftLayout;
        _rightRenderedLayout = rightLayout;
    }

    private static string ReadActionSelection(ComboBox combo, string fallback)
    {
        if (combo.SelectedItem is KeyActionChoice choice && !string.IsNullOrWhiteSpace(choice.Value))
        {
            return choice.Value;
        }

        if (!string.IsNullOrWhiteSpace(combo.SelectedItem?.ToString()))
        {
            return combo.SelectedItem!.ToString()!;
        }

        if (combo.SelectedItem is string raw && !string.IsNullOrWhiteSpace(raw))
        {
            return raw;
        }

        return fallback;
    }

    private static double ReadDouble(TextBox box, double fallback)
    {
        string text = box.Text ?? string.Empty;
        if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out double parsed))
        {
            return parsed;
        }

        if (double.TryParse(text, NumberStyles.Float, CultureInfo.CurrentCulture, out parsed))
        {
            return parsed;
        }

        return fallback;
    }

    private static string FormatNumber(double value)
    {
        return value.ToString("0.##", CultureInfo.InvariantCulture);
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
        if (IsReplayMode)
        {
            ExitReplayMode();
        }

        if (_desktopRuntime.IsCapturingAtpCap)
        {
            LinuxDesktopAtpCapCaptureResult existingCapture = await _desktopRuntime.StopAtpCapCaptureAsync();
            NotifyCaptureStateChanged();
            if (!existingCapture.Success)
            {
                ShowNoticeDialog("Capture Failed", existingCapture.Summary);
            }
            return;
        }

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
            SuggestedFileName = $"glasstokey-{DateTime.Now:yyyyMMdd-HHmmss}.atpcap",
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
            NotifyCaptureStateChanged();
            return;
        }

        NotifyCaptureStateChanged();
    }

    public async Task ReplayAtpCapFromStatusAreaAsync()
    {
        if (_desktopRuntime.IsCapturingAtpCap)
        {
            LinuxDesktopAtpCapCaptureResult captureResult = await _desktopRuntime.StopAtpCapCaptureAsync();
            NotifyCaptureStateChanged();
            if (!captureResult.Success)
            {
                ShowNoticeDialog("Capture Failed", captureResult.Summary);
                return;
            }
        }

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
            LinuxAtpCapReplayVisualData replayData = LinuxAtpCapReplayVisualLoader.Load(localPath, configuration);
            EnterReplayMode(replayData);
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
        if (_hideInProgress)
        {
            return;
        }

        _hideInProgress = true;
        _ = HideToStatusAreaAsync();
    }

    public bool IsCapturingAtpCap => _desktopRuntime.IsCapturingAtpCap;

    private async Task HideToStatusAreaAsync()
    {
        try
        {
            if (_desktopRuntime.IsCapturingAtpCap)
            {
                await _desktopRuntime.StopAtpCapCaptureAsync();
                NotifyCaptureStateChanged();
            }

            Hide();
        }
        finally
        {
            _hideInProgress = false;
        }
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
            NotifyCaptureStateChanged();
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
        return _runtime.TryImportProfile(path, out message);
    }

    private bool TryExportSettings(string path, out string message)
    {
        return _runtime.TryExportProfile(path, out message);
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
            if (_hideInProgress)
            {
                return;
            }

            _hideInProgress = true;
            _ = HideToStatusAreaAsync();
        }
    }

    private void OnWindowOpened(object? sender, EventArgs e)
    {
        if (IsReplayMode)
        {
            ApplyReplayVisualState();
            return;
        }

        ApplyPreviewSnapshot(_desktopRuntime.PreviewSnapshot);
        ApplyRuntimeStatus(_desktopRuntime.RuntimeSnapshot);
    }

    public void EnsurePreviewActive()
    {
        if (IsReplayMode)
        {
            ApplyReplayVisualState();
            return;
        }

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

    private bool IsReplayMode => _replayData != null;

    private void EnterReplayMode(LinuxAtpCapReplayVisualData replayData)
    {
        PauseReplay();
        _replayData = replayData;
        _replayFrameIndex = 0;
        _replayAccumulatedTicks = 0;
        _replayCompleted = false;
        _replayPanel.IsVisible = true;
        _replayToggleButton.Content = "Play";
        UpdateReplayControls();
        RefreshKeymapEditor();
        ApplyReplayVisualState();
        Activate();
    }

    private void ReloadReplayMode(LinuxRuntimeConfiguration configuration)
    {
        if (_replayData == null)
        {
            return;
        }

        double progressTicks = _replayRunning
            ? ClampReplayProgress(GetReplayProgressTicks(Stopwatch.GetTimestamp()))
            : ClampReplayProgress(_replayAccumulatedTicks);
        bool wasRunning = _replayRunning;
        string sourcePath = _replayData.SourcePath;
        PauseReplay();
        LinuxAtpCapReplayVisualData refreshed = LinuxAtpCapReplayVisualLoader.Load(sourcePath, configuration);
        _replayData = refreshed;
        _replayCompleted = false;
        SeekToProgressTicks(progressTicks);
        if (wasRunning)
        {
            StartReplay();
        }
        else
        {
            ApplyReplayVisualState();
        }
    }

    private void ExitReplayMode()
    {
        PauseReplay();
        _replayData = null;
        _replayFrameIndex = 0;
        _replayAccumulatedTicks = 0;
        _replayCompleted = false;
        _replayPanel.IsVisible = false;
        UpdateReplayControls();
        RefreshKeymapEditor();
        ApplyRuntimeStatus(_desktopRuntime.RuntimeSnapshot);
        ApplyPreviewSnapshot(_desktopRuntime.PreviewSnapshot);
    }

    private void ApplyReplayVisualState()
    {
        if (_replayData == null)
        {
            return;
        }

        LinuxAtpCapReplayVisualFrame? current = GetCurrentReplayFrame();
        if (current is null)
        {
            _leftPreviewCanvas.Children.Clear();
            _rightPreviewCanvas.Children.Clear();
            ApplyReplayStatus(null);
            UpdateReplayControls();
            return;
        }

        ApplyReplayStatus(current.Value);
        ApplyPreviewSnapshot(current.Value.PreviewSnapshot);
        UpdateReplayControls();
    }

    private void ApplyReplayStatus(LinuxAtpCapReplayVisualFrame? frame)
    {
        if (frame is null)
        {
            _runtimeTypingStatusText.Text = "Replay: empty capture";
            _runtimeTypingStatusText.Foreground = new SolidColorBrush(Color.Parse("#D9C7B5"));
            return;
        }

        LinuxDesktopRuntimeSnapshot runtimeSnapshot = frame.Value.RuntimeSnapshot;
        string typing = runtimeSnapshot.TypingEnabled ? "on" : "off";
        string state = _replayRunning ? "playing" : (_replayCompleted ? "complete" : "paused");
        _runtimeTypingStatusText.Text = $"Replay: {state} | Typing: {typing} | Layer: {runtimeSnapshot.ActiveLayer}";
        _runtimeTypingStatusText.Foreground = new SolidColorBrush(Color.Parse("#F7F2EA"));
    }

    private LinuxAtpCapReplayVisualFrame? GetCurrentReplayFrame()
    {
        if (_replayData == null || _replayData.Frames.Length == 0)
        {
            return null;
        }

        if (_replayFrameIndex <= 0)
        {
            return _replayData.Frames[0];
        }

        int index = Math.Min(_replayFrameIndex - 1, _replayData.Frames.Length - 1);
        return _replayData.Frames[index];
    }

    private void OnReplayToggleClick(object? sender, RoutedEventArgs e)
    {
        if (!IsReplayMode)
        {
            return;
        }

        if (_replayRunning)
        {
            PauseReplay();
            return;
        }

        StartReplay();
    }

    private void OnReplayCloseClick(object? sender, RoutedEventArgs e)
    {
        ExitReplayMode();
    }

    private void OnReplaySpeedChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (!IsReplayMode || _suppressReplaySpeedEvents || _replaySpeedCombo.SelectedItem is not ReplaySpeedOption option)
        {
            return;
        }

        long now = Stopwatch.GetTimestamp();
        if (_replayRunning)
        {
            _replayAccumulatedTicks = ClampReplayProgress(GetReplayProgressTicks(now));
            _replayPlayStartTicks = now;
        }

        _replaySpeed = option.Speed;
        UpdateReplayControls();
    }

    private void OnReplayTimelinePropertyChanged(object? sender, AvaloniaPropertyChangedEventArgs e)
    {
        if (e.Property != RangeBase.ValueProperty || !IsReplayMode || _suppressReplayTimelineEvents)
        {
            return;
        }

        bool wasRunning = _replayRunning;
        PauseReplay();
        double ratio = _replayTimelineSlider.Maximum <= 0 ? 0 : _replayTimelineSlider.Value / _replayTimelineSlider.Maximum;
        double targetTicks = ratio * (_replayData?.DurationStopwatchTicks ?? 0);
        SeekToProgressTicks(targetTicks);
        if (wasRunning)
        {
            StartReplay();
        }
    }

    private void StartReplay()
    {
        if (_replayData == null || _replayData.Frames.Length == 0)
        {
            return;
        }

        if (_replayCompleted)
        {
            _replayFrameIndex = 0;
            _replayAccumulatedTicks = 0;
            _replayCompleted = false;
        }

        _replayRunning = true;
        _replayPlayStartTicks = Stopwatch.GetTimestamp();
        _replayTimer.Start();
        _replayToggleButton.Content = "Pause";
        UpdateReplayControls();
    }

    private void PauseReplay()
    {
        if (!_replayRunning)
        {
            return;
        }

        _replayAccumulatedTicks = ClampReplayProgress(GetReplayProgressTicks(Stopwatch.GetTimestamp()));
        _replayRunning = false;
        _replayTimer.Stop();
        _replayToggleButton.Content = _replayCompleted ? "Replay" : "Play";
        UpdateReplayControls();
    }

    private void OnReplayTick(object? sender, EventArgs e)
    {
        if (_replayData == null || !_replayRunning)
        {
            return;
        }

        double progressTicks = GetReplayProgressTicks(Stopwatch.GetTimestamp());
        if (progressTicks >= _replayData.DurationStopwatchTicks)
        {
            SeekToProgressTicks(_replayData.DurationStopwatchTicks);
            _replayCompleted = true;
            PauseReplay();
            return;
        }

        SeekToProgressTicks(progressTicks);
    }

    private double GetReplayProgressTicks(long nowTicks)
    {
        double progress = _replayAccumulatedTicks;
        if (_replayRunning)
        {
            progress += (nowTicks - _replayPlayStartTicks) * _replaySpeed;
        }

        return progress;
    }

    private double ClampReplayProgress(double progressTicks)
    {
        if (_replayData == null)
        {
            return 0;
        }

        if (progressTicks < 0)
        {
            return 0;
        }

        if (progressTicks > _replayData.DurationStopwatchTicks)
        {
            return _replayData.DurationStopwatchTicks;
        }

        return progressTicks;
    }

    private void SeekToProgressTicks(double progressTicks)
    {
        if (_replayData == null)
        {
            return;
        }

        double clamped = ClampReplayProgress(progressTicks);
        _replayAccumulatedTicks = clamped;
        if (_replayRunning)
        {
            _replayPlayStartTicks = Stopwatch.GetTimestamp();
        }

        _replayFrameIndex = ResolveReplayFrameIndexForProgress(clamped);
        _replayCompleted = _replayFrameIndex >= _replayData.Frames.Length && _replayData.Frames.Length > 0;
        _replayToggleButton.Content = _replayCompleted ? "Replay" : (_replayRunning ? "Pause" : "Play");
        ApplyReplayVisualState();
    }

    private int ResolveReplayFrameIndexForProgress(double progressTicks)
    {
        if (_replayData == null || _replayData.Frames.Length == 0)
        {
            return 0;
        }

        int lo = 0;
        int hi = _replayData.Frames.Length;
        while (lo < hi)
        {
            int mid = lo + ((hi - lo) >> 1);
            if (_replayData.Frames[mid].OffsetStopwatchTicks <= progressTicks)
            {
                lo = mid + 1;
            }
            else
            {
                hi = mid;
            }
        }

        return lo;
    }

    private void UpdateReplayControls()
    {
        bool hasFrames = _replayData != null && _replayData.Frames.Length > 0;
        _replayPanel.IsVisible = IsReplayMode;
        _replayToggleButton.IsEnabled = hasFrames;
        _replayCloseButton.IsEnabled = IsReplayMode;
        _replayTimelineSlider.IsEnabled = hasFrames;
        _replaySpeedCombo.IsEnabled = hasFrames;

        double durationTicks = _replayData?.DurationStopwatchTicks ?? 0;
        double progressTicks = _replayRunning
            ? ClampReplayProgress(GetReplayProgressTicks(Stopwatch.GetTimestamp()))
            : ClampReplayProgress(_replayAccumulatedTicks);
        double ratio = durationTicks <= 0 ? 0 : progressTicks / durationTicks;
        _suppressReplayTimelineEvents = true;
        _replayTimelineSlider.Value = ratio * _replayTimelineSlider.Maximum;
        _suppressReplayTimelineEvents = false;
        _replayTimeText.Text = $"{progressTicks / Stopwatch.Frequency:0.00}s / {durationTicks / Stopwatch.Frequency:0.00}s";
    }

    private void ShowNoticeDialog(string title, string message)
    {
        _noticeTitleText.Text = title;
        _noticeMessageText.Text = message;
        _noticeOverlay.IsVisible = true;
        if (!IsVisible)
        {
            Show();
        }

        Activate();
    }

    private void NotifyCaptureStateChanged()
    {
        CaptureStateChanged?.Invoke(_desktopRuntime.IsCapturingAtpCap);
    }

    private void HideNoticeDialog()
    {
        _noticeOverlay.IsVisible = false;
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

        if (IsReplayMode)
        {
            return;
        }

        ApplyRuntimeStatus(snapshot);
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private void OnPreviewSnapshotChanged(LinuxInputPreviewSnapshot snapshot)
    {
        if (IsReplayMode)
        {
            return;
        }

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
        int activeLayer = Math.Clamp(GetSelectedLayer(), 0, 7);
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

    private void RenderPreviewCanvas(
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
        _renderedKeymap.SetActiveLayout(configuration.LayoutPreset.Name);
    }

    private void RenderPreviewKeymapOverlay(
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
                bool selected = _hasSelectedKey &&
                                !_hasSelectedCustomButton &&
                                _selectedKeySide == side &&
                                _selectedKeyRow == row &&
                                _selectedKeyColumn == col;

                Border keyBorder = new()
                {
                    Width = Math.Max(22, rect.Width * width),
                    Height = Math.Max(20, rect.Height * height),
                    Background = new SolidColorBrush(accent, selected ? 0.22 : 0.08),
                    BorderBrush = selected
                        ? new SolidColorBrush(Color.Parse("#E07845"), 0.90)
                        : new SolidColorBrush(accent, 0.25),
                    BorderThickness = new Thickness(selected ? 2.5 : 1),
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
            bool selected = _hasSelectedCustomButton &&
                            _selectedKeySide == side &&
                            string.Equals(_selectedCustomButtonId, button.Id, StringComparison.Ordinal);
            Border customBorder = new()
            {
                Width = Math.Max(24, button.Rect.Width * width),
                Height = Math.Max(20, button.Rect.Height * height),
                Background = new SolidColorBrush(Color.Parse("#E07845"), selected ? 0.30 : 0.20),
                BorderBrush = new SolidColorBrush(Color.Parse("#E07845"), selected ? 0.95 : 0.65),
                BorderThickness = new Thickness(selected ? 3.0 : 1.5),
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

    private sealed record LayerChoice(string Label, int Layer)
    {
        public override string ToString()
        {
            return Label;
        }
    }

    private sealed record KeyActionChoice(string Label, string Value)
    {
        public override string ToString()
        {
            return Label;
        }
    }

    private sealed record ReplaySpeedOption(double Speed, string Label)
    {
        public override string ToString()
        {
            return Label;
        }
    }
}
