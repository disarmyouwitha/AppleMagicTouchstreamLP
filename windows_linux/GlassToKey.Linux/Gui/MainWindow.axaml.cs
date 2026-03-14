using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Controls.Templates;
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
    private const int MaxSupportedLayer = 3;
    private const int LinuxForceSliderMaximum = 255;
    private const double TrackpadWidthMm = 160.0;
    private const double TrackpadHeightMm = 114.9;
    private const double KeyWidthMm = 18.0;
    private const double KeyHeightMm = 17.0;
    private const double MinCustomButtonPercent = 5.0;
    private const string TerminalLauncherCommand = "x-terminal-emulator";
    private static readonly string TerminalActionValue = AppLaunchActionHelper.CreateActionLabel(TerminalLauncherCommand);
    private static readonly IDataTemplate KeyActionChoiceTemplate = CreateKeyActionChoiceTemplate();
    private static readonly IDataTemplate ShortcutKeyChoiceTemplate = CreateShortcutKeyChoiceTemplate();
    private readonly LinuxAppRuntime _runtime = new();
    private readonly LinuxDesktopRuntimeController _desktopRuntime;
    private KeyLayout _leftRenderedLayout = new(Array.Empty<NormalizedRect[]>(), Array.Empty<string[]>());
    private KeyLayout _rightRenderedLayout = new(Array.Empty<NormalizedRect[]>(), Array.Empty<string[]>());
    private KeymapStore _renderedKeymap = KeymapStore.LoadBundledDefault();
    private readonly ComboBox _leftDeviceCombo;
    private readonly ComboBox _rightDeviceCombo;
    private readonly ComboBox _layoutPresetCombo;
    private readonly ComboBox _columnLayoutColumnCombo;
    private readonly StackPanel _typingTuningPanel;
    private readonly StackPanel _gestureSectionsPanel;
    private readonly Expander _keymapTuningExpander;
    private readonly Expander _customButtonsExpander;
    private readonly ComboBox _keymapLayerCombo;
    private readonly ComboBox _keymapPrimaryCombo;
    private readonly ComboBox _keymapHoldCombo;
    private readonly TextBlock _gestureShortcutTargetText;
    private readonly RadioButton _shortcutTargetPrimaryRadio;
    private readonly RadioButton _shortcutTargetHoldRadio;
    private readonly ToggleButton _gestureShortcutCtrlToggle;
    private readonly ToggleButton _gestureShortcutShiftToggle;
    private readonly ToggleButton _gestureShortcutAltToggle;
    private readonly ToggleButton _gestureShortcutWinToggle;
    private readonly ComboBox _gestureShortcutKeyCombo;
    private readonly TextBox _appLauncherFileBox;
    private readonly Button _appLauncherBrowseButton;
    private readonly Button _gestureShortcutApplyButton;
    private readonly TextBlock _gestureShortcutPreviewText;
    private readonly CheckBox _keyboardModeCheck;
    private readonly CheckBox _runAtStartupCheck;
    private readonly CheckBox _startInTrayOnLaunchCheck;
    private readonly CheckBox _snapRadiusModeCheck;
    private readonly CheckBox _holdRepeatModeCheck;
    private readonly CheckBox _threeFingerDragModeCheck;
    private readonly CheckBox _autocorrectModeCheck;
    private readonly Border _autocorrectStatusBorder;
    private readonly Button _keymapClearSelectionButton;
    private readonly Button _columnAutoSplayButton;
    private readonly Button _columnEvenSpaceButton;
    private readonly TextBlock _keymapSelectionText;
    private readonly TextBlock _autocorrectRuntimeStateText;
    private readonly TextBlock _autocorrectLastCorrectedValueText;
    private readonly TextBlock _autocorrectCurrentBufferValueText;
    private readonly TextBlock _autocorrectSkipReasonValueText;
    private readonly TextBlock _autocorrectResetSourceValueText;
    private readonly TextBlock _autocorrectWordHistoryValueText;
    private readonly TextBox _columnScaleBox;
    private readonly TextBox _keyPaddingBox;
    private readonly TextBox _columnOffsetXBox;
    private readonly TextBox _columnOffsetYBox;
    private readonly TextBox _columnRotationBox;
    private readonly TextBox _keyRotationBox;
    private readonly TextBox _autocorrectBlacklistBox;
    private readonly TextBox _autocorrectOverridesBox;
    private readonly Button _customButtonAddLeftButton;
    private readonly Button _customButtonAddRightButton;
    private readonly Button _customButtonDeleteButton;
    private readonly Grid _customButtonGeometryGrid;
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
    private List<KeyActionChoice> _keyActionChoices = BuildKeyActionChoices();
    private readonly List<ShortcutKeyChoice> _shortcutKeyChoices = BuildShortcutKeyChoices();
    private HashSet<string> _keyActionChoiceLookup = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, TextBox> _typingTuningTextBoxes = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Slider> _typingTuningSliders = new(StringComparer.Ordinal);
    private readonly Dictionary<string, TextBlock> _typingTuningSliderValueTexts = new(StringComparer.Ordinal);
    private readonly Dictionary<string, ComboBox> _gestureActionCombos = new(StringComparer.Ordinal);
    private Slider? _hapticsStrengthSlider;
    private TextBlock? _hapticsStrengthValueText;
    private bool _allowExit;
    private bool _runtimeOwnedByTray;
    private bool _loadingScreen;
    private bool _settingsApplyPending;
    private bool _hideInProgress;
    private bool _suppressColumnLayoutEvents;
    private bool _suppressKeymapEditorEvents;
    private bool _suppressGestureShortcutEditorEvents;
    private bool _suppressAppLauncherEditorEvents;
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
    private ColumnLayoutSettings[] _columnSettings = Array.Empty<ColumnLayoutSettings>();
    private string _leftStickyTouchedKeys = "Touched keys: (none)";
    private string _rightStickyTouchedKeys = "Touched keys: (none)";
    private string _lastAutocorrectUiRuntimeState = string.Empty;
    private string _lastAutocorrectUiLastCorrected = string.Empty;
    private string _lastAutocorrectUiCurrentBuffer = string.Empty;
    private string _lastAutocorrectUiSkipReason = string.Empty;
    private string _lastAutocorrectUiResetSource = string.Empty;
    private string _lastAutocorrectUiWordHistory = string.Empty;
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
        _columnLayoutColumnCombo = RequireControl<ComboBox>("ColumnLayoutColumnCombo");
        _typingTuningPanel = RequireControl<StackPanel>("TypingTuningPanel");
        _gestureSectionsPanel = RequireControl<StackPanel>("GestureSectionsPanel");
        _keymapTuningExpander = RequireControl<Expander>("KeymapTuningExpander");
        _customButtonsExpander = RequireControl<Expander>("CustomButtonsExpander");
        _keymapLayerCombo = RequireControl<ComboBox>("KeymapLayerCombo");
        _keymapPrimaryCombo = RequireControl<ComboBox>("KeymapPrimaryCombo");
        _keymapHoldCombo = RequireControl<ComboBox>("KeymapHoldCombo");
        _gestureShortcutTargetText = RequireControl<TextBlock>("GestureShortcutTargetText");
        _shortcutTargetPrimaryRadio = RequireControl<RadioButton>("ShortcutTargetPrimaryRadio");
        _shortcutTargetHoldRadio = RequireControl<RadioButton>("ShortcutTargetHoldRadio");
        _gestureShortcutCtrlToggle = RequireControl<ToggleButton>("GestureShortcutCtrlToggle");
        _gestureShortcutShiftToggle = RequireControl<ToggleButton>("GestureShortcutShiftToggle");
        _gestureShortcutAltToggle = RequireControl<ToggleButton>("GestureShortcutAltToggle");
        _gestureShortcutWinToggle = RequireControl<ToggleButton>("GestureShortcutWinToggle");
        _gestureShortcutKeyCombo = RequireControl<ComboBox>("GestureShortcutKeyCombo");
        _appLauncherFileBox = RequireControl<TextBox>("AppLauncherFileBox");
        _appLauncherBrowseButton = RequireControl<Button>("AppLauncherBrowseButton");
        _gestureShortcutApplyButton = RequireControl<Button>("GestureShortcutApplyButton");
        _gestureShortcutPreviewText = RequireControl<TextBlock>("GestureShortcutPreviewText");
        _keyboardModeCheck = RequireControl<CheckBox>("KeyboardModeCheck");
        _runAtStartupCheck = RequireControl<CheckBox>("RunAtStartupCheck");
        _startInTrayOnLaunchCheck = RequireControl<CheckBox>("StartInTrayOnLaunchCheck");
        _snapRadiusModeCheck = RequireControl<CheckBox>("SnapRadiusModeCheck");
        _holdRepeatModeCheck = RequireControl<CheckBox>("HoldRepeatModeCheck");
        _threeFingerDragModeCheck = RequireControl<CheckBox>("ThreeFingerDragModeCheck");
        _autocorrectModeCheck = RequireControl<CheckBox>("AutocorrectModeCheck");
        _autocorrectStatusBorder = RequireControl<Border>("AutocorrectStatusBorder");
        _keymapClearSelectionButton = RequireControl<Button>("KeymapClearSelectionButton");
        _columnAutoSplayButton = RequireControl<Button>("ColumnAutoSplayButton");
        _columnEvenSpaceButton = RequireControl<Button>("ColumnEvenSpaceButton");
        _keymapSelectionText = RequireControl<TextBlock>("KeymapSelectionText");
        _autocorrectRuntimeStateText = RequireControl<TextBlock>("AutocorrectRuntimeStateText");
        _autocorrectLastCorrectedValueText = RequireControl<TextBlock>("AutocorrectLastCorrectedValueText");
        _autocorrectCurrentBufferValueText = RequireControl<TextBlock>("AutocorrectCurrentBufferValueText");
        _autocorrectSkipReasonValueText = RequireControl<TextBlock>("AutocorrectSkipReasonValueText");
        _autocorrectResetSourceValueText = RequireControl<TextBlock>("AutocorrectResetSourceValueText");
        _autocorrectWordHistoryValueText = RequireControl<TextBlock>("AutocorrectWordHistoryValueText");
        _columnScaleBox = RequireControl<TextBox>("ColumnScaleBox");
        _keyPaddingBox = RequireControl<TextBox>("KeyPaddingBox");
        _columnOffsetXBox = RequireControl<TextBox>("ColumnOffsetXBox");
        _columnOffsetYBox = RequireControl<TextBox>("ColumnOffsetYBox");
        _columnRotationBox = RequireControl<TextBox>("ColumnRotationBox");
        _keyRotationBox = RequireControl<TextBox>("KeyRotationBox");
        _autocorrectBlacklistBox = RequireControl<TextBox>("AutocorrectBlacklistBox");
        _autocorrectOverridesBox = RequireControl<TextBox>("AutocorrectOverridesBox");
        _customButtonAddLeftButton = RequireControl<Button>("CustomButtonAddLeftButton");
        _customButtonAddRightButton = RequireControl<Button>("CustomButtonAddRightButton");
        _customButtonDeleteButton = RequireControl<Button>("CustomButtonDeleteButton");
        _customButtonGeometryGrid = RequireControl<Grid>("CustomButtonGeometryGrid");
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
        _keymapPrimaryCombo.ItemTemplate = KeyActionChoiceTemplate;
        _keymapHoldCombo.ItemTemplate = KeyActionChoiceTemplate;
        _gestureShortcutKeyCombo.ItemTemplate = ShortcutKeyChoiceTemplate;
        _replayTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(8)
        };
        BuildTypingTuningControls();
        BuildGestureControls();
        InitializeGestureShortcutEditor();
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

    private void BuildTypingTuningControls()
    {
        _typingTuningPanel.Children.Clear();
        _typingTuningTextBoxes.Clear();
        _typingTuningSliders.Clear();
        _typingTuningSliderValueTexts.Clear();
        _hapticsStrengthSlider = null;
        _hapticsStrengthValueText = null;

        foreach (TypingTuningTextFieldDefinition field in TypingTuningCatalog.TextFields)
        {
            Grid row = new()
            {
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch
            };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            row.Children.Add(new TextBlock
            {
                Text = field.Label,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                TextWrapping = TextWrapping.Wrap
            });

            TextBox box = new()
            {
                MinWidth = 90,
                Margin = new Thickness(8, 0, 0, 0),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch
            };
            Grid.SetColumn(box, 1);
            row.Children.Add(box);
            _typingTuningPanel.Children.Add(row);
            _typingTuningTextBoxes.Add(field.Id, box);
        }

        foreach (TypingTuningSliderFieldDefinition field in TypingTuningCatalog.SliderFields)
        {
            int linuxMaximum = GetLinuxTypingSliderMaximum(field);
            Grid row = new()
            {
                Margin = new Thickness(0, 6, 0, 0),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch
            };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            row.Children.Add(new TextBlock
            {
                Text = field.Label,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                TextWrapping = TextWrapping.Wrap
            });

            StackPanel sliderPanel = new()
            {
                Margin = new Thickness(8, 0, 0, 0),
                Spacing = 2
            };
            Grid.SetColumn(sliderPanel, 1);

            Slider slider = new()
            {
                Minimum = field.Minimum,
                Maximum = linuxMaximum,
                TickFrequency = 1,
                IsSnapToTickEnabled = true,
                Height = 22
            };
            sliderPanel.Children.Add(slider);

            Grid valuesGrid = new();
            valuesGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            valuesGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            valuesGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            valuesGrid.Children.Add(new TextBlock
            {
                Text = field.Minimum.ToString(CultureInfo.InvariantCulture),
                FontSize = 10,
                Foreground = new SolidColorBrush(Color.Parse("#6B7279")),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Left
            });
            TextBlock valueText = new()
            {
                FontSize = 10,
                Foreground = new SolidColorBrush(Color.Parse("#5A4032")),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center
            };
            Grid.SetColumn(valueText, 1);
            valuesGrid.Children.Add(valueText);
            TextBlock maxText = new()
            {
                Text = linuxMaximum.ToString(CultureInfo.InvariantCulture),
                FontSize = 10,
                Foreground = new SolidColorBrush(Color.Parse("#6B7279")),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right
            };
            Grid.SetColumn(maxText, 2);
            valuesGrid.Children.Add(maxText);
            sliderPanel.Children.Add(valuesGrid);

            row.Children.Add(sliderPanel);
            _typingTuningPanel.Children.Add(row);
            _typingTuningSliders.Add(field.Id, slider);
            _typingTuningSliderValueTexts.Add(field.Id, valueText);
        }

        _typingTuningPanel.Children.Add(BuildHapticsControl());
    }

    private Control BuildHapticsControl()
    {
        Grid row = new()
        {
            Margin = new Thickness(0, 12, 0, 0),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        row.Children.Add(new TextBlock
        {
            Text = "Haptic Strength",
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            TextWrapping = TextWrapping.Wrap
        });

        StackPanel sliderPanel = new()
        {
            Margin = new Thickness(8, 0, 0, 0),
            Spacing = 2
        };
        Grid.SetColumn(sliderPanel, 1);

        Slider slider = new()
        {
            Minimum = 0,
            Maximum = TypingTuningCatalog.HapticsAmplitudeMaximum,
            TickFrequency = 1,
            IsSnapToTickEnabled = true,
            Height = 22
        };
        sliderPanel.Children.Add(slider);

        Grid valuesGrid = new();
        valuesGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        valuesGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        valuesGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        valuesGrid.Children.Add(new TextBlock
        {
            Text = "0",
            FontSize = 10,
            Foreground = new SolidColorBrush(Color.Parse("#6B7279")),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Left
        });
        TextBlock valueText = new()
        {
            FontSize = 10,
            Foreground = new SolidColorBrush(Color.Parse("#5A4032")),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center
        };
        Grid.SetColumn(valueText, 1);
        valuesGrid.Children.Add(valueText);
        TextBlock maxText = new()
        {
            Text = TypingTuningCatalog.HapticsAmplitudeMaximum.ToString(CultureInfo.InvariantCulture),
            FontSize = 10,
            Foreground = new SolidColorBrush(Color.Parse("#6B7279")),
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right
        };
        Grid.SetColumn(maxText, 2);
        valuesGrid.Children.Add(maxText);
        sliderPanel.Children.Add(valuesGrid);

        TextBlock note = new()
        {
            Margin = new Thickness(0, 4, 0, 0),
            Text = TypingTuningCatalog.HapticsPlatformNote,
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Foreground = new SolidColorBrush(Color.Parse("#6C757D"))
        };
        sliderPanel.Children.Add(note);

        row.Children.Add(sliderPanel);
        _hapticsStrengthSlider = slider;
        _hapticsStrengthValueText = valueText;
        return row;
    }

    private void BuildGestureControls()
    {
        _gestureSectionsPanel.Children.Clear();
        _gestureActionCombos.Clear();

        foreach (GestureSectionDefinition section in GestureBindingCatalog.Sections)
        {
            Expander expander = new()
            {
                IsExpanded = section.IsExpandedByDefault,
                Margin = new Thickness(0, 0, 0, 0),
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch,
                HorizontalContentAlignment = Avalonia.Layout.HorizontalAlignment.Stretch,
                Header = BuildGestureSectionHeader(section)
            };

            StackPanel sectionPanel = new()
            {
                Margin = new Thickness(0, 6, 0, 0),
                Spacing = 6,
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch
            };

            foreach (GestureBindingDefinition binding in GestureBindingCatalog.EnumerateSectionBindings(section.Id))
            {
                Grid row = new()
                {
                    Margin = new Thickness(0, 6, 0, 0),
                    HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch
                };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                row.Children.Add(new TextBlock
                {
                    Text = binding.Label,
                    VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
                });

                ComboBox combo = CreateGestureActionCombo();
                Grid.SetColumn(combo, 1);
                combo.Margin = new Thickness(12, 0, 0, 0);
                row.Children.Add(combo);
                sectionPanel.Children.Add(row);
                _gestureActionCombos.Add(binding.Id, combo);
            }

            expander.Content = sectionPanel;
            _gestureSectionsPanel.Children.Add(expander);
        }
    }

    private static Control BuildGestureSectionHeader(GestureSectionDefinition section)
    {
        (string backgroundHex, string borderHex, string foregroundHex) = section.Id switch
        {
            "holds" => ("#1A8FB6CF", "#2F4251", "#8FB6CF"),
            "swipes" => ("#1A86C9A9", "#2E4E43", "#86C9A9"),
            "triangles" => ("#1AD8B37A", "#5A4A2E", "#D8B37A"),
            "clicks" => ("#1AB7A3D9", "#4A3E62", "#B7A3D9"),
            "force_clicks" => ("#1AD49A9A", "#5E3D3D", "#D49A9A"),
            _ => ("#1A8B949E", "#2B2F33", "#8B949E")
        };

        return new Border
        {
            Margin = new Thickness(10, 0, 0, 0),
            Padding = new Thickness(8, 2),
            CornerRadius = new CornerRadius(6),
            Background = new SolidColorBrush(Color.Parse(backgroundHex)),
            BorderBrush = new SolidColorBrush(Color.Parse(borderHex)),
            BorderThickness = new Thickness(1),
            Child = new TextBlock
            {
                Text = section.Title,
                Foreground = new SolidColorBrush(Color.Parse(foregroundHex)),
                FontSize = 12,
                FontWeight = FontWeight.SemiBold
            }
        };
    }

    private ComboBox CreateGestureActionCombo()
    {
        return new ComboBox
        {
            HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch,
            MaxDropDownHeight = 420,
            ItemsSource = _keyActionChoices,
            ItemTemplate = KeyActionChoiceTemplate
        };
    }

    private void WireEvents()
    {
        RequireControl<Button>("RefreshDevicesButton").Click += OnRefreshDevicesClick;
        RequireControl<Button>("ImportSettingsButton").Click += OnImportSettingsClick;
        RequireControl<Button>("ExportSettingsButton").Click += OnExportSettingsClick;
        _leftDeviceCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
        _rightDeviceCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
        _layoutPresetCombo.SelectionChanged += OnLiveSettingsSelectionChanged;
        _columnLayoutColumnCombo.SelectionChanged += OnColumnLayoutSelectionChanged;
        foreach (ComboBox combo in _gestureActionCombos.Values)
        {
            combo.SelectionChanged += OnLiveSettingsSelectionChanged;
        }
        _shortcutTargetPrimaryRadio.IsCheckedChanged += OnGestureShortcutToggleChanged;
        _shortcutTargetHoldRadio.IsCheckedChanged += OnGestureShortcutToggleChanged;
        _gestureShortcutCtrlToggle.IsCheckedChanged += OnGestureShortcutToggleChanged;
        _gestureShortcutShiftToggle.IsCheckedChanged += OnGestureShortcutToggleChanged;
        _gestureShortcutAltToggle.IsCheckedChanged += OnGestureShortcutToggleChanged;
        _gestureShortcutWinToggle.IsCheckedChanged += OnGestureShortcutToggleChanged;
        _gestureShortcutKeyCombo.SelectionChanged += OnGestureShortcutKeySelectionChanged;
        _appLauncherFileBox.TextChanged += OnAppLauncherEditorChanged;
        _appLauncherBrowseButton.Click += OnAppLauncherBrowseClick;
        _gestureShortcutApplyButton.Click += OnGestureShortcutApplyClick;
        _keyboardModeCheck.IsCheckedChanged += OnModeToggleChanged;
        _runAtStartupCheck.IsCheckedChanged += OnModeToggleChanged;
        _startInTrayOnLaunchCheck.IsCheckedChanged += OnModeToggleChanged;
        _snapRadiusModeCheck.IsCheckedChanged += OnModeToggleChanged;
        _holdRepeatModeCheck.IsCheckedChanged += OnModeToggleChanged;
        _threeFingerDragModeCheck.IsCheckedChanged += OnModeToggleChanged;
        _autocorrectModeCheck.IsCheckedChanged += OnModeToggleChanged;
        _autocorrectBlacklistBox.LostFocus += OnAutocorrectTextCommitted;
        _autocorrectOverridesBox.LostFocus += OnAutocorrectTextCommitted;
        foreach (TextBox box in _typingTuningTextBoxes.Values)
        {
            box.LostFocus += OnTypingTuningCommitted;
            box.KeyDown += OnTypingTuningKeyDown;
        }
        foreach (Slider slider in _typingTuningSliders.Values)
        {
            slider.PropertyChanged += OnTypingTuningSliderPropertyChanged;
        }
        if (_hapticsStrengthSlider != null)
        {
            _hapticsStrengthSlider.PropertyChanged += OnTypingTuningSliderPropertyChanged;
        }
        _columnScaleBox.LostFocus += OnColumnLayoutCommitted;
        _keyPaddingBox.LostFocus += OnColumnLayoutCommitted;
        _columnOffsetXBox.LostFocus += OnColumnLayoutCommitted;
        _columnOffsetYBox.LostFocus += OnColumnLayoutCommitted;
        _columnRotationBox.LostFocus += OnColumnLayoutCommitted;
        _columnScaleBox.KeyDown += OnColumnLayoutKeyDown;
        _keyPaddingBox.KeyDown += OnColumnLayoutKeyDown;
        _columnOffsetXBox.KeyDown += OnColumnLayoutKeyDown;
        _columnOffsetYBox.KeyDown += OnColumnLayoutKeyDown;
        _columnRotationBox.KeyDown += OnColumnLayoutKeyDown;
        _columnAutoSplayButton.Click += OnColumnAutoSplayClick;
        _columnEvenSpaceButton.Click += OnColumnEvenSpaceClick;
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
        DeviceChoice noneChoice = deviceChoices[0];
        _leftDeviceCombo.ItemsSource = deviceChoices;
        _rightDeviceCombo.ItemsSource = deviceChoices;
        _leftDeviceCombo.SelectedItem = SelectDeviceChoice(deviceChoices, settings.LeftTrackpadStableId) ?? noneChoice;
        _rightDeviceCombo.SelectedItem = SelectDeviceChoice(deviceChoices, settings.RightTrackpadStableId) ?? noneChoice;

        List<PresetChoice> presetChoices = BuildPresetChoices();
        _layoutPresetCombo.ItemsSource = presetChoices;
        _layoutPresetCombo.SelectedItem = SelectPresetChoice(presetChoices, settings.LayoutPresetName) ?? presetChoices[0];
        UserSettings profile = settings.GetSharedProfile();
        ApplyModeToggleControls(profile);
        ApplyTypingTuningControls(profile);

        RenderKeymapPreview(configuration);
        RefreshColumnLayoutEditor();
        ReloadKeymapActionChoices(configuration.Keymap, GestureBindingCatalog.EnumerateConfiguredActions(profile));
        ApplyGestureSelections(profile);
        int fallbackLayer = Math.Clamp(profile.ActiveLayer, 0, MaxSupportedLayer);
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

    private async void OnLiveSettingsSelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_loadingScreen || _suppressKeymapEditorEvents)
        {
            return;
        }

        await SaveLiveSettingsAsync();
    }

    private async void OnModeToggleChanged(object? sender, RoutedEventArgs e)
    {
        if (_loadingScreen)
        {
            return;
        }

        UpdateAutocorrectStatusVisibility();
        UpdateThreeFingerSwipeGestureAvailability();
        await SaveLiveSettingsAsync();
    }

    private async void OnAutocorrectTextCommitted(object? sender, RoutedEventArgs e)
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
        settings.SharedProfile ??= UserSettings.LoadBundledDefaultsOrDefault();
        settings.LeftTrackpadStableId = (_leftDeviceCombo.SelectedItem as DeviceChoice)?.StableId;
        settings.RightTrackpadStableId = (_rightDeviceCombo.SelectedItem as DeviceChoice)?.StableId;
        settings.LayoutPresetName = (_layoutPresetCombo.SelectedItem as PresetChoice)?.Name ?? TrackpadLayoutPreset.SixByThree.Name;
        settings.SharedProfile.LayoutPresetName = settings.LayoutPresetName;
        ApplyGestureSettingsFromUi(settings.SharedProfile);
        ApplyTypingTuningSettingsFromUi(settings.SharedProfile);
        settings.SharedProfile.KeyboardModeEnabled = _keyboardModeCheck.IsChecked == true;
        settings.SharedProfile.AutocorrectEnabled = _autocorrectModeCheck.IsChecked == true;
        settings.SharedProfile.AutocorrectDryRunEnabled = false;
        settings.SharedProfile.AutocorrectMaxEditDistance = 2;
        settings.SharedProfile.AutocorrectBlacklistCsv = NormalizeMultilineText(_autocorrectBlacklistBox.Text);
        settings.SharedProfile.AutocorrectOverridesCsv = NormalizeMultilineText(_autocorrectOverridesBox.Text);
        settings.SharedProfile.SnapRadiusPercent = _snapRadiusModeCheck.IsChecked == true
            ? RuntimeConfigurationFactory.HardcodedSnapRadiusPercent
            : 0.0;
        settings.SharedProfile.HoldRepeatEnabled = _holdRepeatModeCheck.IsChecked == true;
        settings.SharedProfile.ThreeFingerDragEnabled = _threeFingerDragModeCheck.IsChecked == true;
        settings.SharedProfile.StartInTrayOnLaunch = _startInTrayOnLaunchCheck.IsChecked == true;

        bool startupRequested = _runAtStartupCheck.IsChecked == true;
        bool startupEnabled = LinuxStartupRegistration.IsEnabled();
        if (startupRequested != startupEnabled &&
            !LinuxStartupRegistration.TrySetEnabled(startupRequested, out string? startupError))
        {
            ShowNoticeDialog(
                "Startup Registration",
                $"Failed to update Linux startup registration.\n{startupError}");
            LoadScreen();
            _settingsApplyPending = false;
            return Task.CompletedTask;
        }

        settings.SharedProfile.RunAtStartup = startupRequested;
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

    private void ApplyModeToggleControls(UserSettings profile)
    {
        _keyboardModeCheck.IsChecked = profile.KeyboardModeEnabled;
        _autocorrectModeCheck.IsChecked = profile.AutocorrectEnabled;
        _autocorrectBlacklistBox.Text = profile.AutocorrectBlacklistCsv ?? string.Empty;
        _autocorrectOverridesBox.Text = profile.AutocorrectOverridesCsv ?? string.Empty;
        _snapRadiusModeCheck.IsChecked = profile.SnapRadiusPercent > 0.0;
        _holdRepeatModeCheck.IsChecked = profile.HoldRepeatEnabled;
        _threeFingerDragModeCheck.IsChecked = profile.ThreeFingerDragEnabled;
        UpdateThreeFingerSwipeGestureAvailability();
        _startInTrayOnLaunchCheck.IsChecked = profile.StartInTrayOnLaunch;
        bool startupEnabled = LinuxStartupRegistration.IsEnabled();
        profile.RunAtStartup = startupEnabled;
        _runAtStartupCheck.IsChecked = startupEnabled;
        UpdateAutocorrectStatusVisibility();
        UpdateAutocorrectStatusDetails();
    }

    private void UpdateThreeFingerSwipeGestureAvailability()
    {
        bool enableThreeFingerSwipes = _threeFingerDragModeCheck.IsChecked != true;
        SetGestureActionComboEnabled("three_finger_swipe_left", enableThreeFingerSwipes);
        SetGestureActionComboEnabled("three_finger_swipe_right", enableThreeFingerSwipes);
        SetGestureActionComboEnabled("three_finger_swipe_up", enableThreeFingerSwipes);
        SetGestureActionComboEnabled("three_finger_swipe_down", enableThreeFingerSwipes);
    }

    private void SetGestureActionComboEnabled(string bindingId, bool isEnabled)
    {
        if (_gestureActionCombos.TryGetValue(bindingId, out ComboBox? combo))
        {
            combo.IsEnabled = isEnabled;
        }
    }

    private void ApplyTypingTuningControls(UserSettings profile)
    {
        foreach (TypingTuningTextFieldDefinition field in TypingTuningCatalog.TextFields)
        {
            if (_typingTuningTextBoxes.TryGetValue(field.Id, out TextBox? box))
            {
                box.Text = FormatNumber(TypingTuningCatalog.GetTextValue(profile, field));
            }
        }

        foreach (TypingTuningSliderFieldDefinition field in TypingTuningCatalog.SliderFields)
        {
            if (_typingTuningSliders.TryGetValue(field.Id, out Slider? slider))
            {
                slider.Value = ClampLinuxTypingSliderValue(field, TypingTuningCatalog.GetSliderValue(profile, field));
            }
        }

        if (_hapticsStrengthSlider != null)
        {
            _hapticsStrengthSlider.Value = TypingTuningCatalog.GetHapticsAmplitude(profile);
        }

        UpdateTypingTuningSliderLabels();
    }

    private void ApplyTypingTuningSettingsFromUi(UserSettings profile)
    {
        foreach (TypingTuningTextFieldDefinition field in TypingTuningCatalog.TextFields)
        {
            if (_typingTuningTextBoxes.TryGetValue(field.Id, out TextBox? box))
            {
                double fallback = TypingTuningCatalog.GetTextValue(profile, field);
                TypingTuningCatalog.SetTextValue(profile, field, ReadDouble(box, fallback));
            }
        }

        foreach (TypingTuningSliderFieldDefinition field in TypingTuningCatalog.SliderFields)
        {
            if (_typingTuningSliders.TryGetValue(field.Id, out Slider? slider))
            {
                int value = ClampLinuxTypingSliderValue(field, (int)Math.Round(slider.Value));
                TypingTuningCatalog.SetSliderValue(profile, field, value);
            }
        }

        if (_hapticsStrengthSlider != null)
        {
            int amplitude = (int)Math.Clamp(
                Math.Round(_hapticsStrengthSlider.Value),
                0,
                TypingTuningCatalog.HapticsAmplitudeMaximum);
            TypingTuningCatalog.SetHapticsAmplitude(profile, amplitude);
        }

        UpdateTypingTuningSliderLabels();
    }

    private void UpdateTypingTuningSliderLabels()
    {
        foreach (TypingTuningSliderFieldDefinition field in TypingTuningCatalog.SliderFields)
        {
            if (_typingTuningSliders.TryGetValue(field.Id, out Slider? slider) &&
                _typingTuningSliderValueTexts.TryGetValue(field.Id, out TextBlock? text))
            {
                int value = ClampLinuxTypingSliderValue(field, (int)Math.Round(slider.Value));
                text.Text = value.ToString(CultureInfo.InvariantCulture);
            }
        }

        if (_hapticsStrengthSlider != null && _hapticsStrengthValueText != null)
        {
            int amplitude = (int)Math.Clamp(
                Math.Round(_hapticsStrengthSlider.Value),
                0,
                TypingTuningCatalog.HapticsAmplitudeMaximum);
            _hapticsStrengthValueText.Text = amplitude.ToString(CultureInfo.InvariantCulture);
        }
    }

    private async void OnTypingTuningCommitted(object? sender, RoutedEventArgs e)
    {
        if (_loadingScreen)
        {
            return;
        }

        await SaveLiveSettingsAsync();
    }

    private static int GetLinuxTypingSliderMaximum(TypingTuningSliderFieldDefinition field)
    {
        if (string.Equals(field.Id, "force_min", StringComparison.Ordinal) ||
            string.Equals(field.Id, "force_cap", StringComparison.Ordinal))
        {
            return Math.Min(field.Maximum, LinuxForceSliderMaximum);
        }

        return field.Maximum;
    }

    private static int ClampLinuxTypingSliderValue(TypingTuningSliderFieldDefinition field, int value)
    {
        return Math.Clamp(value, field.Minimum, GetLinuxTypingSliderMaximum(field));
    }

    private async void OnTypingTuningKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || _loadingScreen)
        {
            return;
        }

        await SaveLiveSettingsAsync();
        e.Handled = true;
    }

    private async void OnTypingTuningSliderPropertyChanged(object? sender, AvaloniaPropertyChangedEventArgs e)
    {
        if (e.Property != RangeBase.ValueProperty)
        {
            return;
        }

        UpdateTypingTuningSliderLabels();
        if (_loadingScreen)
        {
            return;
        }

        await SaveLiveSettingsAsync();
    }

    private void ApplyGestureSelections(UserSettings profile)
    {
        foreach (GestureBindingDefinition binding in GestureBindingCatalog.All)
        {
            if (_gestureActionCombos.TryGetValue(binding.Id, out ComboBox? combo))
            {
                SetActionComboSelection(combo, GestureBindingCatalog.GetAction(profile, binding));
            }
        }

        RefreshGestureShortcutEditorUi();
    }

    private void ApplyGestureSettingsFromUi(UserSettings profile)
    {
        foreach (GestureBindingDefinition binding in GestureBindingCatalog.All)
        {
            if (!_gestureActionCombos.TryGetValue(binding.Id, out ComboBox? combo))
            {
                continue;
            }

            string action = ReadActionSelection(combo, binding.DefaultAction);
            GestureBindingCatalog.SetAction(profile, binding, action);
            EnsureActionChoice(action);
        }
    }

    private void InitializeGestureShortcutEditor()
    {
        _gestureShortcutKeyCombo.ItemsSource = _shortcutKeyChoices;
        _shortcutTargetPrimaryRadio.IsChecked = true;
        RefreshGestureShortcutEditorUi();
    }

    private void RefreshGestureShortcutEditorUi()
    {
        _suppressGestureShortcutEditorEvents = true;
        _suppressAppLauncherEditorEvents = true;
        try
        {
            if (!HasKeymapSelection())
            {
                ClearGestureShortcutEditorState();
                _appLauncherFileBox.Text = string.Empty;
            }
            else
            {
                string selectedAction = ReadActionSelection(GetShortcutTargetCombo(), "None");
                if (AppLaunchActionHelper.TryParse(selectedAction, out AppLaunchActionSpec spec))
                {
                    ClearGestureShortcutEditorState();
                    _appLauncherFileBox.Text = spec.FileName;
                }
                else if (DispatchShortcutHelper.TryReadShortcut(selectedAction, out DispatchModifierFlags modifiers, out string keyLabel))
                {
                    _appLauncherFileBox.Text = string.Empty;
                    _gestureShortcutCtrlToggle.IsChecked = (modifiers & (
                        DispatchModifierFlags.Ctrl |
                        DispatchModifierFlags.LeftCtrl |
                        DispatchModifierFlags.RightCtrl)) != 0;
                    _gestureShortcutShiftToggle.IsChecked = (modifiers & (
                        DispatchModifierFlags.Shift |
                        DispatchModifierFlags.LeftShift |
                        DispatchModifierFlags.RightShift)) != 0;
                    _gestureShortcutAltToggle.IsChecked = (modifiers & (
                        DispatchModifierFlags.Alt |
                        DispatchModifierFlags.LeftAlt |
                        DispatchModifierFlags.RightAlt)) != 0;
                    _gestureShortcutWinToggle.IsChecked = (modifiers & (
                        DispatchModifierFlags.Meta |
                        DispatchModifierFlags.LeftMeta |
                        DispatchModifierFlags.RightMeta)) != 0;
                    _gestureShortcutKeyCombo.SelectedItem = SelectShortcutKeyChoice(_shortcutKeyChoices, keyLabel);
                }
                else
                {
                    ClearGestureShortcutEditorState();
                    _appLauncherFileBox.Text = string.Empty;
                }
            }
        }
        finally
        {
            _suppressGestureShortcutEditorEvents = false;
            _suppressAppLauncherEditorEvents = false;
        }

        UpdateActionBuilderPreview();
    }

    private void OnGestureShortcutToggleChanged(object? sender, RoutedEventArgs e)
    {
        if (_suppressGestureShortcutEditorEvents)
        {
            return;
        }

        ClearAppLauncherEditorState();
        UpdateActionBuilderPreview();
    }

    private void OnGestureShortcutKeySelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_suppressGestureShortcutEditorEvents)
        {
            return;
        }

        if (_gestureShortcutKeyCombo.SelectedItem is ShortcutKeyChoice { IsSeparator: true })
        {
            _suppressGestureShortcutEditorEvents = true;
            try
            {
                _gestureShortcutKeyCombo.SelectedItem = null;
            }
            finally
            {
                _suppressGestureShortcutEditorEvents = false;
            }

            UpdateActionBuilderPreview();
            return;
        }

        ClearAppLauncherEditorState();
        UpdateActionBuilderPreview();
    }

    private void UpdateActionBuilderPreview()
    {
        string action = BuildActionBuilderAction(out string preview);
        _gestureShortcutPreviewText.Text = preview;
        _gestureShortcutApplyButton.IsEnabled = HasKeymapSelection() && !string.IsNullOrEmpty(action);
    }

    private string BuildGestureShortcutAction()
    {
        if (_gestureShortcutKeyCombo.SelectedItem is not ShortcutKeyChoice selectedChoice ||
            selectedChoice.IsSeparator ||
            !DispatchShortcutHelper.TryNormalizeShortcutKeyLabel(selectedChoice.Value, out string keyLabel))
        {
            return string.Empty;
        }

        DispatchModifierFlags modifiers = DispatchModifierFlags.None;
        if (_gestureShortcutCtrlToggle.IsChecked == true)
        {
            modifiers |= DispatchModifierFlags.Ctrl;
        }

        if (_gestureShortcutShiftToggle.IsChecked == true)
        {
            modifiers |= DispatchModifierFlags.Shift;
        }

        if (_gestureShortcutAltToggle.IsChecked == true)
        {
            modifiers |= DispatchModifierFlags.Alt;
        }

        if (_gestureShortcutWinToggle.IsChecked == true)
        {
            modifiers |= DispatchModifierFlags.Meta;
        }

        return modifiers == DispatchModifierFlags.None
            ? string.Empty
            : DispatchShortcutHelper.FormatShortcut(modifiers, keyLabel);
    }

    private string BuildActionBuilderAction(out string preview)
    {
        string appAction = BuildAppLauncherAction();
        if (!string.IsNullOrEmpty(appAction))
        {
            preview = AppLaunchActionHelper.GetDisplayLabel(appAction);
            return appAction;
        }

        string shortcut = BuildGestureShortcutAction();
        if (!string.IsNullOrEmpty(shortcut))
        {
            preview = $"Shortcut: {shortcut}";
            return shortcut;
        }

        preview = "Shortcut: none";
        return string.Empty;
    }

    private void OnGestureShortcutApplyClick(object? sender, RoutedEventArgs e)
    {
        string action = BuildActionBuilderAction(out string preview);
        if (!HasKeymapSelection() || string.IsNullOrEmpty(action))
        {
            _gestureShortcutPreviewText.Text = preview;
            return;
        }

        if (EnsureActionChoice(action))
        {
            RefreshActionChoiceBindings();
        }

        SetActionComboSelection(GetShortcutTargetCombo(), action);
        RefreshGestureShortcutEditorUi();
    }

    private ComboBox GetShortcutTargetCombo()
    {
        return _shortcutTargetHoldRadio.IsChecked == true
            ? _keymapHoldCombo
            : _keymapPrimaryCombo;
    }

    private void ClearGestureShortcutEditorState()
    {
        _gestureShortcutCtrlToggle.IsChecked = false;
        _gestureShortcutShiftToggle.IsChecked = false;
        _gestureShortcutAltToggle.IsChecked = false;
        _gestureShortcutWinToggle.IsChecked = false;
        _gestureShortcutKeyCombo.SelectedItem = null;
    }

    private void OnAppLauncherEditorChanged(object? sender, TextChangedEventArgs e)
    {
        if (_suppressAppLauncherEditorEvents)
        {
            return;
        }

        if (!string.IsNullOrWhiteSpace(_appLauncherFileBox.Text))
        {
            _suppressGestureShortcutEditorEvents = true;
            try
            {
                ClearGestureShortcutEditorState();
            }
            finally
            {
                _suppressGestureShortcutEditorEvents = false;
            }
        }

        UpdateActionBuilderPreview();
    }

    private async void OnAppLauncherBrowseClick(object? sender, RoutedEventArgs e)
    {
        if (!StorageProvider.CanOpen)
        {
            ShowNoticeDialog(
                "Browse Unavailable",
                "This Linux GUI session cannot open a file picker on the current platform backend.");
            return;
        }

        IReadOnlyList<IStorageFile> files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Select application, desktop entry, or script",
            AllowMultiple = false,
            FileTypeFilter =
            [
                new FilePickerFileType("Applications") { Patterns = ["*.desktop"] },
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
                "Browse Failed",
                "The selected item could not be resolved to a local file path.");
            return;
        }

        _appLauncherFileBox.Text = localPath;
    }

    private void ClearAppLauncherEditorState()
    {
        _suppressAppLauncherEditorEvents = true;
        try
        {
            _appLauncherFileBox.Text = string.Empty;
        }
        finally
        {
            _suppressAppLauncherEditorEvents = false;
        }
    }

    private string BuildAppLauncherAction()
    {
        string fileName = _appLauncherFileBox.Text?.Trim() ?? string.Empty;
        if (fileName.Length == 0)
        {
            return string.Empty;
        }

        return AppLaunchActionHelper.CreateActionLabel(fileName);
    }

    private bool HasKeymapSelection()
    {
        return TryGetSelectedCustomButton(out _, out _) ||
               TryGetSelectedKeyPosition(out _, out _, out _);
    }

    private TrackpadLayoutPreset GetSelectedPreset()
    {
        return (_layoutPresetCombo.SelectedItem as PresetChoice)?.Name is string name
            ? TrackpadLayoutPreset.ResolveByNameOrDefault(name)
            : TrackpadLayoutPreset.SixByThree;
    }

    private void OnColumnLayoutSelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (_loadingScreen || _suppressColumnLayoutEvents)
        {
            return;
        }

        RefreshColumnLayoutFields();
    }

    private void OnColumnLayoutCommitted(object? sender, RoutedEventArgs e)
    {
        if (_loadingScreen || _suppressColumnLayoutEvents || IsReplayMode)
        {
            return;
        }

        SaveColumnLayoutEdits();
    }

    private void OnColumnLayoutKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || _loadingScreen || _suppressColumnLayoutEvents || IsReplayMode)
        {
            return;
        }

        SaveColumnLayoutEdits();
        e.Handled = true;
    }

    private void OnColumnAutoSplayClick(object? sender, RoutedEventArgs e)
    {
        if (IsReplayMode)
        {
            return;
        }

        TrackpadLayoutPreset preset = GetSelectedPreset();
        if (!preset.AllowsColumnSettings || !ColumnLayoutTuning.IsAutoSplaySupported(preset))
        {
            ShowNoticeDialog("Auto Splay", "Auto Splay currently supports 6-column layouts plus 5x3 and 5x4.");
            return;
        }

        if (!TryCaptureAutoSplayTouches(out ColumnAutoSplayTouch[] touches, out string captureError))
        {
            ShowNoticeDialog("Auto Splay", captureError);
            return;
        }

        if (!ColumnLayoutTuning.TryApplyAutoSplay(preset, _rightRenderedLayout, _columnSettings, touches, out string applyError))
        {
            ShowNoticeDialog("Auto Splay", applyError);
            return;
        }

        SaveColumnLayoutStateToSettings();
    }

    private void OnColumnEvenSpaceClick(object? sender, RoutedEventArgs e)
    {
        if (IsReplayMode)
        {
            return;
        }

        TrackpadLayoutPreset preset = GetSelectedPreset();
        if (!ColumnLayoutTuning.TryApplyEvenColumnSpacing(preset, _rightRenderedLayout, _columnSettings, out string error))
        {
            ShowNoticeDialog("Even Space", error);
            return;
        }

        SaveColumnLayoutStateToSettings();
    }

    private void RefreshColumnLayoutEditor()
    {
        TrackpadLayoutPreset preset = GetSelectedPreset();
        LinuxHostSettings settings = _runtime.LoadSettings();
        UserSettings profile = settings.GetSharedProfile();
        double keyPadding = RuntimeConfigurationFactory.GetKeyPaddingPercentForPreset(profile, preset);
        bool allowsColumnSettings = preset.AllowsColumnSettings && !IsReplayMode;

        _suppressColumnLayoutEvents = true;
        _keyPaddingBox.IsEnabled = !IsReplayMode;
        _columnLayoutColumnCombo.IsEnabled = allowsColumnSettings;
        _columnScaleBox.IsEnabled = allowsColumnSettings;
        _columnOffsetXBox.IsEnabled = allowsColumnSettings;
        _columnOffsetYBox.IsEnabled = allowsColumnSettings;
        _columnRotationBox.IsEnabled = allowsColumnSettings;
        _columnAutoSplayButton.IsEnabled = allowsColumnSettings && ColumnLayoutTuning.IsAutoSplaySupported(preset);
        _columnEvenSpaceButton.IsEnabled = allowsColumnSettings && preset.Columns >= 3;
        _keyPaddingBox.Text = FormatNumber(keyPadding);

        int previous = _columnLayoutColumnCombo.SelectedIndex;
        List<string> columnChoices = [];
        for (int col = 0; col < preset.Columns; col++)
        {
            columnChoices.Add($"Column {col + 1}");
        }

        _columnLayoutColumnCombo.ItemsSource = columnChoices;
        if (preset.Columns > 0)
        {
            if (previous < 0 || previous >= preset.Columns)
            {
                previous = 0;
            }

            _columnLayoutColumnCombo.SelectedIndex = previous;
        }
        else
        {
            _columnLayoutColumnCombo.SelectedIndex = -1;
        }

        _suppressColumnLayoutEvents = false;
        RefreshColumnLayoutFields();
    }

    private void RefreshColumnLayoutFields()
    {
        TrackpadLayoutPreset preset = GetSelectedPreset();
        LinuxHostSettings settings = _runtime.LoadSettings();
        UserSettings profile = settings.GetSharedProfile();

        _suppressColumnLayoutEvents = true;
        _keyPaddingBox.Text = FormatNumber(RuntimeConfigurationFactory.GetKeyPaddingPercentForPreset(profile, preset));

        if (!preset.AllowsColumnSettings)
        {
            _columnScaleBox.Text = FormatNumber(preset.FixedKeyScale * 100.0);
            ToolTip.SetTip(_columnScaleBox, "Fixed layout scale.");
            _columnOffsetXBox.Text = "0";
            _columnOffsetYBox.Text = "0";
            _columnRotationBox.Text = "0";
            ToolTip.SetTip(_columnRotationBox, "Rotation range: 0° - 360°.");
            _suppressColumnLayoutEvents = false;
            return;
        }

        int col = _columnLayoutColumnCombo.SelectedIndex;
        if (col < 0 || col >= _columnSettings.Length)
        {
            _columnScaleBox.Text = "100";
            ToolTip.SetTip(_columnScaleBox, null);
            _columnOffsetXBox.Text = "0";
            _columnOffsetYBox.Text = "0";
            _columnRotationBox.Text = "0";
            ToolTip.SetTip(_columnRotationBox, "Rotation range: 0° - 360°.");
            _suppressColumnLayoutEvents = false;
            return;
        }

        double maxScale = RuntimeConfigurationFactory.GetMaxColumnScaleForPreset(preset);
        ColumnLayoutSettings column = _columnSettings[col];
        _columnScaleBox.Text = FormatNumber(column.Scale * 100.0);
        ToolTip.SetTip(
            _columnScaleBox,
            $"Scale range: {FormatNumber(RuntimeConfigurationFactory.MinColumnScale * 100.0)}% - {FormatNumber(maxScale * 100.0)}% (based on Magic Trackpad 2 dimensions 160.0mm x 114.9mm).");
        _columnOffsetXBox.Text = FormatNumber(column.OffsetXPercent);
        _columnOffsetYBox.Text = FormatNumber(column.OffsetYPercent);
        _columnRotationBox.Text = FormatNumber(column.RotationDegrees);
        ToolTip.SetTip(_columnRotationBox, "Rotation range: 0° - 360°.");
        _suppressColumnLayoutEvents = false;
    }

    private void SaveColumnLayoutEdits()
    {
        TrackpadLayoutPreset preset = GetSelectedPreset();
        LinuxHostSettings settings = _runtime.LoadSettings();
        settings.LayoutPresetName = preset.Name;
        settings.SharedProfile ??= UserSettings.LoadBundledDefaultsOrDefault();
        settings.SharedProfile.LayoutPresetName = preset.Name;

        if (!ApplyColumnLayoutFromUi(settings.SharedProfile, preset))
        {
            RefreshColumnLayoutFields();
            return;
        }

        SaveColumnLayoutStateToSettings(settings, preset);
    }

    private bool ApplyColumnLayoutFromUi(UserSettings profile, TrackpadLayoutPreset preset)
    {
        bool changed = false;
        double previousPadding = RuntimeConfigurationFactory.GetKeyPaddingPercentForPreset(profile, preset);
        double nextPadding = Math.Clamp(ReadDouble(_keyPaddingBox, previousPadding), 0.0, 90.0);
        if (Math.Abs(nextPadding - previousPadding) > 0.00001)
        {
            RuntimeConfigurationFactory.SaveKeyPaddingForPreset(profile, preset, nextPadding);
            changed = true;
        }

        _keyPaddingBox.Text = FormatNumber(RuntimeConfigurationFactory.GetKeyPaddingPercentForPreset(profile, preset));

        if (!preset.AllowsColumnSettings)
        {
            return changed;
        }

        int selectedColumn = _columnLayoutColumnCombo.SelectedIndex;
        if (selectedColumn < 0 || selectedColumn >= _columnSettings.Length)
        {
            return changed;
        }

        ColumnLayoutSettings target = _columnSettings[selectedColumn];
        double maxScale = RuntimeConfigurationFactory.GetMaxColumnScaleForPreset(preset);
        double nextScalePercent = ReadDouble(_columnScaleBox, target.Scale * 100.0);
        double nextScale = Math.Clamp(nextScalePercent / 100.0, RuntimeConfigurationFactory.MinColumnScale, maxScale);
        double nextOffsetX = ReadDouble(_columnOffsetXBox, target.OffsetXPercent);
        double nextOffsetY = ReadDouble(_columnOffsetYBox, target.OffsetYPercent);
        double nextRotation = Math.Clamp(ReadDouble(_columnRotationBox, target.RotationDegrees), 0.0, 360.0);

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

        if (Math.Abs(nextRotation - target.RotationDegrees) > 0.00001)
        {
            target.RotationDegrees = nextRotation;
            changed = true;
        }

        _columnScaleBox.Text = FormatNumber(target.Scale * 100.0);
        _columnOffsetXBox.Text = FormatNumber(target.OffsetXPercent);
        _columnOffsetYBox.Text = FormatNumber(target.OffsetYPercent);
        _columnRotationBox.Text = FormatNumber(target.RotationDegrees);
        return changed;
    }

    private void SaveColumnLayoutStateToSettings()
    {
        SaveColumnLayoutStateToSettings(_runtime.LoadSettings(), GetSelectedPreset());
    }

    private void SaveColumnLayoutStateToSettings(LinuxHostSettings settings, TrackpadLayoutPreset preset)
    {
        settings.LayoutPresetName = preset.Name;
        settings.SharedProfile ??= UserSettings.LoadBundledDefaultsOrDefault();
        settings.SharedProfile.LayoutPresetName = preset.Name;
        RuntimeConfigurationFactory.SaveColumnSettingsForPreset(settings.SharedProfile, preset, _columnSettings);
        settings.Normalize();
        _runtime.SaveSettings(settings);
        RenderLayoutsFromCurrentKeymap();
        EnsureSelectedKeyStillValid();
        RefreshColumnLayoutEditor();
        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);
    }

    private bool TryCaptureAutoSplayTouches(out ColumnAutoSplayTouch[] touches, out string error)
    {
        touches = Array.Empty<ColumnAutoSplayTouch>();
        LinuxInputPreviewTrackpadState? left = FindPreviewTrackpadState(TrackpadSide.Left);
        LinuxInputPreviewTrackpadState? right = FindPreviewTrackpadState(TrackpadSide.Right);

        Span<ColumnAutoSplayTouch> leftTouches = stackalloc ColumnAutoSplayTouch[InputFrame.MaxContacts];
        Span<ColumnAutoSplayTouch> rightTouches = stackalloc ColumnAutoSplayTouch[InputFrame.MaxContacts];
        int leftCount = SnapshotAutoSplayTouches(left, leftTouches);
        int rightCount = SnapshotAutoSplayTouches(right, rightTouches);

        bool leftReady = leftCount >= ColumnLayoutTuning.AutoSplayTouchCount;
        bool rightReady = rightCount >= ColumnLayoutTuning.AutoSplayTouchCount;
        if (leftReady && rightReady)
        {
            error = "Detected 4+ touches on both sides. Keep touches on only one side and retry.";
            return false;
        }

        if (!leftReady && !rightReady)
        {
            error = leftCount == 0 && rightCount == 0
                ? "Place at least 4 fingertips on one side, then click Auto Splay."
                : $"Auto Splay needs at least 4 touches on one side (left: {leftCount}, right: {rightCount}).";
            return false;
        }

        TrackpadSide sourceSide = leftReady ? TrackpadSide.Left : TrackpadSide.Right;
        Span<ColumnAutoSplayTouch> source = leftReady ? leftTouches : rightTouches;
        int sourceCount = leftReady ? leftCount : rightCount;
        int skipIndex = IndexOfLowestAutoSplayTouch(source, sourceCount);
        touches = new ColumnAutoSplayTouch[ColumnLayoutTuning.AutoSplayTouchCount];
        for (int i = 0, written = 0; i < sourceCount && written < ColumnLayoutTuning.AutoSplayTouchCount; i++)
        {
            if (i == skipIndex)
            {
                continue;
            }

            ColumnAutoSplayTouch touch = source[i];
            double canonicalX = sourceSide == TrackpadSide.Left ? 1.0 - touch.XNorm : touch.XNorm;
            touches[written++] = new ColumnAutoSplayTouch(canonicalX, touch.YNorm);
        }

        Array.Sort(touches, static (a, b) =>
        {
            int byX = a.XNorm.CompareTo(b.XNorm);
            return byX != 0 ? byX : a.YNorm.CompareTo(b.YNorm);
        });

        error = string.Empty;
        return true;
    }

    private static int IndexOfLowestAutoSplayTouch(Span<ColumnAutoSplayTouch> touches, int count)
    {
        if (count <= ColumnLayoutTuning.AutoSplayTouchCount)
        {
            return -1;
        }

        int index = 0;
        for (int i = 1; i < count; i++)
        {
            if (touches[i].YNorm > touches[index].YNorm)
            {
                index = i;
            }
        }

        return index;
    }

    private int SnapshotAutoSplayTouches(LinuxInputPreviewTrackpadState? state, Span<ColumnAutoSplayTouch> destination)
    {
        if (state == null || destination.Length == 0 || state.Contacts.Count == 0)
        {
            return 0;
        }

        ushort maxX = state.MaxX == 0 ? RuntimeConfigurationFactory.DefaultMaxX : state.MaxX;
        ushort maxY = state.MaxY == 0 ? RuntimeConfigurationFactory.DefaultMaxY : state.MaxY;
        int written = 0;
        for (int index = 0; index < state.Contacts.Count && written < destination.Length; index++)
        {
            LinuxInputPreviewContact contact = state.Contacts[index];
            if (!contact.TipSwitch)
            {
                continue;
            }

            destination[written++] = new ColumnAutoSplayTouch(
                Math.Clamp(contact.X / (double)maxX, 0.0, 1.0),
                Math.Clamp(contact.Y / (double)maxY, 0.0, 1.0));
        }

        return written;
    }

    private LinuxInputPreviewTrackpadState? FindPreviewTrackpadState(TrackpadSide side)
    {
        for (int index = 0; index < _previewSnapshot.Trackpads.Count; index++)
        {
            LinuxInputPreviewTrackpadState trackpad = _previewSnapshot.Trackpads[index];
            if (trackpad.Side == side)
            {
                return trackpad;
            }
        }

        return null;
    }

    private void InitializeKeymapEditorControls()
    {
        for (int index = 0; index < _keyActionChoices.Count; index++)
        {
            if (!_keyActionChoices[index].IsSeparator)
            {
                _keyActionChoiceLookup.Add(_keyActionChoices[index].Value);
            }
        }

        _keymapPrimaryCombo.ItemsSource = _keyActionChoices;
        _keymapHoldCombo.ItemsSource = _keyActionChoices;
        foreach (ComboBox combo in _gestureActionCombos.Values)
        {
            combo.ItemsSource = _keyActionChoices;
        }
        _keymapSelectionText.Text = "Selection: none";
        _keymapPrimaryCombo.IsEnabled = false;
        _keymapHoldCombo.IsEnabled = false;
        _keyRotationBox.IsEnabled = false;
        _customButtonDeleteButton.IsEnabled = false;
        SetCustomButtonGeometryEditorEnabled(false);
        ClearCustomButtonGeometryEditorValues();
    }

    private void ReloadKeymapActionChoices(KeymapStore keymap, IEnumerable<string>? additionalActions = null)
    {
        string previousPrimary = ReadSelectedActionValue(_keymapPrimaryCombo, "None");
        string previousHold = ReadSelectedActionValue(_keymapHoldCombo, "None");
        Dictionary<string, string> previousGestureActions = CaptureGestureSelections();

        List<KeyActionChoice> nextChoices = BuildKeyActionChoices();
        HashSet<string> nextLookup = new(StringComparer.OrdinalIgnoreCase);
        for (int index = 0; index < nextChoices.Count; index++)
        {
            if (!nextChoices[index].IsSeparator)
            {
                nextLookup.Add(nextChoices[index].Value);
            }
        }

        foreach (KeyValuePair<int, Dictionary<string, KeyMapping>> layer in keymap.Mappings)
        {
            foreach (KeyValuePair<string, KeyMapping> mappingEntry in layer.Value)
            {
                EnsureActionChoice(nextChoices, nextLookup, mappingEntry.Value?.Primary?.Label);
                EnsureActionChoice(nextChoices, nextLookup, mappingEntry.Value?.Hold?.Label);
            }
        }

        foreach (KeyValuePair<int, List<CustomButton>> customButtonsByLayer in keymap.CustomButtons)
        {
            for (int index = 0; index < customButtonsByLayer.Value.Count; index++)
            {
                CustomButton button = customButtonsByLayer.Value[index];
                EnsureActionChoice(nextChoices, nextLookup, button.Primary?.Label);
                EnsureActionChoice(nextChoices, nextLookup, button.Hold?.Label);
            }
        }

        if (additionalActions != null)
        {
            foreach (string action in additionalActions)
            {
                EnsureActionChoice(nextChoices, nextLookup, action);
            }
        }

        _suppressKeymapEditorEvents = true;
        _keyActionChoices = nextChoices;
        _keyActionChoiceLookup = nextLookup;
        ResetActionChoiceBindingsSource();
        SetActionComboSelection(_keymapPrimaryCombo, previousPrimary);
        SetActionComboSelection(_keymapHoldCombo, previousHold);
        RestoreGestureSelections(previousGestureActions);
        _suppressKeymapEditorEvents = false;
    }

    private void RefreshActionChoiceBindings()
    {
        string previousPrimary = ReadSelectedActionValue(_keymapPrimaryCombo, "None");
        string previousHold = ReadSelectedActionValue(_keymapHoldCombo, "None");
        Dictionary<string, string> previousGestureActions = CaptureGestureSelections();

        _suppressKeymapEditorEvents = true;
        ResetActionChoiceBindingsSource();
        SetActionComboSelection(_keymapPrimaryCombo, previousPrimary);
        SetActionComboSelection(_keymapHoldCombo, previousHold);
        RestoreGestureSelections(previousGestureActions);
        _suppressKeymapEditorEvents = false;
    }

    private void ResetActionChoiceBindingsSource()
    {
        _keymapPrimaryCombo.SelectedItem = null;
        _keymapHoldCombo.SelectedItem = null;
        _keymapPrimaryCombo.ItemsSource = null;
        _keymapHoldCombo.ItemsSource = null;
        foreach (ComboBox combo in _gestureActionCombos.Values)
        {
            combo.SelectedItem = null;
            combo.ItemsSource = null;
        }

        _keymapPrimaryCombo.ItemsSource = _keyActionChoices;
        _keymapHoldCombo.ItemsSource = _keyActionChoices;
        foreach (ComboBox combo in _gestureActionCombos.Values)
        {
            combo.ItemsSource = _keyActionChoices;
        }
    }

    private bool EnsureActionChoice(string? action)
    {
        return EnsureActionChoice(_keyActionChoices, _keyActionChoiceLookup, action);
    }

    private static bool EnsureActionChoice(
        List<KeyActionChoice> choices,
        HashSet<string> lookup,
        string? action)
    {
        if (string.IsNullOrWhiteSpace(action))
        {
            return false;
        }

        string value = action.Trim();
        if (IsUnsupportedLayerActionChoice(value))
        {
            return false;
        }

        if (!lookup.Add(value))
        {
            return false;
        }

        choices.Add(KeyActionChoice.Action(value));
        return true;
    }

    private Dictionary<string, string> CaptureGestureSelections()
    {
        Dictionary<string, string> actions = new(StringComparer.Ordinal);
        foreach (GestureBindingDefinition binding in GestureBindingCatalog.All)
        {
            if (_gestureActionCombos.TryGetValue(binding.Id, out ComboBox? combo))
            {
                actions[binding.Id] = ReadSelectedActionValue(combo, binding.DefaultAction);
            }
        }

        return actions;
    }

    private void RestoreGestureSelections(IReadOnlyDictionary<string, string> actions)
    {
        foreach (GestureBindingDefinition binding in GestureBindingCatalog.All)
        {
            if (!_gestureActionCombos.TryGetValue(binding.Id, out ComboBox? combo))
            {
                continue;
            }

            string selected = actions.TryGetValue(binding.Id, out string? action)
                ? action
                : binding.DefaultAction;
            SetActionComboSelection(combo, selected);
        }
    }

    private static List<KeyActionChoice> BuildKeyActionChoices()
    {
        List<KeyActionChoice> options = [];
        AddActionSection(options, "Core");
        AddKeyActionChoice(options, "None");
        AddKeyActionChoice(options, "Left Click");
        AddKeyActionChoice(options, "Double Click");
        AddKeyActionChoice(options, "Right Click");
        AddKeyActionChoice(options, "Middle Click");

        AddActionSection(options, "Letters A-Z");
        for (char ch = 'A'; ch <= 'Z'; ch++)
        {
            AddKeyActionChoice(options, ch.ToString());
        }

        AddActionSection(options, "Digits 0-9");
        for (char ch = '0'; ch <= '9'; ch++)
        {
            AddKeyActionChoice(options, ch.ToString());
        }

        AddActionSection(options, "Navigation and Editing");
        string[] navigationAndEditing =
        {
            "Space",
            "Tab",
            "Enter",
            "Ret",
            "Backspace",
            "Back",
            "Escape",
            "Caps Lock",
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

        AddActionSection(options, "Modifiers");
        string[] modifiers =
        {
            "Shift",
            "Ctrl",
            "Alt",
            "Win"
        };
        for (int i = 0; i < modifiers.Length; i++)
        {
            AddKeyActionChoice(options, modifiers[i]);
        }

        string[] modes =
        {
            "Chordal Shift",
            "Typing Toggle"
        };

        AddActionSection(options, "Symbols");
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

        AddActionSection(options, "Function Keys");
        for (int i = 1; i <= 12; i++)
        {
            AddKeyActionChoice(options, $"F{i}");
        }

        AddActionSection(options, "System and Media");
        string[] systemAndMedia =
        {
            TerminalActionValue,
            "EMOJI",
            "VOICE",
            "VOL_UP",
            "VOL_DOWN",
            "BRIGHT_UP",
            "BRIGHT_DOWN"
        };

        AddActionSection(options, "Modes");
        for (int i = 0; i < modes.Length; i++)
        {
            AddKeyActionChoice(options, modes[i]);
        }

        for (int i = 0; i < systemAndMedia.Length; i++)
        {
            AddKeyActionChoice(options, systemAndMedia[i]);
        }

        AddActionSection(options, "Layer Controls");
        AddKeyActionChoice(options, "TO(0)");
        for (int layer = 1; layer <= MaxSupportedLayer; layer++)
        {
            AddKeyActionChoice(options, $"MO({layer})");
            AddKeyActionChoice(options, $"TO({layer})");
            AddKeyActionChoice(options, $"TG({layer})");
        }

        return options;
    }

    private static void AddKeyActionChoice(List<KeyActionChoice> choices, string value)
    {
        choices.Add(KeyActionChoice.Action(value));
    }

    private static void AddActionSection(List<KeyActionChoice> choices, string title)
    {
        choices.Add(KeyActionChoice.Section(title));
    }

    private static List<ShortcutKeyChoice> BuildShortcutKeyChoices()
    {
        List<ShortcutKeyChoice> choices = [];
        string? currentSection = null;
        IReadOnlyList<string> labels = DispatchShortcutHelper.ShortcutKeyLabels;
        for (int i = 0; i < labels.Count; i++)
        {
            string value = labels[i];
            string section = GetShortcutKeySection(value);
            if (!string.Equals(currentSection, section, StringComparison.Ordinal))
            {
                currentSection = section;
                choices.Add(ShortcutKeyChoice.Section(section));
            }

            choices.Add(ShortcutKeyChoice.Action(value));
        }

        return choices;
    }

    private static string GetShortcutKeySection(string value)
    {
        if (value.Length == 1 && value[0] is >= 'A' and <= 'Z')
        {
            return "Letters A-Z";
        }

        if (value.Length == 1 && value[0] is >= '0' and <= '9')
        {
            return "Digits 0-9";
        }

        if (value.Length > 1 && value[0] == 'F' && int.TryParse(value.AsSpan(1), out _))
        {
            return "Function Keys";
        }

        return value switch
        {
            ";" or "=" or "," or "-" or "." or "/" or "`" or "[" or "\\" or "]" or "'" => "Symbols",
            _ => "Navigation and Editing"
        };
    }

    private static ShortcutKeyChoice? SelectShortcutKeyChoice(IEnumerable<ShortcutKeyChoice> choices, string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        foreach (ShortcutKeyChoice choice in choices)
        {
            if (!choice.IsSeparator &&
                string.Equals(choice.Value, value, StringComparison.OrdinalIgnoreCase))
            {
                return choice;
            }
        }

        return null;
    }

    private static bool IsUnsupportedLayerActionChoice(string value)
    {
        if (!TryParseLayerActionChoice(value, out int layer))
        {
            return false;
        }

        return layer < 0 || layer > MaxSupportedLayer;
    }

    private static bool TryParseLayerActionChoice(string value, out int layer)
    {
        layer = -1;
        if (value.Length < 5 || value[^1] != ')')
        {
            return false;
        }

        string prefix = value.Substring(0, 3);
        if (!string.Equals(prefix, "MO(", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(prefix, "TO(", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(prefix, "TG(", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return int.TryParse(
            value.AsSpan(3, value.Length - 4),
            NumberStyles.Integer,
            CultureInfo.InvariantCulture,
            out layer);
    }

    private static List<LayerChoice> BuildLayerChoices()
    {
        List<LayerChoice> layers = [];
        for (int layer = 0; layer <= MaxSupportedLayer; layer++)
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
            return Math.Clamp(choice.Layer, 0, MaxSupportedLayer);
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
        RefreshGestureShortcutEditorUi();
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
        RevealKeymapEditorAndFocusPrimaryAction();
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
        RevealCustomButtonEditorAndFocusGeometry();
    }

    private void RevealKeymapEditorAndFocusPrimaryAction()
    {
        if (IsReplayMode)
        {
            return;
        }

        _keymapTuningExpander.IsExpanded = true;
        _customButtonsExpander.IsExpanded = false;
        Dispatcher.UIThread.Post(
            () =>
            {
                _keymapPrimaryCombo.Focus();
            },
            DispatcherPriority.Input);
    }

    private void RevealCustomButtonEditorAndFocusGeometry()
    {
        if (IsReplayMode)
        {
            return;
        }

        _keymapTuningExpander.IsExpanded = true;
        _customButtonsExpander.IsExpanded = true;
        Dispatcher.UIThread.Post(
            () =>
            {
                _customButtonXBox.Focus();
            },
            DispatcherPriority.Input);
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
            RefreshGestureShortcutEditorUi();
            return;
        }

        _keymapClearSelectionButton.IsEnabled = true;
        _customButtonAddLeftButton.IsEnabled = true;
        _customButtonAddRightButton.IsEnabled = true;
        if (TryGetSelectedCustomButton(out _, out CustomButton? selectedButton))
        {
            _customButtonsExpander.IsExpanded = true;
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
            RefreshGestureShortcutEditorUi();
            return;
        }

        if (!TryGetSelectedKeyPosition(out TrackpadSide side, out int row, out int column))
        {
            _customButtonsExpander.IsExpanded = false;
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
            RefreshGestureShortcutEditorUi();
            return;
        }

        KeyLayout layout = side == TrackpadSide.Left ? _leftRenderedLayout : _rightRenderedLayout;
        if (row < 0 || row >= layout.Labels.Length || column < 0 || column >= layout.Labels[row].Length)
        {
            ClearSelectionForEditing();
            _keymapSelectionText.Text = "Selection: none";
            _suppressKeymapEditorEvents = false;
            RefreshGestureShortcutEditorUi();
            return;
        }

        _keymapSelectionText.Text = $"Selection: {side} r{row + 1} c{column + 1}";
        _keymapPrimaryCombo.IsEnabled = true;
        _keymapHoldCombo.IsEnabled = true;
        _customButtonDeleteButton.IsEnabled = false;
        _keyRotationBox.IsEnabled = true;
        _customButtonsExpander.IsExpanded = false;
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
        RefreshGestureShortcutEditorUi();
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
            if (choice.IsSeparator)
            {
                continue;
            }

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
        _customButtonGeometryGrid.IsVisible = enabled;
        _customButtonDeleteButton.IsVisible = enabled;
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
        _columnSettings = RuntimeConfigurationFactory.CloneColumnSettings(columns);
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

    private string ReadActionSelection(ComboBox combo, string fallback)
    {
        string resolved = ReadSelectedActionValue(combo, fallback);
        if (combo.SelectedItem is KeyActionChoice choice && choice.IsSeparator)
        {
            SetActionComboSelection(combo, fallback);
        }

        return resolved;
    }

    private static string ReadSelectedActionValue(ComboBox combo, string fallback)
    {
        if (combo.SelectedItem is KeyActionChoice choice &&
            !choice.IsSeparator &&
            !string.IsNullOrWhiteSpace(choice.Value))
        {
            return choice.Value;
        }

        if (combo.SelectedItem is KeyActionChoice separatorChoice && separatorChoice.IsSeparator)
        {
            return fallback;
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

    private static string NormalizeMultilineText(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return string.Empty;
        }

        string normalized = text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
        string[] lines = normalized.Split('\n');
        List<string> cleaned = new(lines.Length);
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i].Trim();
            if (line.Length == 0)
            {
                continue;
            }

            cleaned.Add(line);
        }

        return string.Join('\n', cleaned);
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

        ClearSelectionForEditing();
        RefreshKeymapEditor();
        ApplyPreviewSnapshot(_previewSnapshot);

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

    public void ShowNotice(string title, string message)
    {
        ShowNoticeDialog(title, message);
    }

    private static List<DeviceChoice> BuildDeviceChoices(IReadOnlyList<LinuxInputDeviceDescriptor> devices)
    {
        List<DeviceChoice> choices =
        [
            new DeviceChoice("(None)", null)
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
        List<PresetChoice> choices = new(TrackpadLayoutPreset.Selectable.Length);
        for (int index = 0; index < TrackpadLayoutPreset.Selectable.Length; index++)
        {
            TrackpadLayoutPreset preset = TrackpadLayoutPreset.Selectable[index];
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
        PresetChoice? fallback = null;
        foreach (PresetChoice choice in choices)
        {
            if (fallback == null &&
                string.Equals(choice.Name, TrackpadLayoutPreset.SixByThree.Name, StringComparison.OrdinalIgnoreCase))
            {
                fallback = choice;
            }

            if (string.Equals(choice.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                return choice;
            }
        }

        return fallback;
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
        UpdateAutocorrectStatusDetails();
    }

    private void UpdateAutocorrectStatusDetails()
    {
        string runtimeState = BuildAutocorrectRuntimeStateText();
        string lastCorrected = "n/a";
        string currentBuffer = "n/a";
        string skipReason = "n/a";
        string resetSource = "n/a";
        string wordHistory = "n/a";

        if (TryGetAutocorrectStatusSnapshot(out AutocorrectStatusSnapshot snapshot))
        {
            if (!snapshot.Enabled)
            {
                runtimeState = "Autocorrect is disabled in the active Linux runtime.";
            }

            lastCorrected = string.IsNullOrWhiteSpace(snapshot.LastCorrected) ? "none" : snapshot.LastCorrected;
            currentBuffer = string.IsNullOrEmpty(snapshot.CurrentBuffer) ? "<empty>" : snapshot.CurrentBuffer;
            skipReason = string.IsNullOrWhiteSpace(snapshot.SkipReason) ? "idle" : snapshot.SkipReason;
            resetSource = string.IsNullOrWhiteSpace(snapshot.LastResetSource) ? "none" : snapshot.LastResetSource;
            wordHistory = string.IsNullOrWhiteSpace(snapshot.WordHistory) ? "<empty>" : snapshot.WordHistory;
        }

        if (!string.Equals(runtimeState, _lastAutocorrectUiRuntimeState, StringComparison.Ordinal))
        {
            _lastAutocorrectUiRuntimeState = runtimeState;
            _autocorrectRuntimeStateText.Text = runtimeState;
        }

        if (!string.Equals(lastCorrected, _lastAutocorrectUiLastCorrected, StringComparison.Ordinal))
        {
            _lastAutocorrectUiLastCorrected = lastCorrected;
            _autocorrectLastCorrectedValueText.Text = lastCorrected;
        }

        if (!string.Equals(currentBuffer, _lastAutocorrectUiCurrentBuffer, StringComparison.Ordinal))
        {
            _lastAutocorrectUiCurrentBuffer = currentBuffer;
            _autocorrectCurrentBufferValueText.Text = currentBuffer;
        }

        if (!string.Equals(skipReason, _lastAutocorrectUiSkipReason, StringComparison.Ordinal))
        {
            _lastAutocorrectUiSkipReason = skipReason;
            _autocorrectSkipReasonValueText.Text = skipReason;
        }

        if (!string.Equals(resetSource, _lastAutocorrectUiResetSource, StringComparison.Ordinal))
        {
            _lastAutocorrectUiResetSource = resetSource;
            _autocorrectResetSourceValueText.Text = resetSource;
        }

        if (!string.Equals(wordHistory, _lastAutocorrectUiWordHistory, StringComparison.Ordinal))
        {
            _lastAutocorrectUiWordHistory = wordHistory;
            _autocorrectWordHistoryValueText.Text = wordHistory;
        }
    }

    private void UpdateAutocorrectStatusVisibility()
    {
        _autocorrectStatusBorder.IsVisible = !IsReplayMode && _autocorrectModeCheck.IsChecked == true;
    }

    private bool TryGetAutocorrectStatusSnapshot(out AutocorrectStatusSnapshot snapshot)
    {
        return _desktopRuntime.TryGetAutocorrectStatus(out snapshot);
    }

    private string BuildAutocorrectRuntimeStateText()
    {
        LinuxDesktopRuntimeSnapshot runtimeSnapshot = _desktopRuntime.RuntimeSnapshot;
        if (TryGetAutocorrectStatusSnapshot(out AutocorrectStatusSnapshot snapshot) && snapshot.Enabled)
        {
            string mode = snapshot.DryRunEnabled ? "dry run" : "active";
            string app = string.IsNullOrWhiteSpace(snapshot.CurrentApp) ? "unknown app" : snapshot.CurrentApp;
            return $"Runtime {mode}. Current app: {app}. Corrections: {snapshot.CorrectedCount}, skipped: {snapshot.SkippedCount}.";
        }

        return runtimeSnapshot.Status switch
        {
            LinuxDesktopRuntimeStatus.Running => "Runtime active. Touch a key to populate autocorrect state.",
            LinuxDesktopRuntimeStatus.Starting => "Runtime starting.",
            LinuxDesktopRuntimeStatus.Stopping => "Runtime stopping.",
            LinuxDesktopRuntimeStatus.WaitingForBindings => "Runtime waiting for trackpad bindings.",
            LinuxDesktopRuntimeStatus.Faulted => "Runtime faulted.",
            _ => "Runtime stopped."
        };
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
        RefreshColumnLayoutEditor();
        RefreshKeymapEditor();
        UpdateAutocorrectStatusVisibility();
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
        RefreshColumnLayoutEditor();
        RefreshKeymapEditor();
        UpdateAutocorrectStatusVisibility();
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
        int activeLayer = ResolveVisualizerLayer(snapshot);
        LinuxInputPreviewTrackpadState? left = GetPreviewState(snapshot, TrackpadSide.Left);
        LinuxInputPreviewTrackpadState? right = GetPreviewState(snapshot, TrackpadSide.Right);
        _leftPreviewText.Text = BuildPreviewDetails(left, _leftRenderedLayout, _renderedKeymap, TrackpadSide.Left, activeLayer, ref _leftStickyTouchedKeys);
        _rightPreviewText.Text = BuildPreviewDetails(right, _rightRenderedLayout, _renderedKeymap, TrackpadSide.Right, activeLayer, ref _rightStickyTouchedKeys);
        RenderPreviewCanvas(_leftPreviewCanvas, left, _leftRenderedLayout, _renderedKeymap, TrackpadSide.Left, activeLayer, "#D05A2A");
        RenderPreviewCanvas(_rightPreviewCanvas, right, _rightRenderedLayout, _renderedKeymap, TrackpadSide.Right, activeLayer, "#246A73");
    }

    private int ResolveVisualizerLayer(LinuxInputPreviewSnapshot snapshot)
    {
        int selectedLayer = Math.Clamp(GetSelectedLayer(), 0, MaxSupportedLayer);

        if (IsReplayMode)
        {
            LinuxAtpCapReplayVisualFrame? frame = GetCurrentReplayFrame();
            if (frame.HasValue)
            {
                return ResolveVisualizerLayer(
                    frame.Value.PreviewSnapshot,
                    frame.Value.RuntimeSnapshot,
                    selectedLayer);
            }
        }

        return ResolveVisualizerLayer(snapshot, _desktopRuntime.RuntimeSnapshot, selectedLayer);
    }

    private int ResolveVisualizerLayer(
        LinuxInputPreviewSnapshot snapshot,
        LinuxDesktopRuntimeSnapshot runtimeSnapshot,
        int selectedLayer)
    {
        if (HasPressedLayerOverride(snapshot, selectedLayer))
        {
            return Math.Clamp(runtimeSnapshot.ActiveLayer, 0, MaxSupportedLayer);
        }

        return selectedLayer;
    }

    private bool HasPressedLayerOverride(LinuxInputPreviewSnapshot snapshot, int layer)
    {
        for (int index = 0; index < snapshot.Trackpads.Count; index++)
        {
            LinuxInputPreviewTrackpadState state = snapshot.Trackpads[index];
            KeyLayout layout = state.Side == TrackpadSide.Left ? _leftRenderedLayout : _rightRenderedLayout;
            if (HasPressedLayerOverride(state, layout, _renderedKeymap, layer))
            {
                return true;
            }
        }

        return false;
    }

    private static bool HasPressedLayerOverride(
        LinuxInputPreviewTrackpadState state,
        KeyLayout layout,
        KeymapStore keymap,
        int layer)
    {
        if (state.Contacts.Count == 0 || state.MaxX == 0 || state.MaxY == 0)
        {
            return false;
        }

        for (int index = 0; index < state.Contacts.Count; index++)
        {
            LinuxInputPreviewContact contact = state.Contacts[index];
            if (!contact.TipSwitch)
            {
                continue;
            }

            double x = contact.X / (double)state.MaxX;
            double y = contact.Y / (double)state.MaxY;
            if (TryResolveLayerOverrideFromGridKey(state.Side, layout, keymap, layer, x, y, out _) ||
                TryResolveLayerOverrideFromCustomButton(state.Side, keymap, layer, x, y, out _))
            {
                return true;
            }
        }

        return false;
    }

    private static bool TryResolveLayerOverrideFromGridKey(
        TrackpadSide side,
        KeyLayout layout,
        KeymapStore keymap,
        int layer,
        double x,
        double y,
        out int targetLayer)
    {
        targetLayer = 0;
        if (layout.HitGeometries.Length == 0)
        {
            return false;
        }

        for (int row = 0; row < layout.HitGeometries.Length; row++)
        {
            for (int col = 0; col < layout.HitGeometries[row].Length; col++)
            {
                if (!layout.HitGeometries[row][col].Contains(x, y))
                {
                    continue;
                }

                string storageKey = GridKeyPosition.StorageKey(side, row, col);
                KeyMapping mapping = keymap.ResolveMapping(layer, storageKey, layout.Labels[row][col]);
                if (TryParseLayerActionChoice(mapping.Primary.Label, out targetLayer))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static bool TryResolveLayerOverrideFromCustomButton(
        TrackpadSide side,
        KeymapStore keymap,
        int layer,
        double x,
        double y,
        out int targetLayer)
    {
        targetLayer = 0;
        IReadOnlyList<CustomButton> customButtons = keymap.ResolveCustomButtons(layer, side);
        for (int index = 0; index < customButtons.Count; index++)
        {
            CustomButton button = customButtons[index];
            if (!button.Rect.Contains(x, y))
            {
                continue;
            }

            if (TryParseLayerActionChoice(button.Primary.Label, out targetLayer))
            {
                return true;
            }
        }

        return false;
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

    private static string BuildPreviewDetails(
        LinuxInputPreviewTrackpadState? state,
        KeyLayout layout,
        KeymapStore keymap,
        TrackpadSide side,
        int activeLayer,
        ref string stickyTouchedKeys)
    {
        if (state == null)
        {
            stickyTouchedKeys = "Touched keys: (none)";
            return stickyTouchedKeys;
        }

        string[] hits = ResolveTouchedLabels(state, layout, keymap, side, activeLayer);
        if (hits.Length > 0)
        {
            stickyTouchedKeys = $"Touched keys: {string.Join(", ", hits)}";
        }

        return stickyTouchedKeys;
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
            if (state.BindingStatus == LinuxRuntimeBindingStatus.Streaming)
            {
                return;
            }

            canvas.Children.Add(new TextBlock
            {
                Text = state.BindingMessage,
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
        _columnSettings = RuntimeConfigurationFactory.CloneColumnSettings(columns);
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
                KeyMapping mapping = keymap.ResolveMapping(activeLayer, storageKey, layout.Labels[row][col]);
                string label = BuildKeymapDisplayLabel(mapping, layout.Labels[row][col], separator: "\n");
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
                    Text = BuildCustomButtonDisplayLabel(button, separator: "\n"),
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
                    KeyMapping mapping = keymap.ResolveMapping(activeLayer, storageKey, layout.Labels[row][col]);
                    labels.Add(BuildKeymapDisplayLabel(mapping, layout.Labels[row][col], separator: " / "));
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
                    labels.Add(BuildCustomButtonDisplayLabel(button, separator: " / "));
                }
            }
        }

        return labels.Count == 0 ? Array.Empty<string>() : [.. labels];
    }

    private static string BuildKeymapDisplayLabel(KeyMapping mapping, string defaultLabel, string separator)
    {
        string primary = string.IsNullOrWhiteSpace(mapping.Primary.Label) ? defaultLabel : mapping.Primary.Label;
        return BuildPrimaryHoldDisplayLabel(primary, mapping.Hold?.Label, separator);
    }

    private static string BuildCustomButtonDisplayLabel(CustomButton button, string separator)
    {
        string primary = string.IsNullOrWhiteSpace(button.Primary?.Label) ? "None" : button.Primary.Label;
        return BuildPrimaryHoldDisplayLabel(primary, button.Hold?.Label, separator);
    }

    private static string BuildPrimaryHoldDisplayLabel(string primary, string? hold, string separator)
    {
        string displayPrimary = FormatSurfaceActionLabel(primary);
        if (string.IsNullOrWhiteSpace(hold))
        {
            return displayPrimary;
        }

        return $"{displayPrimary}{separator}{FormatSurfaceActionLabel(hold)}";
    }

    private static string FormatSurfaceActionLabel(string action)
    {
        return GetActionDisplayLabel(action);
    }

    private static string GetActionDisplayLabel(string action)
    {
        if (TryGetSpecialActionDisplayLabel(action, out string label))
        {
            return label;
        }

        return AppLaunchActionHelper.TryParse(action, out _)
            ? AppLaunchActionHelper.GetKeymapDisplayLabel(action)
            : action;
    }

    private static bool TryGetSpecialActionDisplayLabel(string? action, out string label)
    {
        label = string.Empty;
        if (!AppLaunchActionHelper.TryParse(action, out AppLaunchActionSpec spec))
        {
            return false;
        }

        if (string.Equals(spec.FileName, TerminalLauncherCommand, StringComparison.OrdinalIgnoreCase) &&
            string.IsNullOrWhiteSpace(spec.Arguments))
        {
            label = "Terminal";
            return true;
        }

        return false;
    }

    private static IDataTemplate CreateKeyActionChoiceTemplate()
    {
        return new FuncDataTemplate<object?>((value, _) =>
        {
            if (value is KeyActionChoice choice)
            {
                if (choice.IsSeparator)
                {
                    Grid grid = new()
                    {
                        ColumnDefinitions = new ColumnDefinitions("*,Auto,*"),
                        Margin = new Thickness(6, 2)
                    };

                    Border leftRule = new()
                    {
                        Height = 1,
                        Background = new SolidColorBrush(Color.Parse("#9FB3C1")),
                        VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                        Margin = new Thickness(0, 0, 8, 0)
                    };
                    grid.Children.Add(leftRule);

                    TextBlock title = new()
                    {
                        Text = choice.Label,
                        Foreground = new SolidColorBrush(Color.Parse("#4A5B68")),
                        FontSize = 11,
                        FontWeight = FontWeight.SemiBold,
                        VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
                    };
                    Grid.SetColumn(title, 1);
                    grid.Children.Add(title);

                    Border rightRule = new()
                    {
                        Height = 1,
                        Background = new SolidColorBrush(Color.Parse("#9FB3C1")),
                        VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                        Margin = new Thickness(8, 0, 0, 0)
                    };
                    Grid.SetColumn(rightRule, 2);
                    grid.Children.Add(rightRule);
                    return grid;
                }

                return new TextBlock
                {
                    Text = choice.Label,
                    Margin = new Thickness(6, 2),
                    Foreground = new SolidColorBrush(Color.Parse("#1E2328"))
                };
            }

            return new TextBlock
            {
                Text = value?.ToString() ?? string.Empty,
                Margin = new Thickness(6, 2)
            };
        });
    }

    private static IDataTemplate CreateShortcutKeyChoiceTemplate()
    {
        return new FuncDataTemplate<object?>((value, _) =>
        {
            if (value is ShortcutKeyChoice choice)
            {
                if (choice.IsSeparator)
                {
                    Grid grid = new()
                    {
                        ColumnDefinitions = new ColumnDefinitions("*,Auto,*"),
                        Margin = new Thickness(6, 2)
                    };

                    Border leftRule = new()
                    {
                        Height = 1,
                        Background = new SolidColorBrush(Color.Parse("#9FB3C1")),
                        VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                        Margin = new Thickness(0, 0, 8, 0)
                    };
                    grid.Children.Add(leftRule);

                    Border chip = new()
                    {
                        CornerRadius = new CornerRadius(6),
                        Padding = new Thickness(8, 2),
                        Background = new SolidColorBrush(Color.Parse("#21323B")),
                        BorderBrush = new SolidColorBrush(Color.Parse("#5C7482")),
                        BorderThickness = new Thickness(1),
                        Child = new TextBlock
                        {
                            Text = choice.Label,
                            Foreground = new SolidColorBrush(Color.Parse("#DCE6EC")),
                            FontSize = 12,
                            FontWeight = FontWeight.SemiBold
                        }
                    };
                    Grid.SetColumn(chip, 1);
                    grid.Children.Add(chip);

                    Border rightRule = new()
                    {
                        Height = 1,
                        Background = new SolidColorBrush(Color.Parse("#9FB3C1")),
                        VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                        Margin = new Thickness(8, 0, 0, 0)
                    };
                    Grid.SetColumn(rightRule, 2);
                    grid.Children.Add(rightRule);

                    return grid;
                }

                return new TextBlock
                {
                    Text = choice.Label,
                    Margin = new Thickness(10, 2),
                    Foreground = new SolidColorBrush(Color.Parse("#F1F5F8"))
                };
            }

            return new TextBlock();
        });
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

    private sealed record LayerChoice(string Label, int Layer)
    {
        public override string ToString()
        {
            return Label;
        }
    }

    private sealed record KeyActionChoice(string Label, string Value, bool IsSeparator)
    {
        public static KeyActionChoice Action(string value)
        {
            string label = GetActionDisplayLabel(value);
            return new KeyActionChoice(label, value, IsSeparator: false);
        }

        public static KeyActionChoice Section(string title)
        {
            string key = title.Replace(' ', '_');
            return new KeyActionChoice(title, $"__section__{key}", IsSeparator: true);
        }

        public override string ToString()
        {
            return Label;
        }
    }

    private sealed record ShortcutKeyChoice(string Label, string Value, bool IsSeparator)
    {
        public static ShortcutKeyChoice Action(string value)
        {
            return new ShortcutKeyChoice(value, value, IsSeparator: false);
        }

        public static ShortcutKeyChoice Section(string title)
        {
            string key = title.Replace(' ', '_');
            return new ShortcutKeyChoice(title, $"__section__{key}", IsSeparator: true);
        }

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
