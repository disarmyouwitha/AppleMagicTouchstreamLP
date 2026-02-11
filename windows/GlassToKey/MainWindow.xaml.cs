using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics.CodeAnalysis;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using Microsoft.Win32;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Interop;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace GlassToKey;

public partial class MainWindow : Window, IRuntimeFrameObserver
{
    private const double TrackpadWidthMm = 160.0;
    private const double TrackpadHeightMm = 114.9;
    private const double KeyWidthMm = 18.0;
    private const double KeyHeightMm = 17.0;
    private const double ControlsPaneExpandedWidth = 360.0;
    private const double ControlsPaneCollapsedWidth = 0.0;
    private const double MinCustomButtonPercent = 5.0;
    private const ushort DefaultMaxX = 7612;
    private const ushort DefaultMaxY = 5065;
    private static readonly Brush IntentIdleBrush = CreateFrozenBrush("#8b949e");
    private static readonly Brush IntentCandidateBrush = CreateFrozenBrush("#f39c12");
    private static readonly Brush IntentTypingBrush = CreateFrozenBrush("#2ecc71");
    private static readonly Brush IntentMouseBrush = CreateFrozenBrush("#3498db");
    private static readonly Brush IntentGestureBrush = CreateFrozenBrush("#9b59b6");
    private static readonly Brush IntentUnknownBrush = CreateFrozenBrush("#6b7279");
    private static readonly Brush ModeKeyboardBrush = CreateFrozenBrush("#9b59b6");
    private static readonly Brush ModeMixedBrush = CreateFrozenBrush("#2ecc71");
    private static readonly Brush ModeMouseBrush = CreateFrozenBrush("#e74c3c");
    private static readonly Brush ModeUnknownBrush = CreateFrozenBrush("#6b7279");
    private static readonly DecoderProfileOption[] DecoderProfileOptions =
    {
        new(TrackpadDecoderProfile.Official, "Official"),
        new(TrackpadDecoderProfile.Legacy, "Opensource")
    };

    private readonly ReaderOptions _options;
    private readonly TouchRuntimeService? _runtimeService;
    private readonly ObservableCollection<HidDeviceInfo> _devices = new();
    private readonly ReaderSession _left = new("Left");
    private readonly ReaderSession _right = new("Right");
    private readonly UserSettings _settings;
    private readonly KeymapStore _keymap;
    private readonly ObservableCollection<KeyActionOption> _keyActionOptions = new();
    private readonly HashSet<string> _keyActionOptionLookup = new(StringComparer.OrdinalIgnoreCase);
    private TrackpadLayoutPreset _preset;
    private ColumnLayoutSettings[] _columnSettings;
    private readonly RawInputContext _rawInputContext = new();
    private readonly FrameMetrics _liveMetrics = new("live");
    private readonly InputCaptureWriter? _captureWriter;
    private readonly ReplayVisualData? _replayData;
    private readonly DispatcherTimer? _replayTimer;
    private readonly DispatcherTimer? _statusTimer;
    private readonly TouchProcessorCore? _touchCore;
    private readonly TouchProcessorActor? _touchActor;
    private readonly DispatchEventQueue? _dispatchQueue;
    private readonly DispatchEventPump? _dispatchPump;
    private KeyLayout _leftLayout;
    private KeyLayout _rightLayout;
    private int _activeLayer;
    private bool _suppressSelectionEvents;
    private bool _suppressDecoderProfileEvents;
    private bool _suppressLayerEvent;
    private bool _suppressReplaySpeedEvents;
    private bool _suppressReplayTimelineEvents;
    private HwndSource? _hwndSource;
    private readonly GlobalMouseClickSuppressor _globalClickSuppressor = new();
    private bool _suppressGlobalClicks;
    private string _leftStatus = "None";
    private string _rightStatus = "None";
    private string _lastLeftHit = "--";
    private string _lastRightHit = "--";
    private bool _replayRunning;
    private bool _replayCompleted;
    private bool _replayLoop;
    private int _replayFrameIndex;
    private long _replayPlayStartTicks;
    private long _replayDurationTicks;
    private double _replayAccumulatedTicks;
    private double _replaySpeed = 1.0;
    private string _engineStateText = "State: n/a";
    private bool _visualizerEnabled = true;
    private bool _suppressSettingsEvents;
    private bool _suppressKeymapActionEvents;
    private bool _hasSelectedKey;
    private bool _hasSelectedCustomButton;
    private TrackpadSide _selectedKeySide = TrackpadSide.Left;
    private int _selectedKeyRow = -1;
    private int _selectedKeyColumn = -1;
    private string? _selectedCustomButtonId;
    private bool _controlsPaneVisible = true;
    private int _lastLeftPillCount = -1;
    private int _lastRightPillCount = -1;
    private string _lastIntentPillLabel = string.Empty;
    private Brush _lastIntentPillBrush = IntentUnknownBrush;
    private string _lastModePillLabel = string.Empty;
    private Brush _lastModePillBrush = ModeUnknownBrush;
    private int _lastEngineVisualLayer = -1;
    private long _rawInputPauseUntilTicks;
    private long _lastRawInputFaultTicks;
    private int _consecutiveRawInputFaults;
    private Dictionary<string, TrackpadDecoderProfile> _decoderProfilesByPath = new(StringComparer.OrdinalIgnoreCase);
    private TrackpadDecoderProfile? _lastDecoderProfileLeft;
    private TrackpadDecoderProfile? _lastDecoderProfileRight;
    private long _lastDecoderProfileLogLeftTicks;
    private long _lastDecoderProfileLogRightTicks;

    private bool IsReplayMode => _replayData != null;
    private bool UsesSharedRuntime => !IsReplayMode && _runtimeService != null;

    private static Brush CreateFrozenBrush(string colorHex)
    {
        Color color = (Color)ColorConverter.ConvertFromString(colorHex);
        SolidColorBrush brush = new(color);
        brush.Freeze();
        return brush;
    }

    internal MainWindow(ReaderOptions options, TouchRuntimeService? runtimeService = null)
    {
        InitializeComponent();
        _options = options;
        _runtimeService = runtimeService;
        _settings = UserSettings.Load();
        _decoderProfilesByPath = TrackpadDecoderProfileMap.BuildFromSettings(_settings);
        if (!_settings.VisualizerEnabled)
        {
            _settings.VisualizerEnabled = true;
            _settings.Save();
        }
        _keymap = KeymapStore.Load();
        _preset = TrackpadLayoutPreset.ResolveByNameOrDefault(_settings.LayoutPresetName);
        _keymap.SetActiveLayout(_preset.Name);
        _columnSettings = BuildColumnSettingsForPreset(_settings, _preset);
        if (!string.IsNullOrWhiteSpace(options.CapturePath))
        {
            _captureWriter = new InputCaptureWriter(Path.GetFullPath(options.CapturePath));
        }
        if (options.ReplayInUi && !string.IsNullOrWhiteSpace(options.ReplayPath))
        {
            _replayData = ReplayVisualLoader.Load(Path.GetFullPath(options.ReplayPath));
            _replayDurationTicks = _replayData.Frames.Length == 0 ? 0 : _replayData.Frames[^1].OffsetStopwatchTicks;
            _replaySpeed = options.ReplaySpeed;
            _replayTimer = new DispatcherTimer(DispatcherPriority.Render)
            {
                Interval = TimeSpan.FromMilliseconds(4)
            };
            _replayTimer.Tick += OnReplayTick;
        }
        else
        {
            _statusTimer = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = TimeSpan.FromMilliseconds(50)
            };
            _statusTimer.Tick += OnStatusTimerTick;
            _statusTimer.Start();
        }

        RuntimeConfigurationFactory.BuildLayouts(_settings, _preset, _columnSettings, out _leftLayout, out _rightLayout);

        LeftSurface.State = _left.State;
        RightSurface.State = _right.State;
        LeftSurface.TrackpadWidthMm = TrackpadWidthMm;
        LeftSurface.TrackpadHeightMm = TrackpadHeightMm;
        RightSurface.TrackpadWidthMm = TrackpadWidthMm;
        RightSurface.TrackpadHeightMm = TrackpadHeightMm;
        LeftSurface.RequestedMaxX = options.MaxX ?? DefaultMaxX;
        LeftSurface.RequestedMaxY = options.MaxY ?? DefaultMaxY;
        RightSurface.RequestedMaxX = options.MaxX ?? DefaultMaxX;
        RightSurface.RequestedMaxY = options.MaxY ?? DefaultMaxY;
        LeftSurface.EmptyMessage = "No device selected.";
        RightSurface.EmptyMessage = "No device selected.";
        LeftSurface.Layout = _leftLayout;
        RightSurface.Layout = _rightLayout;

        RefreshButton.Click += (_, _) => LoadDevices(preserveSelection: true);
        LeftDeviceCombo.SelectionChanged += OnLeftSelectionChanged;
        RightDeviceCombo.SelectionChanged += OnRightSelectionChanged;
        LeftDecoderProfileCombo.SelectionChanged += OnLeftDecoderProfileSelectionChanged;
        RightDecoderProfileCombo.SelectionChanged += OnRightDecoderProfileSelectionChanged;
        LayerCombo.SelectionChanged += OnLayerSelectionChanged;
        ReplayToggleButton.Click += OnReplayToggleClicked;
        ReplaySpeedCombo.SelectionChanged += OnReplaySpeedChanged;
        ReplayStepBackButton.Click += OnReplayStepBackClicked;
        ReplayStepForwardButton.Click += OnReplayStepForwardClicked;
        ReplayLoopCheckBox.Checked += OnReplayLoopChanged;
        ReplayLoopCheckBox.Unchecked += OnReplayLoopChanged;
        ReplayTimelineSlider.ValueChanged += OnReplayTimelineChanged;
        LayoutPresetCombo.SelectionChanged += OnLayoutPresetChanged;
        ColumnLayoutColumnCombo.SelectionChanged += OnColumnLayoutSelectionChanged;
        ToggleControlsButton.Click += OnToggleControlsPaneClicked;
        KeymapExportButton.Click += OnKeymapExportClicked;
        KeymapImportButton.Click += OnKeymapImportClicked;
        TapClickEnabledCheck.Checked += OnModeSettingChanged;
        TapClickEnabledCheck.Unchecked += OnModeSettingChanged;
        KeyboardModeCheck.Checked += OnModeSettingChanged;
        KeyboardModeCheck.Unchecked += OnModeSettingChanged;
        SnapRadiusModeCheck.Checked += OnModeSettingChanged;
        SnapRadiusModeCheck.Unchecked += OnModeSettingChanged;
        ChordShiftCheck.Checked += OnModeSettingChanged;
        ChordShiftCheck.Unchecked += OnModeSettingChanged;
        RunAtStartupCheck.Checked += OnModeSettingChanged;
        RunAtStartupCheck.Unchecked += OnModeSettingChanged;
        KeymapPrimaryCombo.SelectionChanged += OnKeymapActionSelectionChanged;
        KeymapHoldCombo.SelectionChanged += OnKeymapActionSelectionChanged;
        CustomButtonAddLeftButton.Click += OnCustomButtonAddLeftClicked;
        CustomButtonAddRightButton.Click += OnCustomButtonAddRightClicked;
        CustomButtonDeleteButton.Click += OnCustomButtonDeleteClicked;
        CustomButtonXBox.LostKeyboardFocus += OnCustomButtonGeometryCommitted;
        CustomButtonYBox.LostKeyboardFocus += OnCustomButtonGeometryCommitted;
        CustomButtonWidthBox.LostKeyboardFocus += OnCustomButtonGeometryCommitted;
        CustomButtonHeightBox.LostKeyboardFocus += OnCustomButtonGeometryCommitted;
        CustomButtonXBox.KeyDown += OnCustomButtonGeometryKeyDown;
        CustomButtonYBox.KeyDown += OnCustomButtonGeometryKeyDown;
        CustomButtonWidthBox.KeyDown += OnCustomButtonGeometryKeyDown;
        CustomButtonHeightBox.KeyDown += OnCustomButtonGeometryKeyDown;
        KeyDown += OnWindowKeyDown;
        LeftSurface.MouseLeftButtonDown += OnLeftSurfaceMouseLeftButtonDown;
        RightSurface.MouseLeftButtonDown += OnRightSurfaceMouseLeftButtonDown;
        SourceInitialized += OnSourceInitialized;
        HookTuningAutoApplyHandlers();

        InitializeLayerCombo();
        InitializeSettingsPanel();
        if (!UsesSharedRuntime)
        {
            _touchCore = TouchProcessorFactory.CreateDefault(_keymap, _preset, BuildConfigFromSettings());
            _dispatchQueue = new DispatchEventQueue();
            _touchActor = new TouchProcessorActor(_touchCore, dispatchQueue: _dispatchQueue);
            _dispatchPump = new DispatchEventPump(_dispatchQueue, new SendInputDispatcher());
            _touchActor.SetPersistentLayer(_activeLayer);
            _touchActor.SetTypingEnabled(_settings.TypingEnabled);
            _touchActor.SetKeyboardModeEnabled(_settings.KeyboardModeEnabled);
            _touchActor.SetAllowMouseTakeover(_settings.AllowMouseTakeover);
            _suppressGlobalClicks = _settings.KeyboardModeEnabled && _settings.TypingEnabled;
        }

        ApplyCoreSettings();

        InitializeReplayControls();
        UpdateLabelMatrices();
        ApplyVisualizerEnabled(true, persist: false);
        UpdateEngineStateDetails();

        Loaded += (_, _) =>
        {
            if (IsReplayMode)
            {
                LoadReplayDevices();
                StartReplay();
            }
            else
            {
                LoadDevices(preserveSelection: false);
                _runtimeService?.SetFrameObserver(this);
            }
        };
        Closed += (_, _) =>
        {
            _runtimeService?.SetFrameObserver(null);
            ApplySettingsFromUi();
            PersistSelections();
            _keymap.Save();
            _globalClickSuppressor.SetEnabled(false);
            _globalClickSuppressor.Dispose();
            _hwndSource?.RemoveHook(WndProc);
            _replayTimer?.Stop();
            _statusTimer?.Stop();
            _touchActor?.Dispose();
            _dispatchPump?.Dispose();
            _dispatchQueue?.Dispose();
            _captureWriter?.Dispose();
            EmitCaptureReplayTraceIfRequested();
            FrameMetricsSnapshot snapshot = _liveMetrics.CreateSnapshot();
            Console.WriteLine(snapshot.ToSummary());
            if (!string.IsNullOrWhiteSpace(_options.MetricsOutputPath))
            {
                snapshot.WriteSnapshotJson(Path.GetFullPath(_options.MetricsOutputPath));
            }

            _left.Reset();
            _right.Reset();
        };
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        if (IsReplayMode || UsesSharedRuntime)
        {
            return;
        }

        IntPtr hwnd = new WindowInteropHelper(this).Handle;
        _hwndSource = HwndSource.FromHwnd(hwnd);
        _hwndSource?.AddHook(WndProc);
        EnsureGlobalClickSuppressorInstalled();

        if (!RawInputInterop.RegisterForTouchpadRawInput(hwnd, out string? error))
        {
            StatusText.Text = $"Raw input registration failed ({error}).";
        }
    }

    private void EnsureGlobalClickSuppressorInstalled()
    {
        if (_globalClickSuppressor.IsInstalled)
        {
            _globalClickSuppressor.SetEnabled(_suppressGlobalClicks);
            return;
        }

        if (!_globalClickSuppressor.Install(out string? error))
        {
            Console.WriteLine($"Global click suppression hook failed ({error}).");
            return;
        }

        _globalClickSuppressor.SetEnabled(_suppressGlobalClicks);
    }

    private void UpdateGlobalClickSuppressionState(bool enabled)
    {
        bool next = !IsReplayMode && enabled;
        if (_suppressGlobalClicks == next)
        {
            return;
        }

        _suppressGlobalClicks = next;
        if (_globalClickSuppressor.IsInstalled)
        {
            _globalClickSuppressor.SetEnabled(next);
        }
    }

    private void EmitCaptureReplayTraceIfRequested()
    {
        if (IsReplayMode ||
            string.IsNullOrWhiteSpace(_options.CapturePath) ||
            string.IsNullOrWhiteSpace(_options.ReplayTraceOutputPath))
        {
            return;
        }

        string capturePath = Path.GetFullPath(_options.CapturePath);
        string tracePath = Path.GetFullPath(_options.ReplayTraceOutputPath);
        if (!File.Exists(capturePath))
        {
            Console.WriteLine($"Capture replay trace skipped; capture not found: {capturePath}");
            return;
        }

        try
        {
            Dictionary<ReplayDeviceTag, TrackpadSide> sideByTag = new();
            if (_left.Tag is RawInputDeviceTag leftTag)
            {
                sideByTag[new ReplayDeviceTag(leftTag.Index, leftTag.Hash)] = TrackpadSide.Left;
            }

            if (_right.Tag is RawInputDeviceTag rightTag)
            {
                sideByTag[new ReplayDeviceTag(rightTag.Index, rightTag.Hash)] = TrackpadSide.Right;
            }

            ReplayRunner replay = new();
            ReplayRunOptions replayOptions = new(
                keymap: _keymap,
                layoutPreset: _preset,
                config: BuildConfigFromSettings(),
                sideByTag: sideByTag.Count == 0 ? null : sideByTag);
            ReplayRunResult result = replay.Run(capturePath, fixturePath: null, traceOutputPath: tracePath, options: replayOptions);
            Console.WriteLine($"Capture replay trace written: {tracePath}");
            Console.WriteLine(result.ToSummary());
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Capture replay trace failed: {ex.Message}");
        }
    }

    private void OnStatusTimerTick(object? sender, EventArgs e)
    {
        if (_touchActor == null && _runtimeService == null)
        {
            return;
        }

        UpdateEngineStateDetails();
    }

    private void InitializeLayerCombo()
    {
        _suppressLayerEvent = true;
        LayerCombo.Items.Clear();
        for (int layer = 0; layer <= 3; layer++)
        {
            LayerCombo.Items.Add($"Layer {layer}");
        }
        _activeLayer = Math.Clamp(_settings.ActiveLayer, 0, 3);
        LayerCombo.SelectedIndex = _activeLayer;
        _suppressLayerEvent = false;
    }

    private void InitializeSettingsPanel()
    {
        _suppressSettingsEvents = true;
        _keyActionOptions.Clear();
        _keyActionOptionLookup.Clear();
        foreach (KeyActionOption action in BuildKeyActionOptions())
        {
            _keyActionOptions.Add(action);
            _keyActionOptionLookup.Add(action.Value);
        }

        KeymapPrimaryCombo.ItemsSource = CreateGroupedKeyActionView();
        KeymapHoldCombo.ItemsSource = CreateGroupedKeyActionView();

        LayoutPresetCombo.Items.Clear();
        foreach (TrackpadLayoutPreset preset in TrackpadLayoutPreset.All)
        {
            LayoutPresetCombo.Items.Add(preset);
        }

        LayoutPresetCombo.SelectedItem = _preset;
        TapClickEnabledCheck.IsChecked = _settings.TapClickEnabled;
        KeyboardModeCheck.IsChecked = _settings.KeyboardModeEnabled;
        SnapRadiusModeCheck.IsChecked = _settings.SnapRadiusPercent > 0.0;
        ChordShiftCheck.IsChecked = _settings.ChordShiftEnabled;
        bool startupEnabled = StartupRegistration.IsEnabled();
        _settings.RunAtStartup = startupEnabled;
        RunAtStartupCheck.IsChecked = startupEnabled;
        InitializeDecoderProfileCombos();
        RefreshDecoderProfileCombos();

        HoldDurationBox.Text = FormatNumber(_settings.HoldDurationMs);
        DragCancelBox.Text = FormatNumber(_settings.DragCancelMm);
        TypingGraceBox.Text = FormatNumber(_settings.TypingGraceMs);
        IntentMoveBox.Text = FormatNumber(_settings.IntentMoveMm);
        IntentVelocityBox.Text = FormatNumber(_settings.IntentVelocityMmPerSec);
        TapStaggerBox.Text = FormatNumber(_settings.TapStaggerToleranceMs);
        TapCadenceBox.Text = FormatNumber(_settings.TapCadenceWindowMs);
        TapMoveBox.Text = FormatNumber(_settings.TapMoveThresholdMm);
        KeyPaddingBox.Text = FormatNumber(_settings.KeyPaddingPercent);
        ControlsPaneBorder.Width = ControlsPaneExpandedWidth;
        ToggleControlsButton.Content = "Hide Controls";
        RefreshColumnLayoutEditor();
        _suppressSettingsEvents = false;

        ClearSelectionForEditing();
        RefreshKeymapEditor();
    }

    private ListCollectionView CreateGroupedKeyActionView()
    {
        ListCollectionView view = new(_keyActionOptions);
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(KeyActionOption.Group)));
        return view;
    }

    private void HookTuningAutoApplyHandlers()
    {
        TextBox[] boxes =
        {
            HoldDurationBox,
            DragCancelBox,
            TypingGraceBox,
            IntentMoveBox,
            IntentVelocityBox,
            KeyPaddingBox,
            ColumnScaleBox,
            ColumnOffsetXBox,
            ColumnOffsetYBox,
            TapStaggerBox,
            TapCadenceBox,
            TapMoveBox
        };

        foreach (TextBox box in boxes)
        {
            box.LostKeyboardFocus += OnTuningFieldCommitted;
            box.KeyDown += OnTuningFieldKeyDown;
        }
    }

    private void OnTuningFieldCommitted(object sender, KeyboardFocusChangedEventArgs e)
    {
        if (_suppressSettingsEvents)
        {
            return;
        }

        ApplySettingsFromUi();
    }

    private void OnTuningFieldKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        if (_suppressSettingsEvents)
        {
            return;
        }

        ApplySettingsFromUi();
        e.Handled = true;
    }

    private void OnModeSettingChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressSettingsEvents)
        {
            return;
        }

        ApplySettingsFromUi();
    }

    private void OnLayoutPresetChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressSettingsEvents || LayoutPresetCombo.SelectedItem is not TrackpadLayoutPreset selected)
        {
            return;
        }

        _preset = selected;
        _keymap.SetActiveLayout(_preset.Name);
        _settings.LayoutPresetName = selected.Name;
        _columnSettings = BuildColumnSettingsForPreset(_settings, _preset);
        RefreshColumnLayoutEditor();
        RebuildLayouts();
        RefreshKeymapEditor();
        ApplySettingsFromUi();
    }

    private void OnToggleControlsPaneClicked(object sender, RoutedEventArgs e)
    {
        SetControlsPaneVisible(!_controlsPaneVisible, animated: true);
    }

    private void OnKeymapExportClicked(object sender, RoutedEventArgs e)
    {
        SaveFileDialog dialog = new()
        {
            Title = "Export Settings",
            Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
            DefaultExt = ".json",
            AddExtension = true,
            OverwritePrompt = true,
            FileName = $"GlassToKey-settings-{DateTime.Now:yyyyMMdd-HHmmss}.json"
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        if (TryExportSettingsBundle(dialog.FileName, out string error))
        {
            return;
        }

        MessageBox.Show(
            this,
            $"Failed to export settings.\n{error}",
            "Settings Export",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
    }

    private void OnKeymapImportClicked(object sender, RoutedEventArgs e)
    {
        OpenFileDialog dialog = new()
        {
            Title = "Import Settings",
            Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
            CheckFileExists = true,
            Multiselect = false
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        if (!TryImportSettingsBundle(dialog.FileName, out string error))
        {
            MessageBox.Show(
                this,
                $"Failed to import settings.\n{error}",
                "Settings Import",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            return;
        }
    }

    private void ApplySettingsFromUi()
    {
        if (_suppressSettingsEvents)
        {
            return;
        }

        _settings.TapClickEnabled = TapClickEnabledCheck.IsChecked == true;
        _settings.TwoFingerTapEnabled = _settings.TapClickEnabled;
        _settings.ThreeFingerTapEnabled = _settings.TapClickEnabled;
        _settings.KeyboardModeEnabled = KeyboardModeCheck.IsChecked == true;
        _settings.SnapRadiusPercent = SnapRadiusModeCheck.IsChecked == true
            ? RuntimeConfigurationFactory.HardcodedSnapRadiusPercent
            : 0.0;
        _settings.ChordShiftEnabled = ChordShiftCheck.IsChecked == true;
        bool startupRequested = RunAtStartupCheck.IsChecked == true;
        if (_settings.RunAtStartup != startupRequested)
        {
            if (!StartupRegistration.TrySetEnabled(startupRequested, out string? startupError))
            {
                _suppressSettingsEvents = true;
                RunAtStartupCheck.IsChecked = _settings.RunAtStartup;
                _suppressSettingsEvents = false;
                MessageBox.Show(
                    this,
                    $"Failed to update startup registration.\n{startupError}",
                    "Startup Registration",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
                return;
            }

            _settings.RunAtStartup = startupRequested;
        }
        _settings.LayoutPresetName = _preset.Name;
        _settings.VisualizerEnabled = true;

        _settings.HoldDurationMs = ReadDouble(HoldDurationBox, _settings.HoldDurationMs);
        _settings.DragCancelMm = ReadDouble(DragCancelBox, _settings.DragCancelMm);
        _settings.TypingGraceMs = ReadDouble(TypingGraceBox, _settings.TypingGraceMs);
        _settings.IntentMoveMm = ReadDouble(IntentMoveBox, _settings.IntentMoveMm);
        _settings.IntentVelocityMmPerSec = ReadDouble(IntentVelocityBox, _settings.IntentVelocityMmPerSec);
        _settings.KeyBufferMs = RuntimeConfigurationFactory.HardcodedKeyBufferMs;
        _settings.TapStaggerToleranceMs = ReadDouble(TapStaggerBox, _settings.TapStaggerToleranceMs);
        _settings.TapCadenceWindowMs = ReadDouble(TapCadenceBox, _settings.TapCadenceWindowMs);
        _settings.TapMoveThresholdMm = ReadDouble(TapMoveBox, _settings.TapMoveThresholdMm);

        bool layoutChanged = ApplyColumnLayoutFromUi();
        _settings.ActiveLayer = _activeLayer;
        RuntimeConfigurationFactory.SaveColumnSettingsForPreset(_settings, _preset, _columnSettings);
        if (layoutChanged)
        {
            RebuildLayouts();
        }

        ApplyCoreSettings();
        ApplyVisualizerEnabled(true, persist: false);
        _settings.Save();
        _decoderProfilesByPath = TrackpadDecoderProfileMap.BuildFromSettings(_settings);
        UpdateEngineStateDetails();
    }

    private bool TryExportSettingsBundle(string path, out string error)
    {
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(path))
        {
            error = "Export path is empty.";
            return false;
        }

        try
        {
            string? dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(dir))
            {
                Directory.CreateDirectory(dir);
            }

            EnsureExportIncludesAllPresetLayouts();
            SettingsBundleFile bundle = new()
            {
                Version = 1,
                Settings = BuildExportSettingsSnapshot(),
                KeymapJson = _keymap.SerializeToJson(writeIndented: false)
            };

            string json = JsonSerializer.Serialize(bundle, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(path, json);
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    private void EnsureExportIncludesAllPresetLayouts()
    {
        for (int i = 0; i < TrackpadLayoutPreset.All.Length; i++)
        {
            _keymap.EnsureLayoutExists(TrackpadLayoutPreset.All[i].Name);
        }
    }

    private UserSettings BuildExportSettingsSnapshot()
    {
        UserSettings snapshot = _settings.Clone();
        snapshot.NormalizeRanges();
        snapshot.ColumnSettingsByLayout ??= new Dictionary<string, List<ColumnLayoutSettings>>(StringComparer.OrdinalIgnoreCase);

        for (int i = 0; i < TrackpadLayoutPreset.All.Length; i++)
        {
            TrackpadLayoutPreset preset = TrackpadLayoutPreset.All[i];
            ColumnLayoutSettings[] source = RuntimeConfigurationFactory.BuildColumnSettingsForPreset(snapshot, preset);
            List<ColumnLayoutSettings> list = new(source.Length);
            for (int c = 0; c < source.Length; c++)
            {
                ColumnLayoutSettings item = source[c];
                list.Add(new ColumnLayoutSettings(
                    scale: item.Scale,
                    offsetXPercent: item.OffsetXPercent,
                    offsetYPercent: item.OffsetYPercent,
                    rowSpacingPercent: item.RowSpacingPercent));
            }

            snapshot.ColumnSettingsByLayout[preset.Name] = list;
        }

        TrackpadLayoutPreset activePreset = TrackpadLayoutPreset.ResolveByNameOrDefault(snapshot.LayoutPresetName);
        if (snapshot.ColumnSettingsByLayout.TryGetValue(activePreset.Name, out List<ColumnLayoutSettings>? activeList))
        {
            snapshot.ColumnSettings = new List<ColumnLayoutSettings>(activeList.Count);
            for (int i = 0; i < activeList.Count; i++)
            {
                ColumnLayoutSettings item = activeList[i];
                snapshot.ColumnSettings.Add(new ColumnLayoutSettings(
                    scale: item.Scale,
                    offsetXPercent: item.OffsetXPercent,
                    offsetYPercent: item.OffsetYPercent,
                    rowSpacingPercent: item.RowSpacingPercent));
            }
        }
        else
        {
            snapshot.ColumnSettings = new List<ColumnLayoutSettings>();
        }

        return snapshot;
    }

    private bool TryImportSettingsBundle(string path, out string error)
    {
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(path))
        {
            error = "Import path is empty.";
            return false;
        }

        string json;
        try
        {
            json = File.ReadAllText(path);
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }

        if (TryImportSettingsBundleJson(json, out string bundleError))
        {
            return true;
        }

        // Backward compatibility: allow importing legacy keymap-only JSON.
        if (_keymap.TryImportFromJson(json, out string legacyError))
        {
            _keymap.SetActiveLayout(_preset.Name);
            _keymap.Save();
            ApplyCoreSettings();
            UpdateLabelMatrices();
            EnsureSelectedKeyStillValid();
            UpdateSelectedKeyHighlight();
            RefreshKeymapEditor();
            if (_visualizerEnabled)
            {
                UpdateHitForSide(_left, TrackpadSide.Left);
                UpdateHitForSide(_right, TrackpadSide.Right);
            }
            return true;
        }

        if (string.IsNullOrWhiteSpace(bundleError))
        {
            error = legacyError;
        }
        else
        {
            error = $"{bundleError}\nLegacy keymap import also failed: {legacyError}";
        }
        return false;
    }

    private bool TryImportSettingsBundleJson(string json, out string error)
    {
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(json))
        {
            error = "Import file is empty.";
            return false;
        }

        SettingsBundleFile? bundle;
        try
        {
            bundle = JsonSerializer.Deserialize<SettingsBundleFile>(
                json,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }

        if (bundle?.Settings == null || string.IsNullOrWhiteSpace(bundle.KeymapJson))
        {
            error = "Expected a GlassToKey settings export with both settings and keymap data.";
            return false;
        }

        UserSettings importedSettings = bundle.Settings.Clone();
        importedSettings.NormalizeRanges();

        if (!StartupRegistration.TrySetEnabled(importedSettings.RunAtStartup, out string? startupError))
        {
            error = $"Failed to apply startup registration from imported settings.\n{startupError}";
            return false;
        }

        if (!_keymap.TryImportFromJson(bundle.KeymapJson, out string keymapError))
        {
            error = $"Keymap section is invalid: {keymapError}";
            return false;
        }

        _settings.CopyFrom(importedSettings);
        _settings.NormalizeRanges();

        _preset = TrackpadLayoutPreset.ResolveByNameOrDefault(_settings.LayoutPresetName);
        _settings.LayoutPresetName = _preset.Name;
        _activeLayer = Math.Clamp(_settings.ActiveLayer, 0, 3);
        _suppressLayerEvent = true;
        LayerCombo.SelectedIndex = _activeLayer;
        _suppressLayerEvent = false;
        _keymap.SetActiveLayout(_preset.Name);
        _columnSettings = BuildColumnSettingsForPreset(_settings, _preset);

        RebuildLayouts();
        InitializeSettingsPanel();
        ApplyCoreSettings();

        if (!IsReplayMode)
        {
            LoadDevices(preserveSelection: false);
            PersistSelections();
        }

        UpdateLabelMatrices();
        EnsureSelectedKeyStillValid();
        UpdateSelectedKeyHighlight();
        RefreshKeymapEditor();
        if (_visualizerEnabled)
        {
            UpdateHitForSide(_left, TrackpadSide.Left);
            UpdateHitForSide(_right, TrackpadSide.Right);
        }

        _settings.Save();
        _keymap.Save();
        _decoderProfilesByPath = TrackpadDecoderProfileMap.BuildFromSettings(_settings);
        UpdateEngineStateDetails();
        return true;
    }

    private void ApplyCoreSettings()
    {
        if (_touchActor != null)
        {
            _touchActor.Configure(BuildConfigFromSettings());
            _touchActor.SetKeyboardModeEnabled(_settings.KeyboardModeEnabled);
            _touchActor.SetAllowMouseTakeover(_settings.AllowMouseTakeover);
            _touchActor.ConfigureLayouts(_leftLayout, _rightLayout);
            _touchActor.ConfigureKeymap(_keymap);
            _touchActor.SetPersistentLayer(_activeLayer);
        }

        _runtimeService?.ApplyConfiguration(_settings, _keymap, _preset, _columnSettings, _activeLayer);
    }

    private void RebuildLayouts()
    {
        RuntimeConfigurationFactory.BuildLayouts(_settings, _preset, _columnSettings, out _leftLayout, out _rightLayout);
        LeftSurface.Layout = _leftLayout;
        RightSurface.Layout = _rightLayout;
        UpdateLabelMatrices();
        if (_visualizerEnabled)
        {
            UpdateHitForSide(_left, TrackpadSide.Left);
            UpdateHitForSide(_right, TrackpadSide.Right);
        }
        EnsureSelectedKeyStillValid();
        UpdateSelectedKeyHighlight();
    }

    private void ApplyVisualizerEnabled(bool enabled, bool persist)
    {
        _visualizerEnabled = enabled;
        _settings.VisualizerEnabled = enabled;

        if (!enabled)
        {
            LeftSurface.HighlightedKey = null;
            RightSurface.HighlightedKey = null;
            LeftSurface.HighlightedCustomButtonId = null;
            RightSurface.HighlightedCustomButtonId = null;
            LeftSurface.EmptyMessage = "Visualizer disabled (engine still running).";
            RightSurface.EmptyMessage = "Visualizer disabled (engine still running).";
        }
        else
        {
            LeftSurface.EmptyMessage = string.IsNullOrWhiteSpace(_left.DeviceName) ? "No device selected." : string.Empty;
            RightSurface.EmptyMessage = string.IsNullOrWhiteSpace(_right.DeviceName) ? "No device selected." : string.Empty;
        }

        LeftSurface.Opacity = enabled ? 1.0 : 0.45;
        RightSurface.Opacity = enabled ? 1.0 : 0.45;
        LeftSurface.InvalidateVisual();
        RightSurface.InvalidateVisual();
        if (persist)
        {
            _settings.Save();
        }
    }

    private TouchProcessorConfig BuildConfigFromSettings()
    {
        return RuntimeConfigurationFactory.BuildTouchConfig(_settings);
    }

    private static string FormatNumber(double value)
    {
        return value.ToString("0.###", CultureInfo.InvariantCulture);
    }

    private static double ReadDouble(TextBox box, double fallback)
    {
        if (double.TryParse(box.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out double parsed))
        {
            return parsed;
        }

        box.Text = FormatNumber(fallback);
        return fallback;
    }

    private void OnColumnLayoutSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressSettingsEvents)
        {
            return;
        }

        RefreshColumnLayoutFields();
    }

    private void RefreshColumnLayoutEditor()
    {
        bool allowsColumnSettings = _preset.AllowsColumnSettings;
        ColumnLayoutColumnCombo.IsEnabled = allowsColumnSettings;
        ColumnScaleBox.IsEnabled = allowsColumnSettings;
        ColumnOffsetXBox.IsEnabled = allowsColumnSettings;
        ColumnOffsetYBox.IsEnabled = allowsColumnSettings;

        int previous = ColumnLayoutColumnCombo.SelectedIndex;
        ColumnLayoutColumnCombo.Items.Clear();
        for (int col = 0; col < _preset.Columns; col++)
        {
            ColumnLayoutColumnCombo.Items.Add($"Column {col + 1}");
        }

        if (_preset.Columns > 0)
        {
            if (previous < 0 || previous >= _preset.Columns)
            {
                previous = 0;
            }

            ColumnLayoutColumnCombo.SelectedIndex = previous;
        }

        RefreshColumnLayoutFields();
    }

    private void RefreshColumnLayoutFields()
    {
        if (!_preset.AllowsColumnSettings)
        {
            ColumnScaleBox.Text = FormatNumber(_preset.FixedKeyScale * 100.0);
            ColumnOffsetXBox.Text = "0";
            ColumnOffsetYBox.Text = "0";
            return;
        }

        int col = ColumnLayoutColumnCombo.SelectedIndex;
        if (col < 0 || col >= _columnSettings.Length)
        {
            ColumnScaleBox.Text = "100";
            ColumnOffsetXBox.Text = "0";
            ColumnOffsetYBox.Text = "0";
            return;
        }

        ColumnLayoutSettings settings = _columnSettings[col];
        ColumnScaleBox.Text = FormatNumber(settings.Scale * 100.0);
        ColumnOffsetXBox.Text = FormatNumber(settings.OffsetXPercent);
        ColumnOffsetYBox.Text = FormatNumber(settings.OffsetYPercent);
    }

    private bool ApplyColumnLayoutFromUi()
    {
        bool changed = false;
        double previousPadding = _settings.KeyPaddingPercent;
        double nextPadding = Math.Clamp(ReadDouble(KeyPaddingBox, previousPadding), 0.0, 90.0);
        if (Math.Abs(nextPadding - previousPadding) > 0.00001)
        {
            _settings.KeyPaddingPercent = nextPadding;
            changed = true;
        }
        KeyPaddingBox.Text = FormatNumber(_settings.KeyPaddingPercent);

        if (!_preset.AllowsColumnSettings)
        {
            return changed;
        }

        int selectedColumn = ColumnLayoutColumnCombo.SelectedIndex;
        if (selectedColumn < 0 || selectedColumn >= _columnSettings.Length)
        {
            return changed;
        }

        ColumnLayoutSettings target = _columnSettings[selectedColumn];
        double nextScalePercent = ReadDouble(ColumnScaleBox, target.Scale * 100.0);
        double nextScale = Math.Clamp(nextScalePercent / 100.0, 0.25, 3.0);
        double nextOffsetX = ReadDouble(ColumnOffsetXBox, target.OffsetXPercent);
        double nextOffsetY = ReadDouble(ColumnOffsetYBox, target.OffsetYPercent);

        if (Math.Abs(nextScale - target.Scale) > 0.00001)
        {
            target.Scale = nextScale;
            changed = true;
        }

        if (Math.Abs(nextOffsetX - target.OffsetXPercent) > 0.00001)
        {
            target.OffsetXPercent = nextOffsetX;
            changed = true;
        }

        if (Math.Abs(nextOffsetY - target.OffsetYPercent) > 0.00001)
        {
            target.OffsetYPercent = nextOffsetY;
            changed = true;
        }

        ColumnScaleBox.Text = FormatNumber(target.Scale * 100.0);
        ColumnOffsetXBox.Text = FormatNumber(target.OffsetXPercent);
        ColumnOffsetYBox.Text = FormatNumber(target.OffsetYPercent);
        return changed;
    }

    private static ColumnLayoutSettings[] CloneColumnSettings(ColumnLayoutSettings[] source)
    {
        return RuntimeConfigurationFactory.CloneColumnSettings(source);
    }

    private static ColumnLayoutSettings[] BuildColumnSettingsForPreset(UserSettings settings, TrackpadLayoutPreset preset)
    {
        return RuntimeConfigurationFactory.BuildColumnSettingsForPreset(settings, preset);
    }

    private void SetControlsPaneVisible(bool visible, bool animated)
    {
        _controlsPaneVisible = visible;
        ToggleControlsButton.Content = visible ? "Hide Controls" : "Show Controls";
        double targetWidth = visible ? ControlsPaneExpandedWidth : ControlsPaneCollapsedWidth;
        ControlsPaneBorder.IsHitTestVisible = visible;

        if (!animated)
        {
            ControlsPaneBorder.BeginAnimation(FrameworkElement.WidthProperty, null);
            ControlsPaneBorder.BeginAnimation(UIElement.OpacityProperty, null);
            ControlsPaneBorder.Width = targetWidth;
            ControlsPaneBorder.Opacity = visible ? 1.0 : 0.0;
            return;
        }

        var animation = new DoubleAnimation
        {
            To = targetWidth,
            Duration = TimeSpan.FromMilliseconds(220),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        var opacityAnimation = new DoubleAnimation
        {
            To = visible ? 1.0 : 0.0,
            Duration = TimeSpan.FromMilliseconds(200),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        ControlsPaneBorder.BeginAnimation(FrameworkElement.WidthProperty, animation, HandoffBehavior.SnapshotAndReplace);
        ControlsPaneBorder.BeginAnimation(UIElement.OpacityProperty, opacityAnimation, HandoffBehavior.SnapshotAndReplace);
    }

    private static List<KeyActionOption> BuildKeyActionOptions()
    {
        List<KeyActionOption> options = new(120);
        AddKeyActionOption(options, "None", "General");
        AddKeyActionOption(options, "Left Click", "Mouse Actions");
        AddKeyActionOption(options, "Right Click", "Mouse Actions");
        AddKeyActionOption(options, "Middle Click", "Mouse Actions");

        for (char ch = 'A'; ch <= 'Z'; ch++)
        {
            AddKeyActionOption(options, ch.ToString(), "Letters A-Z");
        }

        for (char ch = '0'; ch <= '9'; ch++)
        {
            AddKeyActionOption(options, ch.ToString(), "Numbers 0-9");
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
            AddKeyActionOption(options, navigationAndEditing[i], "Navigation & Editing");
        }

        string[] modifiersAndModes =
        {
            "Shift",
            "Ctrl",
            "Alt",
            "LWin",
            "RWin",
            "TT"
        };
        for (int i = 0; i < modifiersAndModes.Length; i++)
        {
            AddKeyActionOption(options, modifiersAndModes[i], "Modifiers & Modes");
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
            "â€”",
            "=",
            "`"
        };
        for (int i = 0; i < symbols.Length; i++)
        {
            AddKeyActionOption(options, symbols[i], "Symbols & Punctuation");
        }

        for (int i = 1; i <= 12; i++)
        {
            AddKeyActionOption(options, $"F{i}", "Function Keys");
        }

        string[] shortcuts =
        {
            "Ctrl+C",
            "Ctrl+V",
            "Ctrl+F",
            "Ctrl+X",
            "Ctrl+S",
            "Ctrl+A",
            "Ctrl+Z"
        };
        for (int i = 0; i < shortcuts.Length; i++)
        {
            AddKeyActionOption(options, shortcuts[i], "Shortcuts");
        }

        AddKeyActionOption(options, "TO(0)", "Layers");
        for (int layer = 1; layer <= 3; layer++)
        {
            AddKeyActionOption(options, $"MO({layer})", "Layers");
            AddKeyActionOption(options, $"TO({layer})", "Layers");
        }

        return options;
    }

    private static void AddKeyActionOption(List<KeyActionOption> options, string value, string group)
    {
        options.Add(new KeyActionOption(value, value, group));
    }

    private void EnsureActionOption(string action)
    {
        if (string.IsNullOrWhiteSpace(action))
        {
            return;
        }

        if (!_keyActionOptionLookup.Add(action))
        {
            return;
        }

        _keyActionOptions.Add(new KeyActionOption(action, action, "Custom"));
    }

    private void InitializeReplayControls()
    {
        if (!IsReplayMode)
        {
            ReplayPanel.Visibility = Visibility.Collapsed;
            return;
        }

        ReplayPanel.Visibility = Visibility.Visible;
        RefreshButton.IsEnabled = false;

        _suppressReplaySpeedEvents = true;
        ReplaySpeedCombo.Items.Clear();
        ReplaySpeedOption[] options =
        {
            new(0.25, "0.25x"),
            new(0.50, "0.5x"),
            new(1.00, "1x"),
            new(2.00, "2x"),
            new(4.00, "4x")
        };

        int selectedIndex = 2;
        for (int i = 0; i < options.Length; i++)
        {
            ReplaySpeedCombo.Items.Add(options[i]);
            if (Math.Abs(options[i].Speed - _replaySpeed) < 0.0001)
            {
                selectedIndex = i;
            }
        }
        if (selectedIndex == 2 && Math.Abs(_replaySpeed - 1.0) > 0.0001)
        {
            ReplaySpeedOption custom = new(_replaySpeed, $"{_replaySpeed:0.##}x");
            ReplaySpeedCombo.Items.Add(custom);
            selectedIndex = ReplaySpeedCombo.Items.Count - 1;
        }

        ReplaySpeedCombo.SelectedIndex = selectedIndex;
        _replaySpeed = ((ReplaySpeedOption)ReplaySpeedCombo.SelectedItem).Speed;
        _suppressReplaySpeedEvents = false;
        ReplayLoopCheckBox.IsChecked = false;
        _replayLoop = false;

        bool hasFrames = _replayData != null && _replayData.Frames.Length > 0;
        ReplayToggleButton.IsEnabled = hasFrames;
        ReplayStepBackButton.IsEnabled = hasFrames;
        ReplayStepForwardButton.IsEnabled = hasFrames;
        ReplayTimelineSlider.IsEnabled = hasFrames;

        if (_replayData != null)
        {
            UpdateReplayTimelineControls();
        }
    }

    private void OnLayerSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressLayerEvent)
        {
            return;
        }

        _activeLayer = Math.Clamp(LayerCombo.SelectedIndex, 0, 3);
        _settings.ActiveLayer = _activeLayer;
        _touchActor?.SetPersistentLayer(_activeLayer);
        _runtimeService?.ApplyConfiguration(_settings, _keymap, _preset, _columnSettings, _activeLayer);
        _settings.Save();
        UpdateLabelMatrices();
        EnsureSelectedKeyStillValid();
        UpdateSelectedKeyHighlight();
        RefreshKeymapEditor();
        UpdateEngineStateDetails();
        UpdateHitForSide(_left, TrackpadSide.Left);
        UpdateHitForSide(_right, TrackpadSide.Right);
    }

    private void LoadDevices(bool preserveSelection)
    {
        if (IsReplayMode)
        {
            return;
        }

        _suppressSelectionEvents = true;
        string? leftPath = preserveSelection ? (LeftDeviceCombo.SelectedItem as HidDeviceInfo)?.Path : _settings.LeftDevicePath;
        string? rightPath = preserveSelection ? (RightDeviceCombo.SelectedItem as HidDeviceInfo)?.Path : _settings.RightDevicePath;

        _devices.Clear();
        _devices.Add(new HidDeviceInfo("None", null));
        foreach (HidDeviceInfo device in RawInputInterop.EnumerateTrackpads())
        {
            _devices.Add(device);
        }

        _rawInputContext.SeedTags(_devices);

        LeftDeviceCombo.ItemsSource = _devices;
        RightDeviceCombo.ItemsSource = _devices;

        LeftDeviceCombo.SelectedItem = FindDevice(leftPath) ?? _devices[0];
        RightDeviceCombo.SelectedItem = FindDevice(rightPath) ?? _devices[0];

        _suppressSelectionEvents = false;
        ApplySelections();
    }

    private void LoadReplayDevices()
    {
        if (_replayData == null)
        {
            return;
        }

        _suppressSelectionEvents = true;

        _devices.Clear();
        _devices.Add(new HidDeviceInfo("None", null));
        foreach (HidDeviceInfo replayDevice in _replayData.Devices)
        {
            _devices.Add(replayDevice);
        }

        LeftDeviceCombo.ItemsSource = _devices;
        RightDeviceCombo.ItemsSource = _devices;
        LeftDeviceCombo.SelectedItem = _devices.Count > 1 ? _devices[1] : _devices[0];
        RightDeviceCombo.SelectedItem = _devices.Count > 2 ? _devices[2] : _devices[0];

        _suppressSelectionEvents = false;
        ApplySelections();
        UpdateReplayHeaderStatus();
    }

    private void InitializeDecoderProfileCombos()
    {
        _suppressDecoderProfileEvents = true;
        LeftDecoderProfileCombo.Items.Clear();
        RightDecoderProfileCombo.Items.Clear();
        foreach (DecoderProfileOption option in DecoderProfileOptions)
        {
            LeftDecoderProfileCombo.Items.Add(option);
            RightDecoderProfileCombo.Items.Add(option);
        }

        LeftDecoderProfileCombo.SelectedIndex = 0;
        RightDecoderProfileCombo.SelectedIndex = 0;
        _suppressDecoderProfileEvents = false;
    }

    private void RefreshDecoderProfileCombos()
    {
        SetDecoderProfileComboSelection(TrackpadSide.Left);
        SetDecoderProfileComboSelection(TrackpadSide.Right);
    }

    private void SetDecoderProfileComboSelection(TrackpadSide side)
    {
        ComboBox combo = GetDecoderProfileComboForSide(side);
        string? devicePath = GetSelectedDevicePathForSide(side);
        bool hasDevice = !string.IsNullOrWhiteSpace(devicePath);
        TrackpadDecoderProfile profile = TrackpadDecoderProfile.Official;
        if (hasDevice &&
            _decoderProfilesByPath.TryGetValue(devicePath!, out TrackpadDecoderProfile configured))
        {
            profile = NormalizeConfiguredProfile(configured);
        }

        int selectedIndex = profile == TrackpadDecoderProfile.Legacy ? 1 : 0;
        _suppressDecoderProfileEvents = true;
        combo.SelectedIndex = selectedIndex;
        combo.IsEnabled = !IsReplayMode && hasDevice;
        _suppressDecoderProfileEvents = false;
    }

    private void OnLeftDecoderProfileSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        PersistDecoderProfileSelection(TrackpadSide.Left);
    }

    private void OnRightDecoderProfileSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        PersistDecoderProfileSelection(TrackpadSide.Right);
    }

    private void PersistDecoderProfileSelection(TrackpadSide side)
    {
        if (_suppressDecoderProfileEvents || IsReplayMode)
        {
            return;
        }

        ComboBox combo = GetDecoderProfileComboForSide(side);
        if (combo.SelectedItem is not DecoderProfileOption option)
        {
            return;
        }

        string? devicePath = GetSelectedDevicePathForSide(side);
        if (string.IsNullOrWhiteSpace(devicePath))
        {
            return;
        }

        _settings.DecoderProfilesByDevicePath ??= new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        bool changed;
        if (option.Profile == TrackpadDecoderProfile.Legacy)
        {
            changed =
                !_settings.DecoderProfilesByDevicePath.TryGetValue(devicePath, out string? existing) ||
                !string.Equals(existing, "legacy", StringComparison.Ordinal);
            if (changed)
            {
                _settings.DecoderProfilesByDevicePath[devicePath] = "legacy";
            }
        }
        else
        {
            changed = _settings.DecoderProfilesByDevicePath.Remove(devicePath);
        }

        if (!changed)
        {
            return;
        }

        _settings.Save();
        _decoderProfilesByPath = TrackpadDecoderProfileMap.BuildFromSettings(_settings);
        _runtimeService?.ApplyConfiguration(_settings, _keymap, _preset, _columnSettings, _activeLayer);
        ApplyPressurePolicyForSide(side);
    }

    private static TrackpadDecoderProfile NormalizeConfiguredProfile(TrackpadDecoderProfile profile)
    {
        return profile == TrackpadDecoderProfile.Legacy
            ? TrackpadDecoderProfile.Legacy
            : TrackpadDecoderProfile.Official;
    }

    private string? GetSelectedDevicePathForSide(TrackpadSide side)
    {
        return side == TrackpadSide.Left
            ? (LeftDeviceCombo.SelectedItem as HidDeviceInfo)?.Path
            : (RightDeviceCombo.SelectedItem as HidDeviceInfo)?.Path;
    }

    private ComboBox GetDecoderProfileComboForSide(TrackpadSide side)
    {
        return side == TrackpadSide.Left ? LeftDecoderProfileCombo : RightDecoderProfileCombo;
    }

    private HidDeviceInfo? FindDevice(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        foreach (HidDeviceInfo device in _devices)
        {
            if (string.Equals(device.Path, path, StringComparison.OrdinalIgnoreCase))
            {
                return device;
            }
        }

        return null;
    }

    private void OnLeftSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressSelectionEvents)
        {
            return;
        }
        StartReader(_left, LeftDeviceCombo.SelectedItem as HidDeviceInfo, TrackpadSide.Left);
        RefreshDecoderProfileCombos();
        if (!IsReplayMode)
        {
            PersistSelections();
        }
    }

    private void OnRightSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressSelectionEvents)
        {
            return;
        }
        StartReader(_right, RightDeviceCombo.SelectedItem as HidDeviceInfo, TrackpadSide.Right);
        RefreshDecoderProfileCombos();
        if (!IsReplayMode)
        {
            PersistSelections();
        }
    }

    private void ApplySelections()
    {
        StartReader(_left, LeftDeviceCombo.SelectedItem as HidDeviceInfo, TrackpadSide.Left);
        StartReader(_right, RightDeviceCombo.SelectedItem as HidDeviceInfo, TrackpadSide.Right);
        RefreshDecoderProfileCombos();
    }

    private void StartReader(ReaderSession session, HidDeviceInfo? device, TrackpadSide side)
    {
        session.Reset();
        ApplyRequestedMaxRange(side, device);

        if (device == null || device.IsNone)
        {
            if (side == TrackpadSide.Left) _leftStatus = "None";
            else _rightStatus = "None";
            UpdateHeaderStatus();
            SetEmptyMessage(session, "No device selected.");
            InvalidateSurface(session);
            UpdateHitDisplay(side, "--", null);
            ApplyPressurePolicyForSide(side);
            return;
        }

        if (side == TrackpadSide.Left) _leftStatus = IsReplayMode ? "Replay" : "Listening";
        else _rightStatus = IsReplayMode ? "Replay" : "Listening";
        UpdateHeaderStatus();
        SetEmptyMessage(session, string.Empty);
        session.SetDevice(device.Path!, device.DisplayName);
        UpdateHitDisplay(side, "--", null);
        ApplyPressurePolicyForSide(side);
    }

    private void ApplyRequestedMaxRange(TrackpadSide side, HidDeviceInfo? device)
    {
        TouchView surface = side == TrackpadSide.Left ? LeftSurface : RightSurface;
        ushort fallbackX = _options.MaxX ?? DefaultMaxX;
        ushort fallbackY = _options.MaxY ?? DefaultMaxY;

        if (IsReplayMode &&
            device != null &&
            !device.IsNone &&
            device.SuggestedMaxX > 0 &&
            device.SuggestedMaxY > 0)
        {
            surface.RequestedMaxX = device.SuggestedMaxX;
            surface.RequestedMaxY = device.SuggestedMaxY;
            return;
        }

        surface.RequestedMaxX = fallbackX;
        surface.RequestedMaxY = fallbackY;
    }

    private void ApplyPressurePolicyForSide(TrackpadSide side)
    {
        TouchView surface = side == TrackpadSide.Left ? LeftSurface : RightSurface;
        ReaderSession session = side == TrackpadSide.Left ? _left : _right;
        HidDeviceInfo? device = side == TrackpadSide.Left
            ? LeftDeviceCombo.SelectedItem as HidDeviceInfo
            : RightDeviceCombo.SelectedItem as HidDeviceInfo;

        bool showPressureValues = false;
        bool likelyNoPressure = true;
        if (device != null && !device.IsNone && !string.IsNullOrWhiteSpace(device.Path))
        {
            TrackpadDecoderProfile profile = GetConfiguredDecoderProfile(device.Path!);
            showPressureValues = profile == TrackpadDecoderProfile.Legacy;
            likelyNoPressure = !showPressureValues || IsLikelyBluetoothDevice(device);
        }

        surface.ShowPressureValues = showPressureValues;
        session.State.ConfigurePressureHint(likelyNoPressure);
        InvalidateSurface(session);
    }

    private static bool IsLikelyBluetoothDevice(HidDeviceInfo device)
    {
        return ContainsBluetoothToken(device.Path) || ContainsBluetoothToken(device.DisplayName);
    }

    private static bool ContainsBluetoothToken(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        return value.IndexOf("BTH", StringComparison.OrdinalIgnoreCase) >= 0 ||
               value.IndexOf("BLUETOOTH", StringComparison.OrdinalIgnoreCase) >= 0 ||
               value.IndexOf("BTLE", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private void UpdateLabelMatrices()
    {
        LeftSurface.LabelMatrix = BuildLabelMatrix(TrackpadSide.Left);
        RightSurface.LabelMatrix = BuildLabelMatrix(TrackpadSide.Right);
        LeftSurface.CustomButtons = BuildSurfaceCustomButtons(TrackpadSide.Left);
        RightSurface.CustomButtons = BuildSurfaceCustomButtons(TrackpadSide.Right);
        LeftSurface.InvalidateVisual();
        RightSurface.InvalidateVisual();
    }

    private SurfaceCustomButton[] BuildSurfaceCustomButtons(TrackpadSide side)
    {
        IReadOnlyList<CustomButton> buttons = _keymap.ResolveCustomButtons(GetVisualizationLayer(), side);
        if (buttons.Count == 0)
        {
            return Array.Empty<SurfaceCustomButton>();
        }

        SurfaceCustomButton[] output = new SurfaceCustomButton[buttons.Count];
        for (int i = 0; i < buttons.Count; i++)
        {
            CustomButton button = buttons[i];
            string primary = string.IsNullOrWhiteSpace(button.Primary?.Label) ? "None" : button.Primary.Label;
            string? hold = button.Hold?.Label;
            string label = string.IsNullOrWhiteSpace(hold) ? primary : $"{primary}\n{hold}";
            output[i] = new SurfaceCustomButton(button.Id, button.Rect, label);
        }

        return output;
    }

    private string[][] BuildLabelMatrix(TrackpadSide side)
    {
        int layer = GetVisualizationLayer();
        KeyLayout layout = side == TrackpadSide.Left ? _leftLayout : _rightLayout;
        string[][] labels = layout.Labels;
        string[][] output = new string[labels.Length][];
        for (int row = 0; row < labels.Length; row++)
        {
            output[row] = new string[labels[row].Length];
            for (int col = 0; col < labels[row].Length; col++)
            {
                string storageKey = GridKeyPosition.StorageKey(side, row, col);
                string defaultLabel = labels[row][col];
                KeyMapping mapping = _keymap.ResolveMapping(layer, storageKey, defaultLabel);
                string primary = string.IsNullOrWhiteSpace(mapping.Primary.Label) ? defaultLabel : mapping.Primary.Label;
                string? hold = mapping.Hold?.Label;
                output[row][col] = string.IsNullOrWhiteSpace(hold) ? primary : $"{primary}\n{hold}";
            }
        }
        return output;
    }

    private void RefreshKeymapEditor()
    {
        _suppressKeymapActionEvents = true;
        if (TryGetSelectedCustomButton(out _, out CustomButton? selectedButton))
        {
            KeymapPrimaryCombo.IsEnabled = true;
            KeymapHoldCombo.IsEnabled = true;
            CustomButtonDeleteButton.IsEnabled = true;
            SetCustomButtonGeometryEditorEnabled(true);

            string buttonPrimary = string.IsNullOrWhiteSpace(selectedButton.Primary?.Label) ? "None" : selectedButton.Primary.Label;
            string buttonHold = selectedButton.Hold?.Label ?? "None";
            EnsureActionOption(buttonPrimary);
            EnsureActionOption(buttonHold);
            KeymapPrimaryCombo.SelectedValue = buttonPrimary;
            KeymapHoldCombo.SelectedValue = buttonHold;
            CustomButtonXBox.Text = FormatNumber(selectedButton.Rect.X * 100.0);
            CustomButtonYBox.Text = FormatNumber(selectedButton.Rect.Y * 100.0);
            CustomButtonWidthBox.Text = FormatNumber(selectedButton.Rect.Width * 100.0);
            CustomButtonHeightBox.Text = FormatNumber(selectedButton.Rect.Height * 100.0);
            _suppressKeymapActionEvents = false;
            return;
        }

        if (!TryGetSelectedKeyPosition(out TrackpadSide side, out int row, out int column))
        {
            KeymapPrimaryCombo.IsEnabled = false;
            KeymapHoldCombo.IsEnabled = false;
            CustomButtonDeleteButton.IsEnabled = false;
            SetCustomButtonGeometryEditorEnabled(false);
            KeymapPrimaryCombo.SelectedValue = "None";
            KeymapHoldCombo.SelectedValue = "None";
            ClearCustomButtonGeometryEditorValues();
            _suppressKeymapActionEvents = false;
            return;
        }

        KeyLayout layout = side == TrackpadSide.Left ? _leftLayout : _rightLayout;
        if (row < 0 || row >= layout.Labels.Length || column < 0 || column >= layout.Labels[row].Length)
        {
            ClearSelectionForEditing();
            _suppressKeymapActionEvents = false;
            return;
        }

        KeymapPrimaryCombo.IsEnabled = true;
        KeymapHoldCombo.IsEnabled = true;
        CustomButtonDeleteButton.IsEnabled = false;
        SetCustomButtonGeometryEditorEnabled(false);
        ClearCustomButtonGeometryEditorValues();
        string defaultLabel = layout.Labels[row][column];
        string storageKey = GridKeyPosition.StorageKey(side, row, column);
        KeyMapping mapping = _keymap.ResolveMapping(GetSelectedLayer(), storageKey, defaultLabel);
        string primary = string.IsNullOrWhiteSpace(mapping.Primary.Label) ? defaultLabel : mapping.Primary.Label;
        string hold = mapping.Hold?.Label ?? "None";
        EnsureActionOption(primary);
        EnsureActionOption(hold);
        KeymapPrimaryCombo.SelectedValue = primary;
        KeymapHoldCombo.SelectedValue = hold;
        _suppressKeymapActionEvents = false;
    }

    private void SetCustomButtonGeometryEditorEnabled(bool enabled)
    {
        CustomButtonXBox.IsEnabled = enabled;
        CustomButtonYBox.IsEnabled = enabled;
        CustomButtonWidthBox.IsEnabled = enabled;
        CustomButtonHeightBox.IsEnabled = enabled;
    }

    private void ClearCustomButtonGeometryEditorValues()
    {
        CustomButtonXBox.Text = string.Empty;
        CustomButtonYBox.Text = string.Empty;
        CustomButtonWidthBox.Text = string.Empty;
        CustomButtonHeightBox.Text = string.Empty;
    }

    private void OnKeymapActionSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressKeymapActionEvents)
        {
            return;
        }

        ApplySelectedKeymapOverride();
    }

    private void ApplySelectedKeymapOverride()
    {
        int layer = GetSelectedLayer();
        string selectedPrimary = KeymapPrimaryCombo.SelectedValue as string ?? "None";
        string selectedHold = KeymapHoldCombo.SelectedValue as string ?? "None";
        string? hold = string.Equals(selectedHold, "None", StringComparison.OrdinalIgnoreCase) ? null : selectedHold;

        if (TryGetSelectedCustomButton(out _, out CustomButton? selectedButton))
        {
            selectedButton.Primary ??= new KeyAction();
            selectedButton.Primary.Label = selectedPrimary;
            selectedButton.Hold = hold == null ? null : new KeyAction { Label = hold };
            selectedButton.Layer = layer;

            _keymap.Save();
            UpdateLabelMatrices();
            ApplyCoreSettings();
            UpdateHitForSide(_left, TrackpadSide.Left);
            UpdateHitForSide(_right, TrackpadSide.Right);
            RefreshKeymapEditor();
            return;
        }

        if (!TryGetSelectedKeyPosition(out TrackpadSide side, out int row, out int column))
        {
            return;
        }

        KeyLayout layout = side == TrackpadSide.Left ? _leftLayout : _rightLayout;
        string defaultLabel = layout.Labels[row][column];
        string primary = selectedPrimary;
        string storageKey = GridKeyPosition.StorageKey(side, row, column);

        if (!_keymap.Mappings.TryGetValue(layer, out var layerMap))
        {
            layerMap = new Dictionary<string, KeyMapping>();
            _keymap.Mappings[layer] = layerMap;
        }

        layerMap[storageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = primary },
            Hold = hold == null ? null : new KeyAction { Label = hold }
        };

        _keymap.Save();
        UpdateLabelMatrices();
        ApplyCoreSettings();
        UpdateHitForSide(_left, TrackpadSide.Left);
        UpdateHitForSide(_right, TrackpadSide.Right);
        RefreshKeymapEditor();
    }

    private void OnCustomButtonAddLeftClicked(object sender, RoutedEventArgs e)
    {
        AddCustomButton(TrackpadSide.Left);
    }

    private void OnCustomButtonAddRightClicked(object sender, RoutedEventArgs e)
    {
        AddCustomButton(TrackpadSide.Right);
    }

    private void AddCustomButton(TrackpadSide side)
    {
        int layer = GetSelectedLayer();
        List<CustomButton> buttons = _keymap.GetOrCreateCustomButtons(layer);
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

        _keymap.Save();
        UpdateLabelMatrices();
        ApplyCoreSettings();
        if (_visualizerEnabled)
        {
            UpdateHitForSide(_left, TrackpadSide.Left);
            UpdateHitForSide(_right, TrackpadSide.Right);
        }
        SelectCustomButtonForEditing(side, button.Id);
    }

    private void OnCustomButtonDeleteClicked(object sender, RoutedEventArgs e)
    {
        if (!TryGetSelectedCustomButton(out _, out CustomButton? selectedButton))
        {
            return;
        }

        int layer = GetSelectedLayer();
        if (!_keymap.RemoveCustomButton(layer, selectedButton.Id))
        {
            return;
        }

        _keymap.Save();
        ClearSelectionForEditing();
        UpdateLabelMatrices();
        ApplyCoreSettings();
        if (_visualizerEnabled)
        {
            UpdateHitForSide(_left, TrackpadSide.Left);
            UpdateHitForSide(_right, TrackpadSide.Right);
        }
        RefreshKeymapEditor();
    }

    private void OnCustomButtonGeometryCommitted(object sender, KeyboardFocusChangedEventArgs e)
    {
        if (_suppressKeymapActionEvents)
        {
            return;
        }

        ApplySelectedCustomButtonGeometryFromUi();
    }

    private void OnCustomButtonGeometryKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        if (_suppressKeymapActionEvents)
        {
            return;
        }

        ApplySelectedCustomButtonGeometryFromUi();
        e.Handled = true;
    }

    private void OnWindowKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape)
        {
            return;
        }

        if (!_hasSelectedKey && !_hasSelectedCustomButton)
        {
            return;
        }

        ClearSelectionForEditing();
        RefreshKeymapEditor();
        e.Handled = true;
    }

    private void ApplySelectedCustomButtonGeometryFromUi()
    {
        if (!TryGetSelectedCustomButton(out _, out CustomButton? selectedButton))
        {
            return;
        }

        double xPercent = ReadDouble(CustomButtonXBox, selectedButton.Rect.X * 100.0);
        double yPercent = ReadDouble(CustomButtonYBox, selectedButton.Rect.Y * 100.0);
        double widthPercent = ReadDouble(CustomButtonWidthBox, selectedButton.Rect.Width * 100.0);
        double heightPercent = ReadDouble(CustomButtonHeightBox, selectedButton.Rect.Height * 100.0);

        double width = Math.Clamp(widthPercent / 100.0, MinCustomButtonPercent / 100.0, 1.0);
        double height = Math.Clamp(heightPercent / 100.0, MinCustomButtonPercent / 100.0, 1.0);
        double x = Math.Clamp(xPercent / 100.0, 0.0, 1.0 - width);
        double y = Math.Clamp(yPercent / 100.0, 0.0, 1.0 - height);

        selectedButton.Rect = KeymapStore.ClampCustomButtonRect(new NormalizedRect(x, y, width, height));
        selectedButton.Layer = GetSelectedLayer();

        _keymap.Save();
        UpdateLabelMatrices();
        ApplyCoreSettings();
        if (_visualizerEnabled)
        {
            UpdateHitForSide(_left, TrackpadSide.Left);
            UpdateHitForSide(_right, TrackpadSide.Right);
        }
        RefreshKeymapEditor();
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

    private bool TryGetSelectedCustomButton(out TrackpadSide side, [NotNullWhen(true)] out CustomButton? button)
    {
        side = _selectedKeySide;
        button = null;
        if (!_hasSelectedCustomButton || string.IsNullOrWhiteSpace(_selectedCustomButtonId))
        {
            return false;
        }

        button = _keymap.FindCustomButton(GetSelectedLayer(), _selectedCustomButtonId);
        if (button == null)
        {
            return false;
        }

        return true;
    }

    private void OnLeftSurfaceMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        HandleSurfaceKeymapSelection(TrackpadSide.Left, LeftSurface, _leftLayout, e);
    }

    private void OnRightSurfaceMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        HandleSurfaceKeymapSelection(TrackpadSide.Right, RightSurface, _rightLayout, e);
    }

    private void HandleSurfaceKeymapSelection(TrackpadSide side, TouchView surface, KeyLayout layout, MouseButtonEventArgs e)
    {
        Point point = e.GetPosition(surface);
        IReadOnlyList<CustomButton> customButtons = _keymap.ResolveCustomButtons(GetSelectedLayer(), side);
        if (!TryHitSelectionAtPoint(surface, layout, customButtons, point, out int row, out int column, out string? customButtonId))
        {
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

    private void SelectKeyForEditing(TrackpadSide side, int row, int column)
    {
        _hasSelectedKey = true;
        _hasSelectedCustomButton = false;
        _selectedCustomButtonId = null;
        _selectedKeySide = side;
        _selectedKeyRow = row;
        _selectedKeyColumn = column;
        UpdateSelectedKeyHighlight();
        RefreshKeymapEditor();
        ExpandKeymapEditorAndFocusPrimaryAction();
    }

    private void SelectCustomButtonForEditing(TrackpadSide side, string buttonId)
    {
        _hasSelectedKey = false;
        _hasSelectedCustomButton = true;
        _selectedCustomButtonId = buttonId;
        _selectedKeySide = side;
        _selectedKeyRow = -1;
        _selectedKeyColumn = -1;
        UpdateSelectedKeyHighlight();
        RefreshKeymapEditor();
        ExpandKeymapEditorAndFocusPrimaryAction();
    }

    private void ExpandKeymapEditorAndFocusPrimaryAction()
    {
        KeymapEditorExpander.IsExpanded = true;
        Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() =>
        {
            KeymapEditorExpander.IsExpanded = true;
            KeymapPrimaryCombo.BringIntoView();
            KeymapPrimaryCombo.Focus();
            Keyboard.Focus(KeymapPrimaryCombo);
        }));
    }

    private void ClearSelectionForEditing()
    {
        _hasSelectedKey = false;
        _hasSelectedCustomButton = false;
        _selectedCustomButtonId = null;
        _selectedKeySide = TrackpadSide.Left;
        _selectedKeyRow = -1;
        _selectedKeyColumn = -1;
        UpdateSelectedKeyHighlight();
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
                _keymap.FindCustomButton(GetSelectedLayer(), _selectedCustomButtonId) == null)
            {
                ClearSelectionForEditing();
            }
            return;
        }

        KeyLayout layout = _selectedKeySide == TrackpadSide.Left ? _leftLayout : _rightLayout;
        if (_selectedKeyRow < 0 ||
            _selectedKeyRow >= layout.Rects.Length ||
            _selectedKeyColumn < 0 ||
            (_selectedKeyRow < layout.Rects.Length && _selectedKeyColumn >= layout.Rects[_selectedKeyRow].Length))
        {
            ClearSelectionForEditing();
        }
    }

    private void UpdateSelectedKeyHighlight()
    {
        LeftSurface.SelectedKey = null;
        RightSurface.SelectedKey = null;
        LeftSurface.SelectedCustomButtonId = null;
        RightSurface.SelectedCustomButtonId = null;

        if (_hasSelectedCustomButton && !string.IsNullOrWhiteSpace(_selectedCustomButtonId))
        {
            if (_selectedKeySide == TrackpadSide.Left)
            {
                LeftSurface.SelectedCustomButtonId = _selectedCustomButtonId;
            }
            else
            {
                RightSurface.SelectedCustomButtonId = _selectedCustomButtonId;
            }
        }
        else if (_hasSelectedKey)
        {
            KeyLayout layout = _selectedKeySide == TrackpadSide.Left ? _leftLayout : _rightLayout;
            if (_selectedKeyRow >= 0 &&
                _selectedKeyRow < layout.Rects.Length &&
                _selectedKeyColumn >= 0 &&
                _selectedKeyColumn < layout.Rects[_selectedKeyRow].Length)
            {
                if (_selectedKeySide == TrackpadSide.Left)
                {
                    LeftSurface.SelectedKey = layout.Rects[_selectedKeyRow][_selectedKeyColumn];
                }
                else
                {
                    RightSurface.SelectedKey = layout.Rects[_selectedKeyRow][_selectedKeyColumn];
                }
            }
        }

        LeftSurface.InvalidateVisual();
        RightSurface.InvalidateVisual();
    }

    private static bool TryHitSelectionAtPoint(
        TouchView surface,
        KeyLayout layout,
        IReadOnlyList<CustomButton> customButtons,
        Point point,
        out int row,
        out int column,
        out string? customButtonId)
    {
        row = -1;
        column = -1;
        customButtonId = null;
        if (layout.Rects.Length == 0 && (customButtons == null || customButtons.Count == 0))
        {
            return false;
        }

        Rect bounds = new(0, 0, surface.ActualWidth, surface.ActualHeight);
        if (bounds.Width <= 1 || bounds.Height <= 1)
        {
            return false;
        }

        if (!TryCreatePadRect(bounds, surface.TrackpadWidthMm, surface.TrackpadHeightMm, out Rect pad))
        {
            return false;
        }

        if (!pad.Contains(point))
        {
            return false;
        }

        double xNorm = (point.X - pad.Left) / pad.Width;
        double yNorm = (point.Y - pad.Top) / pad.Height;
        double bestScore = double.NegativeInfinity;
        double bestArea = double.PositiveInfinity;
        for (int r = 0; r < layout.Rects.Length; r++)
        {
            NormalizedRect[] rowRects = layout.Rects[r];
            for (int c = 0; c < rowRects.Length; c++)
            {
                NormalizedRect rect = rowRects[c];
                if (!rect.Contains(xNorm, yNorm))
                {
                    continue;
                }

                double dx = Math.Min(xNorm - rect.X, rect.X + rect.Width - xNorm);
                double dy = Math.Min(yNorm - rect.Y, rect.Y + rect.Height - yNorm);
                double score = Math.Min(dx, dy);
                double area = rect.Width * rect.Height;
                if (score > bestScore || (Math.Abs(score - bestScore) < 1e-9 && area < bestArea))
                {
                    bestScore = score;
                    bestArea = area;
                    row = r;
                    column = c;
                    customButtonId = null;
                }
            }
        }

        if (customButtons != null)
        {
            for (int i = 0; i < customButtons.Count; i++)
            {
                CustomButton button = customButtons[i];
                NormalizedRect rect = button.Rect;
                if (!rect.Contains(xNorm, yNorm))
                {
                    continue;
                }

                double dx = Math.Min(xNorm - rect.X, rect.X + rect.Width - xNorm);
                double dy = Math.Min(yNorm - rect.Y, rect.Y + rect.Height - yNorm);
                double score = Math.Min(dx, dy);
                double area = rect.Width * rect.Height;
                if (score > bestScore || (Math.Abs(score - bestScore) < 1e-9 && area < bestArea))
                {
                    bestScore = score;
                    bestArea = area;
                    row = -1;
                    column = -1;
                    customButtonId = button.Id;
                }
            }
        }

        return row >= 0 || !string.IsNullOrWhiteSpace(customButtonId);
    }

    private static bool TryCreatePadRect(Rect bounds, double trackpadWidthMm, double trackpadHeightMm, out Rect pad)
    {
        pad = default;
        double padding = 20;
        Rect inner = new(bounds.Left + padding, bounds.Top + padding, bounds.Width - padding * 2, bounds.Height - padding * 2);
        if (inner.Width <= 0 || inner.Height <= 0)
        {
            return false;
        }

        double aspect = trackpadWidthMm <= 0 || trackpadHeightMm <= 0 ? 1.0 : trackpadWidthMm / trackpadHeightMm;
        double width = inner.Width;
        double height = width / aspect;
        if (height > inner.Height)
        {
            height = inner.Height;
            width = height * aspect;
        }

        double x = inner.Left + (inner.Width - width) / 2;
        double y = inner.Top + (inner.Height - height) / 2;
        pad = new Rect(x, y, width, height);
        return true;
    }

    private int GetSelectedLayer()
    {
        int selected = LayerCombo.SelectedIndex;
        if (selected >= 0)
        {
            return Math.Clamp(selected, 0, 3);
        }

        return Math.Clamp(_activeLayer, 0, 3);
    }

    private void UpdateHitForSide(ReaderSession session, TrackpadSide side)
    {
        Span<TouchContact> contacts = stackalloc TouchContact[PtpReport.MaxContacts];
        int contactCount = session.State.SnapshotContacts(contacts);
        KeyLayout layout = side == TrackpadSide.Left ? _leftLayout : _rightLayout;
        int activeLayer = GetVisualizationLayer();
        IReadOnlyList<CustomButton> customButtons = _keymap.ResolveCustomButtons(activeLayer, side);
        ushort maxX = (side == TrackpadSide.Left ? LeftSurface : RightSurface).RequestedMaxX ?? DefaultMaxX;
        ushort maxY = (side == TrackpadSide.Left ? LeftSurface : RightSurface).RequestedMaxY ?? DefaultMaxY;
        bool suppressHighlights = ShouldSuppressKeyHighlighting();

        NormalizedRect? hit = null;
        string? hitCustomButtonId = null;
        string hitLabel = "--";

        if (!suppressHighlights && contactCount > 0 && (layout.Rects.Length > 0 || customButtons.Count > 0))
        {
            TouchContact? selected = null;
            for (int i = 0; i < contactCount; i++)
            {
                TouchContact c = contacts[i];
                if (c.Tip)
                {
                    selected = c;
                    break;
                }
            }

            if (selected.HasValue)
            {
                double xNorm = selected.Value.X / (double)maxX;
                double yNorm = selected.Value.Y / (double)maxY;
                double bestScore = double.NegativeInfinity;
                double bestArea = double.PositiveInfinity;

                for (int row = 0; row < layout.Rects.Length; row++)
                {
                    NormalizedRect[] rowRects = layout.Rects[row];
                    for (int col = 0; col < rowRects.Length; col++)
                    {
                        NormalizedRect rect = rowRects[col];
                        if (!rect.Contains(xNorm, yNorm))
                        {
                            continue;
                        }

                        double dx = Math.Min(xNorm - rect.X, rect.X + rect.Width - xNorm);
                        double dy = Math.Min(yNorm - rect.Y, rect.Y + rect.Height - yNorm);
                        double score = Math.Min(dx, dy);
                        double area = rect.Width * rect.Height;
                        if (score > bestScore || (Math.Abs(score - bestScore) < 1e-9 && area < bestArea))
                        {
                            bestScore = score;
                            bestArea = area;
                            hit = rect;
                            hitCustomButtonId = null;
                            hitLabel = _keymap.ResolveLabel(activeLayer, GridKeyPosition.StorageKey(side, row, col), layout.Labels[row][col]);
                        }
                    }
                }

                for (int i = 0; i < customButtons.Count; i++)
                {
                    CustomButton button = customButtons[i];
                    NormalizedRect rect = button.Rect;
                    if (!rect.Contains(xNorm, yNorm))
                    {
                        continue;
                    }

                    double dx = Math.Min(xNorm - rect.X, rect.X + rect.Width - xNorm);
                    double dy = Math.Min(yNorm - rect.Y, rect.Y + rect.Height - yNorm);
                    double score = Math.Min(dx, dy);
                    double area = rect.Width * rect.Height;
                    if (score > bestScore || (Math.Abs(score - bestScore) < 1e-9 && area < bestArea))
                    {
                        bestScore = score;
                        bestArea = area;
                        hit = rect;
                        hitCustomButtonId = button.Id;
                        hitLabel = string.IsNullOrWhiteSpace(button.Primary?.Label) ? "None" : button.Primary.Label;
                    }
                }
            }
        }

        if (side == TrackpadSide.Left)
        {
            LeftSurface.HighlightedKey = hit;
            LeftSurface.HighlightedCustomButtonId = hitCustomButtonId;
        }
        else
        {
            RightSurface.HighlightedKey = hit;
            RightSurface.HighlightedCustomButtonId = hitCustomButtonId;
        }

        UpdateHitDisplay(side, hitLabel, hit);
    }

    private bool ShouldSuppressKeyHighlighting()
    {
        if (IsReplayMode)
        {
            return false;
        }

        if (!TryGetEngineSnapshot(out TouchProcessorSnapshot snapshot))
        {
            return false;
        }

        IntentMode intent = snapshot.IntentMode;
        return intent is IntentMode.MouseCandidate or IntentMode.MouseActive or IntentMode.GestureCandidate;
    }

    private void UpdateHitDisplay(TrackpadSide side, string hitLabel, NormalizedRect? hit)
    {
        if (side == TrackpadSide.Left)
        {
            LeftSurface.LastHitLabel = hitLabel;
            LeftSurface.InvalidateVisual();
            if (!string.Equals(_lastLeftHit, hitLabel, StringComparison.Ordinal))
            {
                _lastLeftHit = hitLabel;
            }
        }
        else
        {
            RightSurface.LastHitLabel = hitLabel;
            RightSurface.InvalidateVisual();
            if (!string.Equals(_lastRightHit, hitLabel, StringComparison.Ordinal))
            {
                _lastRightHit = hitLabel;
            }
        }
    }

    private void SetEmptyMessage(ReaderSession session, string message)
    {
        if (ReferenceEquals(session, _left))
        {
            LeftSurface.EmptyMessage = message;
        }
        else
        {
            RightSurface.EmptyMessage = message;
        }
    }

    private void InvalidateSurface(ReaderSession session)
    {
        if (ReferenceEquals(session, _left))
        {
            LeftSurface.InvalidateVisual();
        }
        else
        {
            RightSurface.InvalidateVisual();
        }
    }

    private void UpdateHeaderStatus()
    {
        if (IsReplayMode)
        {
            UpdateReplayHeaderStatus();
        }
    }

    private void UpdateReplayHeaderStatus()
    {
        UpdateReplayTimelineControls();
    }

    private void OnReplayToggleClicked(object sender, RoutedEventArgs e)
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

    private void OnReplayStepBackClicked(object sender, RoutedEventArgs e)
    {
        if (!IsReplayMode)
        {
            return;
        }

        PauseReplay();
        SeekToFrameIndex(_replayFrameIndex - 1);
    }

    private void OnReplayStepForwardClicked(object sender, RoutedEventArgs e)
    {
        if (!IsReplayMode)
        {
            return;
        }

        PauseReplay();
        SeekToFrameIndex(_replayFrameIndex + 1);
    }

    private void OnReplayLoopChanged(object sender, RoutedEventArgs e)
    {
        if (!IsReplayMode)
        {
            return;
        }

        _replayLoop = ReplayLoopCheckBox.IsChecked == true;
        UpdateReplayHeaderStatus();
    }

    private void OnReplayTimelineChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!IsReplayMode || _suppressReplayTimelineEvents || _replayData == null)
        {
            return;
        }

        bool wasRunning = _replayRunning;
        PauseReplay();

        double ratio = ReplayTimelineSlider.Maximum <= 0 ? 0 : ReplayTimelineSlider.Value / ReplayTimelineSlider.Maximum;
        double targetProgressTicks = ratio * _replayDurationTicks;
        SeekToProgressTicks(targetProgressTicks);

        if (wasRunning)
        {
            StartReplay();
        }
    }

    private void OnReplaySpeedChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsReplayMode || _suppressReplaySpeedEvents)
        {
            return;
        }

        if (ReplaySpeedCombo.SelectedItem is not ReplaySpeedOption option)
        {
            return;
        }

        long now = Stopwatch.GetTimestamp();
        if (_replayRunning)
        {
            _replayAccumulatedTicks = GetReplayProgressTicks(now);
            _replayPlayStartTicks = now;
        }

        _replaySpeed = option.Speed;
        UpdateReplayHeaderStatus();
    }

    private void StartReplay()
    {
        if (_replayData == null || _replayData.Frames.Length == 0)
        {
            return;
        }

        if (_replayCompleted)
        {
            RestartReplayFromBeginning();
        }

        _replayRunning = true;
        _replayPlayStartTicks = Stopwatch.GetTimestamp();
        _replayTimer?.Start();
        ReplayToggleButton.Content = "Pause";
        SetEmptyMessage(_left, "Replaying...");
        SetEmptyMessage(_right, "Replaying...");
        UpdateReplayHeaderStatus();
    }

    private void PauseReplay()
    {
        if (!_replayRunning)
        {
            return;
        }

        long now = Stopwatch.GetTimestamp();
        _replayAccumulatedTicks = ClampReplayProgress(GetReplayProgressTicks(now));
        _replayRunning = false;
        _replayTimer?.Stop();
        ReplayToggleButton.Content = _replayCompleted ? "Replay" : "Resume";
        UpdateReplayHeaderStatus();
    }

    private void RestartReplayFromBeginning()
    {
        _replayFrameIndex = 0;
        _replayAccumulatedTicks = 0;
        _replayCompleted = false;
        ResetReplayEngineState();
        _left.State.Clear();
        _right.State.Clear();
        LeftSurface.HighlightedKey = null;
        RightSurface.HighlightedKey = null;
        LeftSurface.HighlightedCustomButtonId = null;
        RightSurface.HighlightedCustomButtonId = null;
        UpdateHitDisplay(TrackpadSide.Left, "--", null);
        UpdateHitDisplay(TrackpadSide.Right, "--", null);
        InvalidateSurface(_left);
        InvalidateSurface(_right);
        UpdateReplayTimelineControls();
    }

    private void ResetReplayEngineState()
    {
        if (_touchActor == null)
        {
            return;
        }

        _touchActor.WaitForIdle(2000);
        _touchActor.ResetState();
        _dispatchQueue?.Clear();
        _touchActor.SetPersistentLayer(_activeLayer);
        _touchActor.SetTypingEnabled(true);
        _touchActor.SetKeyboardModeEnabled(_settings.KeyboardModeEnabled);
        _touchActor.SetAllowMouseTakeover(true);
        UpdateEngineStateDetails();
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

    private void SeekToProgressTicks(double targetProgressTicks)
    {
        if (_replayData == null)
        {
            return;
        }

        double clampedProgress = ClampReplayProgress(targetProgressTicks);
        int targetFrameIndex = ResolveFrameIndexForProgress(clampedProgress);
        SeekToFrameIndex(targetFrameIndex, clampedProgress);
    }

    private void SeekToFrameIndex(int targetFrameIndex, double? targetProgressTicks = null)
    {
        if (_replayData == null)
        {
            return;
        }

        if (targetFrameIndex < 0)
        {
            targetFrameIndex = 0;
        }
        else if (targetFrameIndex > _replayData.Frames.Length)
        {
            targetFrameIndex = _replayData.Frames.Length;
        }

        if (targetFrameIndex < _replayFrameIndex)
        {
            RestartReplayFromBeginning();
        }

        while (_replayFrameIndex < targetFrameIndex)
        {
            ReplayVisualFrame replayFrame = _replayData.Frames[_replayFrameIndex++];
            ApplyReplayFrame(replayFrame);
        }

        _replayAccumulatedTicks = targetProgressTicks ?? ReplayProgressForFrameIndex(targetFrameIndex);
        _replayAccumulatedTicks = ClampReplayProgress(_replayAccumulatedTicks);
        _replayCompleted = _replayFrameIndex >= _replayData.Frames.Length;
        ReplayToggleButton.Content = _replayCompleted ? "Replay" : "Resume";
        if (_replayCompleted)
        {
            SetEmptyMessage(_left, "Replay completed.");
            SetEmptyMessage(_right, "Replay completed.");
        }
        else
        {
            SetEmptyMessage(_left, "Replaying...");
            SetEmptyMessage(_right, "Replaying...");
        }

        UpdateReplayHeaderStatus();
    }

    private static int ResolveFrameIndexForProgressCore(ReplayVisualFrame[] frames, double progressTicks)
    {
        int lo = 0;
        int hi = frames.Length;
        while (lo < hi)
        {
            int mid = lo + ((hi - lo) >> 1);
            if (frames[mid].OffsetStopwatchTicks <= progressTicks)
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

    private int ResolveFrameIndexForProgress(double progressTicks)
    {
        if (_replayData == null || _replayData.Frames.Length == 0)
        {
            return 0;
        }

        return ResolveFrameIndexForProgressCore(_replayData.Frames, progressTicks);
    }

    private double ReplayProgressForFrameIndex(int frameIndex)
    {
        if (_replayData == null || _replayData.Frames.Length == 0 || frameIndex <= 0)
        {
            return 0;
        }

        if (frameIndex >= _replayData.Frames.Length)
        {
            return _replayDurationTicks;
        }

        return _replayData.Frames[frameIndex - 1].OffsetStopwatchTicks;
    }

    private double ClampReplayProgress(double progressTicks)
    {
        if (_replayDurationTicks <= 0)
        {
            return 0;
        }

        if (progressTicks < 0)
        {
            return 0;
        }

        if (progressTicks > _replayDurationTicks)
        {
            return _replayDurationTicks;
        }

        return progressTicks;
    }

    private void UpdateReplayTimelineControls()
    {
        if (!IsReplayMode)
        {
            return;
        }

        double progressTicks = _replayRunning
            ? ClampReplayProgress(GetReplayProgressTicks(Stopwatch.GetTimestamp()))
            : ClampReplayProgress(_replayAccumulatedTicks);
        double ratio = _replayDurationTicks <= 0 ? 0 : progressTicks / _replayDurationTicks;
        double elapsedSeconds = progressTicks / Stopwatch.Frequency;
        double totalSeconds = _replayDurationTicks / (double)Stopwatch.Frequency;

        _suppressReplayTimelineEvents = true;
        ReplayTimelineSlider.Value = ratio * ReplayTimelineSlider.Maximum;
        _suppressReplayTimelineEvents = false;

        ReplayTimeText.Text = $"{elapsedSeconds:0.00}s / {totalSeconds:0.00}s";
        ReplayStepBackButton.IsEnabled = _replayFrameIndex > 0;
        ReplayStepForwardButton.IsEnabled = _replayData != null && _replayFrameIndex < _replayData.Frames.Length;
    }

    private void ApplyReplayFrame(in ReplayVisualFrame replayFrame)
    {
        InputFrame frame = replayFrame.Frame;
        // Replay captures preserve original arrival ticks, which are not comparable to the
        // current process Stopwatch timeline used by TouchState staleness checks.
        // Stamp replay-applied frames with the local clock so visual contact snapshots stay live.
        frame.ArrivalQpcTicks = Stopwatch.GetTimestamp();
        DispatchReport(replayFrame.Snapshot, in frame, replayFrame.OffsetStopwatchTicks);
    }

    private void OnReplayTick(object? sender, EventArgs e)
    {
        if (!_replayRunning || _replayData == null)
        {
            return;
        }

        long now = Stopwatch.GetTimestamp();
        double progressTicks = GetReplayProgressTicks(now);
        while (_replayFrameIndex < _replayData.Frames.Length &&
               _replayData.Frames[_replayFrameIndex].OffsetStopwatchTicks <= progressTicks)
        {
            ReplayVisualFrame replayFrame = _replayData.Frames[_replayFrameIndex++];
            ApplyReplayFrame(in replayFrame);
        }

        if (_replayFrameIndex >= _replayData.Frames.Length)
        {
            if (_replayLoop && _replayDurationTicks > 0)
            {
                double overflow = progressTicks - _replayDurationTicks;
                if (overflow < 0)
                {
                    overflow = 0;
                }

                RestartReplayFromBeginning();
                _replayAccumulatedTicks = overflow;
                _replayPlayStartTicks = now;
                SeekToProgressTicks(_replayAccumulatedTicks);
                ReplayToggleButton.Content = "Pause";
            }
            else
            {
                _replayAccumulatedTicks = ClampReplayProgress(progressTicks);
                _replayRunning = false;
                _replayCompleted = true;
                _replayTimer?.Stop();
                ReplayToggleButton.Content = "Replay";
                SetEmptyMessage(_left, "Replay completed.");
                SetEmptyMessage(_right, "Replay completed.");
            }
        }

        UpdateReplayHeaderStatus();
    }

    private void PersistSelections()
    {
        if (IsReplayMode)
        {
            return;
        }

        string? leftPath = (LeftDeviceCombo.SelectedItem as HidDeviceInfo)?.Path;
        string? rightPath = (RightDeviceCombo.SelectedItem as HidDeviceInfo)?.Path;
        _settings.LeftDevicePath = leftPath;
        _settings.RightDevicePath = rightPath;
        _settings.Save();
        _runtimeService?.UpdateDeviceSelections(leftPath, rightPath);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == RawInputInterop.WM_INPUT)
        {
            HandleRawInput(lParam);
        }

        return IntPtr.Zero;
    }

    private void HandleRawInput(IntPtr lParam)
    {
        if (IsReplayMode)
        {
            return;
        }

        long nowTicks = Stopwatch.GetTimestamp();
        if (_rawInputPauseUntilTicks > nowTicks)
        {
            return;
        }

        if (!RawInputInterop.TryGetRawInputPacket(lParam, out RawInputPacket packet))
        {
            return;
        }

        if (!_rawInputContext.TryGetSnapshot(packet.DeviceHandle, out RawInputDeviceSnapshot snapshot))
        {
            return;
        }

        if (!RawInputInterop.IsTargetDevice(snapshot.Info) || !RawInputInterop.IsPreferredInterfaceName(snapshot.DeviceName))
        {
            return;
        }

        int reportSize = (int)packet.ReportSize;
        if (reportSize <= 0)
        {
            return;
        }

        for (uint i = 0; i < packet.ReportCount; i++)
        {
            long started = Stopwatch.GetTimestamp();
            _liveMetrics.RecordSeen();

            int offset = packet.DataOffset + (int)(i * packet.ReportSize);
            if (offset + reportSize > packet.ValidLength)
            {
                _liveMetrics.RecordDropped(FrameDropReason.PacketTruncated);
                break;
            }

            ReadOnlySpan<byte> reportSpan = packet.Buffer.AsSpan(offset, reportSize);
            _captureWriter?.WriteFrame(snapshot, reportSpan, started);
            try
            {
                TrackpadDecoderProfile decoderProfile = ResolveDecoderProfile(snapshot.DeviceName);
                if (!TrackpadReportDecoder.TryDecode(reportSpan, snapshot.Info, started, decoderProfile, out TrackpadDecodeResult decoded))
                {
                    _liveMetrics.RecordDropped(FrameDropReason.NonMultitouchReport);
                    continue;
                }

                bool leftMatch = _left.IsMatch(snapshot.DeviceName);
                bool rightMatch = _right.IsMatch(snapshot.DeviceName);
                TraceDecoderSelection(snapshot, decoderProfile, decoded, leftMatch, rightMatch);

                _liveMetrics.RecordParsed();
                InputFrame frame = decoded.Frame;
                if (!DispatchReport(snapshot, in frame))
                {
                    _liveMetrics.RecordDropped(FrameDropReason.RoutedToNoSession);
                    continue;
                }

                _liveMetrics.RecordDispatched(started);
            }
            catch (Exception ex)
            {
                RegisterRawInputFault(
                    source: "MainWindow.HandleRawInput",
                    ex,
                    snapshot,
                    packet,
                    i,
                    reportSize,
                    offset,
                    reportSpan);
            }
        }
    }

    private void TraceDecoderSelection(
        in RawInputDeviceSnapshot snapshot,
        TrackpadDecoderProfile preferredProfile,
        in TrackpadDecodeResult decoded,
        bool leftMatch,
        bool rightMatch)
    {
        if (!_options.DecoderDebug)
        {
            return;
        }

        if (leftMatch)
        {
            TraceDecoderSelectionForSide(TrackpadSide.Left, snapshot, preferredProfile, decoded);
        }

        if (rightMatch)
        {
            TraceDecoderSelectionForSide(TrackpadSide.Right, snapshot, preferredProfile, decoded);
        }
    }

    private void TraceDecoderSelectionForSide(
        TrackpadSide side,
        in RawInputDeviceSnapshot snapshot,
        TrackpadDecoderProfile preferredProfile,
        in TrackpadDecodeResult decoded)
    {
        long now = Stopwatch.GetTimestamp();
        TrackpadDecoderProfile? lastProfile = side == TrackpadSide.Left ? _lastDecoderProfileLeft : _lastDecoderProfileRight;
        long lastLogTicks = side == TrackpadSide.Left ? _lastDecoderProfileLogLeftTicks : _lastDecoderProfileLogRightTicks;

        bool profileChanged = !lastProfile.HasValue || lastProfile.Value != decoded.Profile;
        bool throttled = now - lastLogTicks < Stopwatch.Frequency;
        if (!profileChanged && throttled)
        {
            return;
        }

        if (side == TrackpadSide.Left)
        {
            _lastDecoderProfileLeft = decoded.Profile;
            _lastDecoderProfileLogLeftTicks = now;
        }
        else
        {
            _lastDecoderProfileRight = decoded.Profile;
            _lastDecoderProfileLogRightTicks = now;
        }

        int count = decoded.Frame.GetClampedContactCount();
        string firstContact = "none";
        if (count > 0)
        {
            ContactFrame c0 = decoded.Frame.GetContact(0);
            firstContact = $"id={c0.Id} flags=0x{c0.Flags:X2} x={c0.X} y={c0.Y}";
        }

        Console.WriteLine(
            $"[decoder] side={side} pref={preferredProfile} picked={decoded.Profile} kind={decoded.Kind} count={count} " +
            $"first={firstContact} tag={RawInputInterop.FormatTag(snapshot.Tag)} " +
            $"vid=0x{(ushort)snapshot.Info.VendorId:X4} pid=0x{(ushort)snapshot.Info.ProductId:X4} " +
            $"usage=0x{snapshot.Info.UsagePage:X2}/0x{snapshot.Info.Usage:X2}");
    }

    private TrackpadDecoderProfile ResolveDecoderProfile(string deviceName)
    {
        return GetConfiguredDecoderProfile(deviceName);
    }

    private TrackpadDecoderProfile GetConfiguredDecoderProfile(string deviceName)
    {
        if (_decoderProfilesByPath.TryGetValue(deviceName, out TrackpadDecoderProfile profile))
        {
            return NormalizeConfiguredProfile(profile);
        }

        return TrackpadDecoderProfile.Official;
    }

    private void RegisterRawInputFault(
        string source,
        Exception ex,
        in RawInputDeviceSnapshot snapshot,
        in RawInputPacket packet,
        uint reportIndex,
        int reportSize,
        int offset,
        ReadOnlySpan<byte> reportSpan)
    {
        string context = RuntimeFaultLogger.BuildRawInputContext(snapshot, packet, reportIndex, reportSize, offset, reportSpan);
        RuntimeFaultLogger.LogException(source, ex, context);

        long nowTicks = Stopwatch.GetTimestamp();
        if (nowTicks - _lastRawInputFaultTicks > Stopwatch.Frequency)
        {
            _consecutiveRawInputFaults = 0;
        }

        _lastRawInputFaultTicks = nowTicks;
        _consecutiveRawInputFaults++;
        if (_consecutiveRawInputFaults >= 3)
        {
            _rawInputPauseUntilTicks = nowTicks + (Stopwatch.Frequency * 2);
            _consecutiveRawInputFaults = 0;
        }
    }

    private bool DispatchReport(RawInputDeviceSnapshot snapshot, in InputFrame report, long? replayTimestampTicks = null)
    {
        bool leftMatch = _left.IsMatch(snapshot.DeviceName);
        bool rightMatch = _right.IsMatch(snapshot.DeviceName);
        long timestampTicks = replayTimestampTicks ?? report.ArrivalQpcTicks;

        if (!leftMatch && !rightMatch)
        {
            return false;
        }

        if (leftMatch)
        {
            ApplyReport(_left, snapshot, in report, TrackpadSide.Left);
            PostToEngine(TrackpadSide.Left, in report, LeftSurface.RequestedMaxX ?? DefaultMaxX, LeftSurface.RequestedMaxY ?? DefaultMaxY, timestampTicks);
        }

        if (rightMatch)
        {
            ApplyReport(_right, snapshot, in report, TrackpadSide.Right);
            PostToEngine(TrackpadSide.Right, in report, RightSurface.RequestedMaxX ?? DefaultMaxX, RightSurface.RequestedMaxY ?? DefaultMaxY, timestampTicks);
        }

        return true;
    }

    private void ApplyReport(ReaderSession session, RawInputDeviceSnapshot snapshot, in InputFrame report, TrackpadSide side)
    {
        ApplyReport(session, snapshot.Tag, in report, side);
    }

    private void ApplyReport(ReaderSession session, RawInputDeviceTag tag, in InputFrame report, TrackpadSide side)
    {
        session.State.Update(in report);

        string tagText = RawInputInterop.FormatTag(tag);
        if (!string.Equals(session.TagText, tagText, StringComparison.Ordinal))
        {
            session.UpdateTag(tag);
            if (side == TrackpadSide.Left) _leftStatus = tagText;
            else _rightStatus = tagText;
            UpdateHeaderStatus();
        }

        if (_visualizerEnabled)
        {
            UpdateHitForSide(session, side);
            InvalidateSurface(session);
        }
    }

    void IRuntimeFrameObserver.OnRuntimeFrame(TrackpadSide side, in InputFrame frame, RawInputDeviceTag tag)
    {
        if (IsReplayMode || !UsesSharedRuntime)
        {
            return;
        }

        ReaderSession session = side == TrackpadSide.Left ? _left : _right;
        if (string.IsNullOrWhiteSpace(session.DeviceName))
        {
            return;
        }

        ApplyReport(session, tag, in frame, side);
    }

    private void PostToEngine(TrackpadSide side, in InputFrame report, ushort maxX, ushort maxY, long timestampTicks)
    {
        if (_touchActor == null)
        {
            UpdateEngineStateDetails();
            return;
        }

        if (!_touchActor.Post(side, in report, maxX, maxY, timestampTicks))
        {
            _liveMetrics.RecordDropped(FrameDropReason.EngineQueueFull);
        }

        UpdateEngineStateDetails();
    }

    private void UpdateEngineStateDetails()
    {
        string next;
        int leftContacts;
        int rightContacts;
        string intentLabel;
        Brush intentBrush;
        string modeLabel;
        Brush modeBrush;
        bool suppressGlobalClicks;
        if (!TryGetEngineSnapshot(out TouchProcessorSnapshot snapshot))
        {
            next = "State: n/a";
            leftContacts = SnapshotContactCount(_left.State);
            rightContacts = SnapshotContactCount(_right.State);
            intentLabel = "n/a";
            intentBrush = IntentUnknownBrush;
            modeLabel = "n/a";
            modeBrush = ModeUnknownBrush;
            suppressGlobalClicks = _settings.KeyboardModeEnabled && _settings.TypingEnabled;
        }
        else
        {
            next = $"State: {snapshot.IntentMode} | layer {snapshot.ActiveLayer} | contacts {snapshot.ContactCount}";
            leftContacts = snapshot.LeftContacts;
            rightContacts = snapshot.RightContacts;
            (intentLabel, intentBrush) = ToIntentPill(snapshot.IntentMode);
            (modeLabel, modeBrush) = ToModePill(snapshot.TypingEnabled, snapshot.KeyboardModeEnabled);
            suppressGlobalClicks = snapshot.KeyboardModeEnabled && snapshot.TypingEnabled;
            if (_lastEngineVisualLayer != snapshot.ActiveLayer)
            {
                _lastEngineVisualLayer = snapshot.ActiveLayer;
                SyncEditorLayerToRuntime(snapshot.ActiveLayer);
                UpdateLabelMatrices();
                RefreshKeymapEditor();
            }
        }

        UpdateGlobalClickSuppressionState(suppressGlobalClicks);
        UpdateStatusPills(leftContacts, rightContacts, intentLabel, intentBrush, modeLabel, modeBrush);

        if (!string.Equals(next, _engineStateText, StringComparison.Ordinal))
        {
            _engineStateText = next;
            StatusText.Text = next;
        }
    }

    private void UpdateStatusPills(int leftContacts, int rightContacts, string intentLabel, Brush intentBrush, string modeLabel, Brush modeBrush)
    {
        leftContacts = Math.Max(0, leftContacts);
        rightContacts = Math.Max(0, rightContacts);
        if (leftContacts != _lastLeftPillCount)
        {
            _lastLeftPillCount = leftContacts;
            LeftContactsPillText.Text = $"L {leftContacts}";
        }

        if (rightContacts != _lastRightPillCount)
        {
            _lastRightPillCount = rightContacts;
            RightContactsPillText.Text = $"R {rightContacts}";
        }

        if (!string.Equals(intentLabel, _lastIntentPillLabel, StringComparison.Ordinal))
        {
            _lastIntentPillLabel = intentLabel;
            IntentPillText.Text = intentLabel;
        }

        if (!ReferenceEquals(intentBrush, _lastIntentPillBrush))
        {
            _lastIntentPillBrush = intentBrush;
            IntentPillDot.Fill = intentBrush;
        }

        if (!string.Equals(modeLabel, _lastModePillLabel, StringComparison.Ordinal))
        {
            _lastModePillLabel = modeLabel;
            ModePillText.Text = modeLabel;
        }

        if (!ReferenceEquals(modeBrush, _lastModePillBrush))
        {
            _lastModePillBrush = modeBrush;
            ModePillDot.Fill = modeBrush;
        }
    }

    private static int SnapshotContactCount(TouchState state)
    {
        Span<TouchContact> contacts = stackalloc TouchContact[PtpReport.MaxContacts];
        return state.SnapshotContacts(contacts);
    }

    private int GetVisualizationLayer()
    {
        if (!TryGetEngineSnapshot(out TouchProcessorSnapshot snapshot))
        {
            return GetSelectedLayer();
        }

        return Math.Clamp(snapshot.ActiveLayer, 0, 7);
    }

    private void SyncEditorLayerToRuntime(int runtimeLayer)
    {
        int clamped = Math.Clamp(runtimeLayer, 0, 3);
        if (LayerCombo.SelectedIndex == clamped)
        {
            return;
        }

        _suppressLayerEvent = true;
        LayerCombo.SelectedIndex = clamped;
        _suppressLayerEvent = false;
    }

    private bool TryGetEngineSnapshot(out TouchProcessorSnapshot snapshot)
    {
        if (_touchActor != null)
        {
            snapshot = _touchActor.Snapshot();
            return true;
        }

        if (_runtimeService != null)
        {
            return _runtimeService.TryGetSnapshot(out snapshot);
        }

        snapshot = default;
        return false;
    }

    private static (string Label, Brush Brush) ToIntentPill(IntentMode mode)
    {
        return mode switch
        {
            IntentMode.Idle => ("idle", IntentIdleBrush),
            IntentMode.KeyCandidate => ("cand", IntentCandidateBrush),
            IntentMode.TypingCommitted => ("typing", IntentTypingBrush),
            IntentMode.MouseCandidate => ("mouse", IntentMouseBrush),
            IntentMode.MouseActive => ("mouse", IntentMouseBrush),
            IntentMode.GestureCandidate => ("gest", IntentGestureBrush),
            _ => ("n/a", IntentUnknownBrush)
        };
    }

    private static (string Label, Brush Brush) ToModePill(bool typingEnabled, bool keyboardModeEnabled)
    {
        if (!typingEnabled)
        {
            return ("Mouse", ModeMouseBrush);
        }

        return keyboardModeEnabled
            ? ("Keyboard", ModeKeyboardBrush)
            : ("Mixed", ModeMixedBrush);
    }

    private sealed class KeyActionOption
    {
        public KeyActionOption(string value, string display, string group)
        {
            Value = value;
            Display = display;
            Group = group;
        }

        public string Value { get; }
        public string Display { get; }
        public string Group { get; }
    }

    private readonly record struct DecoderProfileOption(TrackpadDecoderProfile Profile, string Label)
    {
        public override string ToString() => Label;
    }

    private readonly record struct ReplaySpeedOption(double Speed, string Label)
    {
        public override string ToString() => Label;
    }

    private sealed class SettingsBundleFile
    {
        public int Version { get; set; } = 1;
        public UserSettings Settings { get; set; } = new();
        public string KeymapJson { get; set; } = string.Empty;
    }

    private sealed class ReaderSession
    {
        public ReaderSession(string label)
        {
            State = new TouchState();
            DisplayName = label;
        }

        public TouchState State { get; }
        public string? DeviceName { get; private set; }
        public string DisplayName { get; private set; }
        public RawInputDeviceTag? Tag { get; private set; }
        public string? TagText { get; private set; }

        public bool IsMatch(string deviceName)
        {
            return !string.IsNullOrWhiteSpace(DeviceName) &&
                   string.Equals(DeviceName, deviceName, StringComparison.OrdinalIgnoreCase);
        }

        public void SetDevice(string deviceName, string displayName)
        {
            DeviceName = deviceName;
            DisplayName = displayName;
            Tag = null;
            TagText = null;
            State.Clear();
        }

        public void Reset()
        {
            DeviceName = null;
            DisplayName = string.Empty;
            Tag = null;
            TagText = null;
            State.Clear();
        }

        public void UpdateTag(RawInputDeviceTag tag)
        {
            Tag = tag;
            TagText = RawInputInterop.FormatTag(tag);
        }
    }
}
