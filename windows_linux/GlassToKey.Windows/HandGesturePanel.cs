using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace GlassToKey;

// Same trigger/action menus and Left/Right/Both semantics as the Mac inspector.
internal sealed class HandGesturePanel : StackPanel
{
    private UserSettings _settings;
    private readonly Action _changed;
    private readonly ComboBox _scope = new() { ItemsSource = Enum.GetValues<HandGestureScope>(), SelectedIndex = 2, Height = 26 };
    private readonly StackPanel _rows = new();
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, FontSize = 11, Margin = new(0,8,0,0) };
    private bool _refreshing;
    public HandGesturePanel(UserSettings settings, Action changed)
    {
        _settings = settings; _changed = changed;
        Children.Add(_scope); Children.Add(_rows);
        Children.Add(new TextBlock { Text = "Use Mouse Takeover for gesture output. Lift all fingers once after enabling or changing bindings. Ctrl+Alt+R releases it. Disable Windows 3/4-finger gestures to prevent native actions.", TextWrapping = TextWrapping.Wrap, FontSize = 11, Margin = new(0,10,0,0) });
        Children.Add(new TextBlock { Text = "Apple acceleration uses a Mac reference profile unless you import your own. Scroll uses high-resolution wheel/pan with momentum.", TextWrapping = TextWrapping.Wrap, FontSize = 11, Margin = new(0,6,0,0) });
        Children.Add(_status);
        _scope.SelectionChanged += (_,_) => Rebuild();
        Rebuild();
    }
    public void SetStatus(string text) { if (_status.Text != text) _status.Text = text; }
    public void Refresh(UserSettings settings) { _settings = settings; Rebuild(); }
    private void Rebuild()
    {
        if (_refreshing) return;
        _refreshing = true;
        try
        {
            _settings.HandGesturesV1 ??= new(); _settings.HandGesturesV1.Normalize();
            _rows.Children.Clear();
            foreach (var trigger in Enum.GetValues<HandGestureTrigger>())
            {
                var row = new StackPanel { Margin = new(0,9,0,0) };
                row.Children.Add(new TextBlock { Text = Title(trigger), Foreground = new SolidColorBrush(Color.FromRgb(143,182,207)), FontSize = 12,
                    ToolTip = trigger == HandGestureTrigger.ThreeFingerMove ? "Same as Mac: activation requires a compact, aligned fingertip chord. Once active it stays latched until all fingers lift." : null });
                var options = Enum.GetValues<HandGestureAction>().Where(a => PerHandGestureSettings.Allows(trigger,a))
                    .Select(a => new ActionOption(a, ActionTitle(a))).ToList();
                var left = _settings.HandGesturesV1.Left.Get(trigger); var right = _settings.HandGesturesV1.Right.Get(trigger);
                var scope = (HandGestureScope)_scope.SelectedItem;
                HandGestureAction? value = scope == HandGestureScope.Left ? left : scope == HandGestureScope.Right ? right : left == right ? left : null;
                if (value == null) options.Insert(0, new(null,"Mixed"));
                var combo = new ComboBox { ItemsSource = options, DisplayMemberPath = nameof(ActionOption.Title), Height = 26, Margin = new(0,4,0,0),
                    SelectedItem = options.First(o => o.Action == value) };
                combo.SelectionChanged += (_,_) =>
                {
                    if (_refreshing || combo.SelectedItem is not ActionOption { Action: { } action }) return;
                    if (scope != HandGestureScope.Right) _settings.HandGesturesV1.Left.Set(trigger,action);
                    if (scope != HandGestureScope.Left) _settings.HandGesturesV1.Right.Set(trigger,action);
                    _changed();
                };
                row.Children.Add(combo);
                if (trigger == HandGestureTrigger.ThumbTwoTap) row.Children.Add(new TextBlock { Text = "Unavailable with current Windows reports: no thumb identity. You can save an assignment or choose None; unknown three-contact taps use 3-finger tap.", TextWrapping = TextWrapping.Wrap, FontSize = 11, Margin = new(0,4,0,0) });
                _rows.Children.Add(row);
            }
            AddPointerResponse();
            AddGain("Pointer sensitivity",false); AddGain("Scroll sensitivity",true);
            AddNaturalScrolling();
        }
        finally { _refreshing = false; }
    }
    private void ApplyToScope(Action<PerHandGestureSettings> apply)
    {
        var scope = (HandGestureScope)_scope.SelectedItem;
        if (scope != HandGestureScope.Right) apply(_settings.HandGesturesV1.Left);
        if (scope != HandGestureScope.Left) apply(_settings.HandGesturesV1.Right);
    }
    private void AddNaturalScrolling()
    {
        var scope = (HandGestureScope)_scope.SelectedItem;
        bool left = _settings.HandGesturesV1.Left.NaturalScrolling, right = _settings.HandGesturesV1.Right.NaturalScrolling;
        bool? value = scope == HandGestureScope.Left ? left : scope == HandGestureScope.Right ? right : left == right ? left : null;
        var check = new CheckBox { Content = "Natural scrolling", IsThreeState = true, IsChecked = value, Margin = new(0,10,0,0),
            ToolTip = "Checked: content follows your fingers. Uncheck to reverse vertical and horizontal scrolling, including momentum. Mixed means Left/Right differ." };
        check.Click += (_,_) =>
        {
            if (_refreshing) return;
            bool enabled = value != true;
            check.IsChecked = enabled;
            ApplyToScope(hand => hand.NaturalScrolling = enabled); _changed();
        };
        _rows.Children.Add(check);
    }
    private void AddPointerResponse()
    {
        var scope = (HandGestureScope)_scope.SelectedItem;
        var left = _settings.HandGesturesV1.Left; var right = _settings.HandGesturesV1.Right;
        HandPointerResponse? selected = scope == HandGestureScope.Left ? left.PointerResponse : scope == HandGestureScope.Right ? right.PointerResponse
            : left.PointerResponse == right.PointerResponse ? left.PointerResponse : null;
        bool imported = (scope == HandGestureScope.Right || left.ImportedPointerProfile != null) && (scope == HandGestureScope.Left || right.ImportedPointerProfile != null);
        var options = new List<ResponseOption> { new(HandPointerResponse.AppleReference,"Apple acceleration (Mac reference)"), new(HandPointerResponse.Fixed,"Fixed 6 px/mm") };
        if (imported) options.Insert(1,new(HandPointerResponse.ImportedApple,"Apple acceleration (imported Mac profile)"));
        if (selected == null) options.Insert(0,new(null,"Mixed"));
        _rows.Children.Add(new TextBlock { Text = "Pointer response (movement and drag)", Margin = new(0,10,0,4), FontSize = 12 });
        var combo = new ComboBox { ItemsSource = options, DisplayMemberPath = nameof(ResponseOption.Title), SelectedItem = options.First(o => o.Value == selected), Height = 26 };
        combo.SelectionChanged += (_,_) =>
        {
            if (_refreshing || combo.SelectedItem is not ResponseOption { Value: {} response }) return;
            ApplyToScope(hand => hand.PointerResponse = response); _changed();
        };
        _rows.Children.Add(combo);
        var import = new Button { Content = "Import Mac tracking profile…", Margin = new(0,5,0,0), Height = 26 };
        import.Click += (_,_) => ImportPointerProfile();
        _rows.Children.Add(import);
    }
    private void ImportPointerProfile()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Title = "Import Mac pointer-settings.json", Filter = "Pointer settings (*.json)|*.json", CheckFileExists = true };
        var owner = Window.GetWindow(this);
        if (dialog.ShowDialog(owner) != true) return;
        try
        {
            if (new System.IO.FileInfo(dialog.FileName).Length > 1024*1024) throw new ArgumentException("Pointer settings exceed 1 MB.");
            var profiles = ApplePointerProfile.ReadSnapshot(System.IO.File.ReadAllText(dialog.FileName));
            int index = 0;
            if (profiles.Length > 1)
            {
                var choose = new Window { Title = "Choose Mac trackpad profile", Width = 460, Height = 260, Owner = owner, WindowStartupLocation = WindowStartupLocation.CenterOwner };
                var content = new StackPanel { Margin = new(12) };
                var list = new ListBox { ItemsSource = profiles.Select(p => $"{p.DeviceId} · resolution {p.Resolution:0.##} · acceleration {p.Acceleration:0.##}"), SelectedIndex = 0, Height = 140 };
                var use = new Button { Content = "Use selected profile", Margin = new(0,10,0,0), Height = 28 };
                use.Click += (_,_) => { if (list.SelectedIndex >= 0) choose.DialogResult = true; };
                content.Children.Add(list); content.Children.Add(use); choose.Content = content;
                if (choose.ShowDialog() != true) return;
                index = list.SelectedIndex;
            }
            ApplyToScope(hand => { hand.ImportedPointerProfile = profiles[index].Copy(); hand.PointerResponse = HandPointerResponse.ImportedApple; });
            _changed();
        }
        catch (Exception ex) { MessageBox.Show(owner,ex.Message,"Cannot import tracking profile",MessageBoxButton.OK,MessageBoxImage.Warning); }
    }
    private void AddGain(string title, bool scroll)
    {
        var scope = (HandGestureScope)_scope.SelectedItem;
        double left = scroll ? _settings.HandGesturesV1.Left.ScrollSensitivity : _settings.HandGesturesV1.Left.PointerSensitivity;
        double right = scroll ? _settings.HandGesturesV1.Right.ScrollSensitivity : _settings.HandGesturesV1.Right.PointerSensitivity;
        double? value = scope == HandGestureScope.Left ? left : scope == HandGestureScope.Right ? right : left == right ? left : null;
        var options = new List<GainOption>();
        if (value == null) options.Add(new(null,"Mixed"));
        foreach (double gain in new[] {.25,.5,.75,1,1.25,1.5,1.75,2}.Append(value ?? 1).Distinct().Order()) options.Add(new(gain,$"{gain:0.##}×"));
        _rows.Children.Add(new TextBlock { Text = title, Margin = new(0,10,0,4), FontSize = 12 });
        var combo = new ComboBox { ItemsSource = options, DisplayMemberPath = nameof(GainOption.Title), SelectedItem = options.First(o => o.Value == value), Height = 26 };
        combo.SelectionChanged += (_,_) =>
        {
            if (_refreshing || combo.SelectedItem is not GainOption { Value: { } gain }) return;
            if (scope != HandGestureScope.Right) SetGain(_settings.HandGesturesV1.Left,scroll,gain);
            if (scope != HandGestureScope.Left) SetGain(_settings.HandGesturesV1.Right,scroll,gain);
            _changed();
        };
        _rows.Children.Add(combo);
    }
    private static void SetGain(PerHandGestureSettings hand, bool scroll, double gain) { if (scroll) hand.ScrollSensitivity = gain; else hand.PointerSensitivity = gain; }
    private sealed record ActionOption(HandGestureAction? Action, string Title);
    private sealed record GainOption(double? Value, string Title);
    private sealed record ResponseOption(HandPointerResponse? Value, string Title);
    private static string Title(HandGestureTrigger trigger) => trigger switch
    {
        HandGestureTrigger.TwoFingerMove => "● ●  2-finger movement", HandGestureTrigger.TwoFingerTap => "● ●  2-finger tap",
        HandGestureTrigger.ThreeFingerMove => "● ● ●  3-finger movement", HandGestureTrigger.ThreeFingerTap => "● ● ●  3-finger tap",
        HandGestureTrigger.FourFingerMove => "● ● ● ●  4-finger movement", _ => "Spread thumb + 2 fingertips tap"
    };
    private static string ActionTitle(HandGestureAction action) => action switch
    { HandGestureAction.None => "None", HandGestureAction.Pointer => "Move Pointer", HandGestureAction.PrimaryDrag => "Drag / Select", HandGestureAction.Scroll => "Scroll / Pan",
        HandGestureAction.PrimaryClick => "Primary Click", HandGestureAction.DoubleClick => "Double-Click", _ => "Secondary Click" };
}
