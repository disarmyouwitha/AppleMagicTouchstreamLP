using System;
using System.Diagnostics;
using System.Threading;
using WinForms = System.Windows.Forms;

namespace AmtPtpVisualizer;

internal sealed class TouchRuntimeService : IDisposable
{
    private readonly ReaderOptions _options;
    private readonly RawInputContext _rawInputContext = new();
    private readonly GlobalMouseClickSuppressor _globalClickSuppressor = new();

    private RuntimeRoute _leftRoute = RuntimeRoute.Empty;
    private RuntimeRoute _rightRoute = RuntimeRoute.Empty;
    private TouchProcessorCore? _touchCore;
    private TouchProcessorActor? _touchActor;
    private DispatchEventQueue? _dispatchQueue;
    private DispatchEventPump? _dispatchPump;
    private InputSinkWindow? _inputSink;
    private Timer? _snapshotTimer;
    private IRuntimeFrameObserver? _frameObserver;
    private RuntimeModeIndicator _lastModeIndicator = RuntimeModeIndicator.Unknown;

    private UserSettings _settings;
    private KeymapStore _keymap;
    private TrackpadLayoutPreset _preset;
    private ColumnLayoutSettings[] _columnSettings;
    private bool _started;
    public event Action<RuntimeModeIndicator>? ModeIndicatorChanged;

    public TouchRuntimeService(ReaderOptions options)
    {
        _options = options;
        _settings = UserSettings.Load();
        _keymap = KeymapStore.Load();
        _preset = TrackpadLayoutPreset.ResolveByNameOrDefault(_settings.LayoutPresetName);
        _columnSettings = RuntimeConfigurationFactory.BuildColumnSettingsForPreset(_settings, _preset);
    }

    public bool Start(out string? error)
    {
        error = null;
        if (_started)
        {
            return true;
        }

        try
        {
            _keymap.SetActiveLayout(_preset.Name);
            RuntimeConfigurationFactory.BuildLayouts(_settings, _preset, _columnSettings, out KeyLayout leftLayout, out KeyLayout rightLayout);

            _touchCore = TouchProcessorFactory.CreateDefault(_keymap, _preset, RuntimeConfigurationFactory.BuildTouchConfig(_settings));
            _dispatchQueue = new DispatchEventQueue();
            _touchActor = new TouchProcessorActor(_touchCore, dispatchQueue: _dispatchQueue);
            _dispatchPump = new DispatchEventPump(_dispatchQueue, new SendInputDispatcher());

            int layer = Math.Clamp(_settings.ActiveLayer, 0, 7);
            _touchActor.ConfigureLayouts(leftLayout, rightLayout);
            _touchActor.ConfigureKeymap(_keymap);
            _touchActor.SetPersistentLayer(layer);
            _touchActor.SetTypingEnabled(_settings.TypingEnabled);
            _touchActor.SetKeyboardModeEnabled(_settings.KeyboardModeEnabled);
            _touchActor.SetAllowMouseTakeover(_settings.AllowMouseTakeover);
            _lastModeIndicator = ToModeIndicator(_settings.TypingEnabled, _settings.KeyboardModeEnabled);

            RefreshDeviceRoutes(_settings.LeftDevicePath, _settings.RightDevicePath);

            _inputSink = new InputSinkWindow(this);
            _inputSink.Create();
            if (!RawInputInterop.RegisterForTouchpadRawInput(_inputSink.Handle, out string? registerError))
            {
                error = $"Raw input registration failed ({registerError}).";
                Dispose();
                return false;
            }

            if (!_globalClickSuppressor.Install(out string? hookError))
            {
                Console.WriteLine($"Global click suppression hook failed ({hookError}).");
            }

            _snapshotTimer = new Timer(OnSnapshotTimerTick, null, dueTime: 50, period: 50);
            _started = true;
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            Dispose();
            return false;
        }
    }

    public void ApplyConfiguration(
        UserSettings settings,
        KeymapStore keymap,
        TrackpadLayoutPreset preset,
        ColumnLayoutSettings[] columnSettings,
        int activeLayer)
    {
        _settings = settings;
        _keymap = keymap;
        _preset = preset;
        _columnSettings = RuntimeConfigurationFactory.CloneColumnSettings(columnSettings);

        _keymap.SetActiveLayout(_preset.Name);
        RuntimeConfigurationFactory.BuildLayouts(_settings, _preset, _columnSettings, out KeyLayout leftLayout, out KeyLayout rightLayout);

        TouchProcessorActor? actor = _touchActor;
        if (actor == null)
        {
            return;
        }

        actor.Configure(RuntimeConfigurationFactory.BuildTouchConfig(_settings));
        actor.SetKeyboardModeEnabled(_settings.KeyboardModeEnabled);
        actor.SetAllowMouseTakeover(_settings.AllowMouseTakeover);
        actor.ConfigureLayouts(leftLayout, rightLayout);
        actor.ConfigureKeymap(_keymap);
        actor.SetPersistentLayer(Math.Clamp(activeLayer, 0, 7));
    }

    public void UpdateDeviceSelections(string? leftPath, string? rightPath)
    {
        _settings.LeftDevicePath = leftPath;
        _settings.RightDevicePath = rightPath;
        RefreshDeviceRoutes(leftPath, rightPath);
    }

    public void SetFrameObserver(IRuntimeFrameObserver? observer)
    {
        _frameObserver = observer;
    }

    public RuntimeModeIndicator GetCurrentModeIndicator()
    {
        if (TryGetSnapshot(out TouchProcessorSnapshot snapshot))
        {
            return ToModeIndicator(snapshot.TypingEnabled, snapshot.KeyboardModeEnabled);
        }

        return _lastModeIndicator;
    }

    public bool TryGetSnapshot(out TouchProcessorSnapshot snapshot)
    {
        TouchProcessorActor? actor = _touchActor;
        if (actor == null)
        {
            snapshot = default;
            return false;
        }

        snapshot = actor.Snapshot();
        return true;
    }

    public void Dispose()
    {
        _snapshotTimer?.Dispose();
        _snapshotTimer = null;
        _frameObserver = null;

        _globalClickSuppressor.SetEnabled(false);
        _globalClickSuppressor.Dispose();

        _inputSink?.Dispose();
        _inputSink = null;

        _touchActor?.Dispose();
        _touchActor = null;

        _dispatchPump?.Dispose();
        _dispatchPump = null;

        _dispatchQueue?.Dispose();
        _dispatchQueue = null;

        _touchCore = null;
        _started = false;
        ModeIndicatorChanged = null;
    }

    private void OnSnapshotTimerTick(object? _)
    {
        TouchProcessorActor? actor = _touchActor;
        if (actor == null)
        {
            return;
        }

        TouchProcessorSnapshot snapshot = actor.Snapshot();
        _globalClickSuppressor.SetEnabled(snapshot.KeyboardModeEnabled && snapshot.TypingEnabled);
        RuntimeModeIndicator nextMode = ToModeIndicator(snapshot.TypingEnabled, snapshot.KeyboardModeEnabled);
        if (nextMode == _lastModeIndicator)
        {
            return;
        }

        _lastModeIndicator = nextMode;
        try
        {
            ModeIndicatorChanged?.Invoke(nextMode);
        }
        catch
        {
            // Observer failures should never impact hot-path processing.
        }
    }

    private void RefreshDeviceRoutes(string? leftPath, string? rightPath)
    {
        HidDeviceInfo[] devices = RawInputInterop.EnumerateTrackpads();
        HidDeviceInfo[] seed = new HidDeviceInfo[devices.Length + 1];
        seed[0] = new HidDeviceInfo("None", null);
        for (int i = 0; i < devices.Length; i++)
        {
            seed[i + 1] = devices[i];
        }

        _rawInputContext.SeedTags(seed);
        _leftRoute = RuntimeRoute.FromPath(leftPath);
        _rightRoute = RuntimeRoute.FromPath(rightPath);
    }

    private void HandleRawInput(IntPtr lParam)
    {
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

        bool routeLeft = _leftRoute.IsMatch(snapshot.DeviceName);
        bool routeRight = _rightRoute.IsMatch(snapshot.DeviceName);
        if (!routeLeft && !routeRight)
        {
            return;
        }

        int reportSize = (int)packet.ReportSize;
        if (reportSize <= 0)
        {
            return;
        }

        ushort maxX = _options.MaxX ?? RuntimeConfigurationFactory.DefaultMaxX;
        ushort maxY = _options.MaxY ?? RuntimeConfigurationFactory.DefaultMaxY;

        TouchProcessorActor? actor = _touchActor;
        if (actor == null)
        {
            return;
        }

        for (uint i = 0; i < packet.ReportCount; i++)
        {
            int offset = packet.DataOffset + (int)(i * packet.ReportSize);
            if (offset + reportSize > packet.ValidLength)
            {
                break;
            }

            ReadOnlySpan<byte> reportSpan = packet.Buffer.AsSpan(offset, reportSize);
            if (reportSpan.Length < PtpReport.ExpectedSize || reportSpan[0] != RawInputInterop.ReportIdMultitouch)
            {
                continue;
            }

            if (!PtpReport.TryParse(reportSpan, out PtpReport report))
            {
                continue;
            }

            long timestampTicks = Stopwatch.GetTimestamp();
            InputFrame frame = InputFrame.FromReport(timestampTicks, in report);

            if (routeLeft)
            {
                _frameObserver?.OnRuntimeFrame(TrackpadSide.Left, in frame, snapshot.Tag);
                _ = actor.Post(TrackpadSide.Left, in frame, maxX, maxY, timestampTicks);
            }

            if (routeRight)
            {
                _frameObserver?.OnRuntimeFrame(TrackpadSide.Right, in frame, snapshot.Tag);
                _ = actor.Post(TrackpadSide.Right, in frame, maxX, maxY, timestampTicks);
            }
        }
    }

    private static RuntimeModeIndicator ToModeIndicator(bool typingEnabled, bool keyboardModeEnabled)
    {
        if (!typingEnabled)
        {
            return RuntimeModeIndicator.Mouse;
        }

        return keyboardModeEnabled
            ? RuntimeModeIndicator.Keyboard
            : RuntimeModeIndicator.Mixed;
    }

    private readonly record struct RuntimeRoute(string? DevicePath)
    {
        public static RuntimeRoute Empty => new(null);

        public static RuntimeRoute FromPath(string? devicePath)
        {
            return string.IsNullOrWhiteSpace(devicePath) ? Empty : new RuntimeRoute(devicePath);
        }

        public bool IsMatch(string deviceName)
        {
            return !string.IsNullOrWhiteSpace(DevicePath) &&
                   string.Equals(DevicePath, deviceName, StringComparison.OrdinalIgnoreCase);
        }
    }

    private sealed class InputSinkWindow : WinForms.NativeWindow, IDisposable
    {
        private readonly TouchRuntimeService _owner;

        public InputSinkWindow(TouchRuntimeService owner)
        {
            _owner = owner;
        }

        public void Create()
        {
            WinForms.CreateParams parameters = new()
            {
                Caption = "AmtPtpRuntimeInputSink",
                X = -32000,
                Y = -32000,
                Width = 1,
                Height = 1
            };
            CreateHandle(parameters);
        }

        protected override void WndProc(ref WinForms.Message m)
        {
            if (m.Msg == RawInputInterop.WM_INPUT)
            {
                _owner.HandleRawInput(m.LParam);
            }

            base.WndProc(ref m);
        }

        public void Dispose()
        {
            if (Handle != IntPtr.Zero)
            {
                DestroyHandle();
            }
        }
    }
}
