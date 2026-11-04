using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace AppleMagicTouchstream;

/// <summary>Focused native text editing; practice never observes or posts global input.</summary>
public sealed class TypingPracticePanel : StackPanel
{
    private static readonly Brush Muted = new SolidColorBrush(Color.FromRgb(139, 148, 158));
    private static readonly Brush Good = new SolidColorBrush(Color.FromRgb(87, 199, 133));
    private static readonly Brush Bad = new SolidColorBrush(Color.FromRgb(255, 123, 114));
    private readonly ComboBox _area = new() { ItemsSource = new[] { "Free type", "Practice" }, SelectedIndex = 0, Width = 116 };
    private readonly ComboBox _mode = new() { ItemsSource = new[] { "Words", "Steno drills", "Custom" }, SelectedIndex = 0, Width = 130 };
    private readonly ComboBox _count = new() { ItemsSource = new[] { 10, 25, 50, 100 }, SelectedItem = 25, Width = 64 };
    private readonly Button _restart = new() { Content = "New drill", Padding = new Thickness(10, 4, 10, 4) };
    private readonly Border _freeHost = new();
    private readonly StackPanel _practice = new() { Visibility = Visibility.Collapsed };
    private readonly TextBox _custom = new() { MaxLength = 20500, Visibility = Visibility.Collapsed, Margin = new Thickness(0, 0, 0, 8) };
    private readonly TextBlock _prompt = new() { TextWrapping = TextWrapping.Wrap, FontFamily = new FontFamily("Consolas"), FontSize = 18, LineHeight = 26, IsHitTestVisible = false };
    private readonly TextBox _input = new()
    {
        Background = Brushes.Transparent, Foreground = Brushes.Transparent, CaretBrush = Brushes.Transparent,
        SelectionBrush = Brushes.Transparent, BorderThickness = new Thickness(0), Padding = new Thickness(0),
        AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontFamily = new FontFamily("Consolas"), FontSize = 18,
        VerticalContentAlignment = VerticalAlignment.Top, MinHeight = 52
    };
    private readonly ProgressBar _progress = new() { Minimum = 0, Maximum = 1, Height = 4, Margin = new Thickness(0, 8, 0, 8) };
    private readonly TextBlock _metrics = new() { Foreground = Muted, TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _help = new() { Foreground = Muted, FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) };
    private readonly TextBlock _customHelp = new() { Text = "Edit the word list, then choose New drill.", Foreground = Muted, Visibility = Visibility.Collapsed, Margin = new Thickness(0, 0, 0, 8) };
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    private TypingPracticeSession _session = new("");
    internal TypingPracticeSession Session => _session;
    internal TextBox PracticeInput => _input;
    internal ComboBox AreaSelector => _area;
    internal ComboBox ModeSelector => _mode;
    internal TextBox CustomInput => _custom;
    internal Button NewDrillButton => _restart;
    private bool Practicing => _area.SelectedIndex == 1;

    // Keep the window's existing named TypingTestBox and its text intact.
    public UIElement? FreeInput { get => _freeHost.Child; set => _freeHost.Child = value; }

    public TypingPracticePanel()
    {
        var header = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
        foreach (var control in new FrameworkElement[] { _area, _mode, _count, _restart })
        {
            control.Margin = new Thickness(0, 0, 8, 4);
            header.Children.Add(control);
        }
        Children.Add(header); Children.Add(_freeHost); Children.Add(_practice);
        _practice.Children.Add(_custom); _practice.Children.Add(_customHelp);
        var promptHost = new Grid { MinHeight = 52 };
        // Input and display share a viewport so long rounds scroll together.
        TextBlock.SetLineHeight(_input, 26);
        promptHost.Children.Add(_prompt); promptHost.Children.Add(_input);
        var promptScroll = new ScrollViewer { Content = promptHost, MaxHeight = 180, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        _practice.Children.Add(promptScroll); _practice.Children.Add(_progress);
        _practice.Children.Add(_metrics); _practice.Children.Add(_help);
        AutomationProperties.SetName(_area, "Typing area");
        AutomationProperties.SetName(_mode, "Practice mode");
        AutomationProperties.SetName(_count, "Number of words");
        AutomationProperties.SetName(_custom, "Words to practice, separated by spaces");
        AutomationProperties.SetName(_input, "Practice input");
        AutomationProperties.SetName(_progress, "Practice progress");
        SpellCheck.SetIsEnabled(_input, false);
        _input.ToolTip = "Click the prompt and type. Backspace and translated steno corrections work here.";
        _input.TextChanged += (_, _) =>
        {
            _session.Update(_input.Text, DateTimeOffset.UtcNow);
            if (_input.Text != _session.Input)
            {
                _input.Text = _session.Input;
                _input.CaretIndex = _input.Text.Length;
            }
            Refresh();
        };
        _input.PreviewMouseLeftButtonDown += (_, args) =>
        {
            _input.Focus(); _input.CaretIndex = _input.Text.Length; args.Handled = true;
        };
        _custom.TextChanged += (_, _) => UpdateRestart();
        _custom.PreviewKeyDown += (_, args) => { if (args.Key == Key.Enter && _restart.IsEnabled) { Restart(); args.Handled = true; } };
        _area.SelectionChanged += (_, _) =>
        {
            UpdateVisibility();
            if (Practicing && _session.Prompt.Length == 0) Restart();
        };
        _mode.SelectionChanged += (_, _) => { UpdateVisibility(); Restart(); };
        _count.SelectionChanged += (_, _) => Restart();
        _restart.Click += (_, _) => Restart();
        _timer.Tick += (_, _) => RefreshMetrics();
        Loaded += (_, _) => UpdateTimer();
        Unloaded += (_, _) => _timer.Stop();
        IsVisibleChanged += (_, _) => UpdateTimer();
        UpdateVisibility();
    }

    private void UpdateVisibility()
    {
        _freeHost.Visibility = Practicing ? Visibility.Collapsed : Visibility.Visible;
        _practice.Visibility = Practicing ? Visibility.Visible : Visibility.Collapsed;
        foreach (var control in new UIElement[] { _mode, _count, _restart }) control.Visibility = _practice.Visibility;
        _custom.Visibility = _customHelp.Visibility = _mode.SelectedIndex == 2 ? Visibility.Visible : Visibility.Collapsed;
        UpdateRestart(); UpdateTimer();
    }
    private void UpdateRestart() => _restart.IsEnabled = _mode.SelectedIndex != 2 || TypingPracticeSession.Words(_custom.Text).Length > 0;
    private void UpdateTimer()
    {
        if (IsLoaded && IsVisible && Practicing && _session.StartedAt != null && _session.FinishedAt == null) _timer.Start();
        else _timer.Stop();
    }
    internal void Restart()
    {
        var mode = (TypingPracticeSession.Mode)_mode.SelectedIndex;
        _session = new(TypingPracticeSession.Generate(mode, (int)_count.SelectedItem, _custom.Text, Random.Shared), mode == TypingPracticeSession.Mode.Steno);
        _input.Text = ""; _input.IsReadOnly = false;
        Refresh();
        if (Practicing && IsVisible && _session.Prompt.Length > 0) _input.Focus();
    }
    private void Refresh()
    {
        var input = TypingPracticeSession.Characters(_session.ComparisonInput);
        var compared = TypingPracticeSession.Characters(_session.Compare(_session.Prompt));
        _prompt.Inlines.Clear();
        var characters = TypingPracticeSession.Characters(_session.Prompt);
        for (int i = 0; i < characters.Length; ++i)
            _prompt.Inlines.Add(new Run(characters[i]) { Foreground = i < input.Length ? input[i] == compared[i] ? Good : Bad : Muted });
        if (_session.Prompt.Length == 0) _prompt.Inlines.Add(new Run("Add some words to create a drill.") { Foreground = Muted });
        AutomationProperties.SetName(_prompt, "Practice prompt: " + _session.Prompt);
        _input.IsReadOnly = _session.FinishedAt != null || _session.Prompt.Length == 0;
        _progress.Value = _session.Progress;
        _help.Text = _session.IgnoresCase
            ? "Use translated steno output here. Capitalization is ignored; corrections and backspaces update the score."
            : "Click the prompt and type. Corrections are allowed; WPM and accuracy reflect your current text.";
        RefreshMetrics(); UpdateTimer();
    }
    private void RefreshMetrics()
    {
        var now = DateTimeOffset.UtcNow;
        string status = _session.FinishedAt != null ? "Complete!" : _session.StartedAt == null ? "Start typing to begin" : "Keep going";
        _metrics.Text = $"{_session.Wpm(now):0} WPM     {_session.Accuracy:0}% accuracy     {_session.Elapsed(now):0}s     {status}";
    }
}
