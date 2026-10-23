using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace GlassToKey;

// Mac GestureSidebar / GestureInspectorPanel, using Windows output actions.
internal sealed class HandGesturePanel : StackPanel
{
    private UserSettings _settings;
    private readonly Action _changed;
    private readonly StackPanel _rows = new();
    private readonly TextBlock _status = new() { TextWrapping=TextWrapping.Wrap, FontSize=11, Margin=new(0,8,0,0) };
    private readonly HashSet<string> _expanded = ["2-main"];
    private readonly RadioButton[] _scopeButtons = new RadioButton[3];
    private HandGestureScope _scope = HandGestureScope.Both;
    private bool _refreshing;
    private static readonly Brush TextColor = new SolidColorBrush(Color.FromRgb(207,215,220));
    private static readonly Brush Secondary = new SolidColorBrush(Color.FromRgb(143,182,207));
    internal HandGestureScope EditingScope
    {
        get => _scope;
        set { _scope=value; _scopeButtons[(int)value].IsChecked=true; Rebuild(); }
    }
    public HandGesturePanel(UserSettings settings, Action changed)
    {
        _settings=settings; _changed=changed; SetValue(System.Windows.Documents.TextElement.ForegroundProperty,TextColor);
        var header=new DockPanel { LastChildFill=false, Margin=new(0,0,0,12) };
        header.Children.Add(new TextBlock { Text="Gestures", FontSize=15, FontWeight=FontWeights.SemiBold, VerticalAlignment=VerticalAlignment.Center });
        var scopes=new UniformGrid { Rows=1, Width=190 };
        DockPanel.SetDock(scopes,Dock.Right); header.Children.Add(scopes);
        foreach (var scope in Enum.GetValues<HandGestureScope>())
        {
            var button=new RadioButton { Content=scope.ToString(), GroupName="GestureScope"+GetHashCode(),
                IsChecked=scope==_scope, Foreground=TextColor, Padding=new(4), VerticalContentAlignment=VerticalAlignment.Center };
            button.SetResourceReference(StyleProperty,"GestureScopeButtonStyle");
            button.Checked += (_,_) => { if (_scope!=scope) { _scope=scope; Rebuild(); } };
            _scopeButtons[(int)scope]=button; scopes.Children.Add(button);
        }
        Children.Add(header); Children.Add(_rows);
        Children.Add(Note("Use Mouse Takeover for gesture output. Lift all fingers after edits. Ctrl+Alt+R releases takeover. Disable native Windows 3/4-finger actions to prevent conflicts."));
        Children.Add(Note("Apple acceleration drives pointer and drag. Scroll uses high-resolution wheel/pan with momentum; Zoom uses Ctrl+wheel and depends on the target app."));
        Children.Add(_status); Rebuild();
    }
    public void SetStatus(string text) { if (_status.Text!=text) _status.Text=text; }
    public void Refresh(UserSettings settings) { _settings=settings; Rebuild(); }
    private static TextBlock Note(string text) => new() { Text=text, TextWrapping=TextWrapping.Wrap, Foreground=Secondary, FontSize=11, Margin=new(0,8,0,0) };
    private void Rebuild()
    {
        if (_refreshing) return;
        _refreshing=true;
        try
        {
            _settings.HandGesturesV1 ??= new(); _settings.HandGesturesV1.Normalize(); _rows.Children.Clear();
            for (int count=1; count<=5; count++)
            {
                var group=new StackPanel { Margin=new(0,0,0,16) };
                var heading=new StackPanel { Orientation=Orientation.Horizontal, Margin=new(0,0,0,8) };
                heading.Children.Add(new GestureChordDiagram(count,_scope==HandGestureScope.Right,false));
                heading.Children.Add(new TextBlock { Text=count==1 ? "1 finger" : $"{count} fingers", FontSize=14, FontWeight=FontWeights.SemiBold, VerticalAlignment=VerticalAlignment.Center, Margin=new(8,0,8,0) });
                if (_scope==HandGestureScope.Both) heading.Children.Add(new GestureChordDiagram(count,true,false));
                group.Children.Add(heading);
                HandGestureTrigger[] main = count switch
                {
                    1 => [HandGestureTrigger.OneFingerForce],
                    2 => [HandGestureTrigger.TwoFingerTap,HandGestureTrigger.TwoFingerForce,HandGestureTrigger.TwoFingerMove],
                    3 => [HandGestureTrigger.ThreeFingerTap,HandGestureTrigger.ThreeFingerForce,HandGestureTrigger.ThreeFingerMove],
                    4 => [HandGestureTrigger.FourFingerMove,HandGestureTrigger.FourFingerForce],
                    _ => [HandGestureTrigger.FiveFingerForce]
                };
                AddSection(group,$"{count}-main",count is 1 or 5 ? "Force Click" : count==4 ? "Move and Force Click" : "Tap and Move",main);
                if (count>=2) AddSection(group,$"{count}-shape","Pinch and Spread",[PerHandGestureSettings.Pinch(count)!.Value,PerHandGestureSettings.Pinch(count,true)!.Value]);
                _rows.Children.Add(group);
            }
            var thumb=new StackPanel();
            var thumbHeader=new StackPanel { Orientation=Orientation.Horizontal };
            thumbHeader.Children.Add(new GestureChordDiagram(3,_scope==HandGestureScope.Right,true));
            thumbHeader.Children.Add(new TextBlock { Text="Thumb + 2 fingers", FontWeight=FontWeights.SemiBold, FontSize=14, Margin=new(8,0,0,0), VerticalAlignment=VerticalAlignment.Center });
            thumb.Children.Add(thumbHeader);
            if (_scope==HandGestureScope.Both) thumbHeader.Children.Add(new GestureChordDiagram(3,true,true) { Margin=new(8,0,0,0) });
            AddSection(thumb,"thumb","Tap",[HandGestureTrigger.ThumbTwoTap]); _rows.Children.Add(thumb);
            _rows.Children.Add(Note(_scope==HandGestureScope.Both ? "Editing both trackpads" : $"Editing the {_scope.ToString().ToLowerInvariant()} trackpad"));
        }
        finally { _refreshing=false; }
    }
    private void AddSection(StackPanel parent, string id, string title, HandGestureTrigger[] triggers)
    {
        var content=new StackPanel { Margin=new(12,6,4,8) };
        foreach (var trigger in triggers) AddAction(content,trigger);
        bool uses(HandGestureAction action) => triggers.Any(t => (_scope!=HandGestureScope.Right && _settings.HandGesturesV1.Left.Get(t)==action)
            || (_scope!=HandGestureScope.Left && _settings.HandGesturesV1.Right.Get(t)==action));
        if (uses(HandGestureAction.Pointer) || uses(HandGestureAction.PrimaryDrag)) AddGain(content,"Pointer sensitivity",0);
        if (uses(HandGestureAction.Scroll)) { AddGain(content,"Scroll sensitivity",1); AddNaturalScrolling(content); }
        if (uses(HandGestureAction.Zoom)) AddGain(content,"Zoom sensitivity",2);
        if (triggers.Any(t=>t>=HandGestureTrigger.OneFingerForce)) content.Children.Add(Note("Force click requires reported pressure P ≥ 130. It fires once until all fingers lift. Pressure-free decoders cannot trigger it; Windows pressure feel still needs testing."));
        if (triggers.Contains(HandGestureTrigger.ThreeFingerMove)) content.Children.Add(Note("Drag requires a compact fingertip row. With four-finger Scroll assigned, drag waits 120 ms for the fourth finger."));
        if (triggers.Contains(HandGestureTrigger.ThumbTwoTap)) content.Children.Add(Note("Unavailable with current Windows reports: no thumb identity. The assignment is saved; unknown three-contact taps use 3-finger tap."));
        if (triggers.Any(PerHandGestureSettings.IsPinch)) content.Children.Add(Note("Pinch moves inward; Spread moves outward. The selected action stays latched until all fingers lift, including direction reversals."));
        var expander=new Expander { Header=title, Content=new Border { Background=new SolidColorBrush(Color.FromRgb(23,29,34)), CornerRadius=new(8), Child=content },
            IsExpanded=_expanded.Contains(id), Foreground=TextColor, Margin=new(0,4,0,4) };
        expander.SetResourceReference(StyleProperty,"GestureSectionStyle");
        expander.Expanded += (_,_) => _expanded.Add(id);
        expander.Collapsed += (_,_) => _expanded.Remove(id);
        parent.Children.Add(expander);
    }
    private void AddAction(StackPanel parent, HandGestureTrigger trigger)
    {
        parent.Children.Add(new TextBlock { Text=Title(trigger), FontSize=12, FontWeight=FontWeights.Medium, Margin=new(0,8,0,4), Foreground=Secondary });
        var left=_settings.HandGesturesV1.Left.Get(trigger); var right=_settings.HandGesturesV1.Right.Get(trigger);
        HandGestureAction? value=_scope==HandGestureScope.Left ? left : _scope==HandGestureScope.Right ? right : left==right ? left : null;
        var options=Enum.GetValues<HandGestureAction>().Where(a=>PerHandGestureSettings.Allows(trigger,a)).Select(a=>new ActionOption(a,ActionTitle(a))).ToList();
        if (value==null) options.Insert(0,new(null,"Mixed"));
        var combo=new ComboBox { Tag=trigger, ItemsSource=options, DisplayMemberPath=nameof(ActionOption.Title), SelectedItem=options.First(o=>o.Action==value), Height=26 };
        System.Windows.Automation.AutomationProperties.SetName(combo,Title(trigger));
        combo.SelectionChanged += (_,_) =>
        {
            if (_refreshing || combo.SelectedItem is not ActionOption { Action:{} action }) return;
            ApplyToScope(hand=>hand.Set(trigger,action)); _changed(); Rebuild();
        };
        parent.Children.Add(combo);
        if (value==null) parent.Children.Add(Note($"Left: {ActionTitle(left)} · Right: {ActionTitle(right)}"));
    }
    private void ApplyToScope(Action<PerHandGestureSettings> apply)
    {
        if (_scope!=HandGestureScope.Right) apply(_settings.HandGesturesV1.Left);
        if (_scope!=HandGestureScope.Left) apply(_settings.HandGesturesV1.Right);
    }
    private void AddNaturalScrolling(StackPanel parent)
    {
        bool left=_settings.HandGesturesV1.Left.NaturalScrolling, right=_settings.HandGesturesV1.Right.NaturalScrolling;
        bool? value=_scope==HandGestureScope.Left ? left : _scope==HandGestureScope.Right ? right : left==right ? left : null;
        var check=new CheckBox { Content="Natural scrolling", IsThreeState=true, IsChecked=value, Foreground=TextColor, Margin=new(0,10,0,0), ToolTip="Content follows your fingers. Uncheck to reverse both axes and momentum." };
        check.Click += (_,_) => { if (_refreshing) return; bool enabled=value!=true; check.IsChecked=enabled; ApplyToScope(hand=>hand.NaturalScrolling=enabled); _changed(); Rebuild(); };
        parent.Children.Add(check);
    }
    private void AddGain(StackPanel parent, string title, int kind)
    {
        double get(PerHandGestureSettings h) => kind==0 ? h.PointerSensitivity : kind==1 ? h.ScrollSensitivity : h.ZoomSensitivity;
        double left=get(_settings.HandGesturesV1.Left), right=get(_settings.HandGesturesV1.Right);
        double? value=_scope==HandGestureScope.Left ? left : _scope==HandGestureScope.Right ? right : left==right ? left : null;
        var label=new TextBlock { Text=value.HasValue ? $"{title} · {value:0.00}×" : $"{title} · Mixed · L {left:0.00}× / R {right:0.00}×", FontSize=11, Margin=new(0,12,0,4) };
        parent.Children.Add(label);
        var slider=new Slider { Tag=kind, Minimum=.25, Maximum=2, Value=value ?? left, SmallChange=.01, LargeChange=.25,
            TickFrequency=.01, IsSnapToTickEnabled=true, IsMoveToPointEnabled=true, Height=24 };
        System.Windows.Automation.AutomationProperties.SetName(slider,title);
        slider.ValueChanged += (_,_) =>
        {
            if (_refreshing) return;
            double gain=Math.Round(slider.Value,2); label.Text=$"{title} · {gain:0.00}×";
            ApplyToScope(hand=> { if (kind==0) hand.PointerSensitivity=gain; else if (kind==1) hand.ScrollSensitivity=gain; else hand.ZoomSensitivity=gain; });
            _refreshing=true; try { _changed(); } finally { _refreshing=false; }
        };
        slider.AddHandler(Thumb.DragCompletedEvent,new DragCompletedEventHandler((_,_)=>Rebuild()));
        slider.LostKeyboardFocus += (_,_)=>Rebuild();
        parent.Children.Add(slider);
    }
    private sealed record ActionOption(HandGestureAction? Action, string Title);
    internal static string Title(HandGestureTrigger trigger)
    {
        if (trigger>=HandGestureTrigger.OneFingerForce) return $"{(int)trigger-(int)HandGestureTrigger.OneFingerForce+1}-finger force click";
        if (PerHandGestureSettings.IsPinch(trigger))
        {
            bool spread=trigger>=HandGestureTrigger.TwoFingerSpread;
            int count=(int)trigger-(int)(spread ? HandGestureTrigger.TwoFingerSpread : HandGestureTrigger.TwoFingerPinch)+2;
            return $"{count}-finger {(spread ? "spread" : "pinch")}";
        }
        return trigger switch { HandGestureTrigger.TwoFingerMove=>"2-finger movement", HandGestureTrigger.TwoFingerTap=>"2-finger tap",
            HandGestureTrigger.ThreeFingerMove=>"3-finger movement", HandGestureTrigger.ThreeFingerTap=>"3-finger tap",
            HandGestureTrigger.FourFingerMove=>"4-finger movement", _=>"Spread thumb + 2 fingertips tap" };
    }
    internal static string ActionTitle(HandGestureAction action) => action switch
    {
        HandGestureAction.None=>"None", HandGestureAction.Pointer=>"Move Pointer", HandGestureAction.PrimaryDrag=>"Drag / Select", HandGestureAction.Scroll=>"Scroll / Pan",
        HandGestureAction.PrimaryClick=>"Primary Click", HandGestureAction.DoubleClick=>"Double-Click", HandGestureAction.SecondaryClick=>"Secondary Click",
        HandGestureAction.Zoom=>"Zoom", HandGestureAction.NotificationCenter=>"Notification Center", HandGestureAction.TaskView=>"Task View",
        HandGestureAction.StartMenu=>"Start Menu", HandGestureAction.ShowDesktop=>"Show Desktop", _=>"None"
    };
}

// Diagrammatic anatomy only: these colors never assert live PTP finger identities.
internal sealed class GestureChordDiagram(int count, bool right, bool thumb) : FrameworkElement
{
    private static readonly Brush[] Colors = [new SolidColorBrush(Color.FromRgb(242,115,13)),new SolidColorBrush(Color.FromRgb(26,115,242)),
        new SolidColorBrush(Color.FromRgb(26,179,77)),new SolidColorBrush(Color.FromRgb(166,64,217)),new SolidColorBrush(Color.FromRgb(242,51,140))];
    protected override Size MeasureOverride(Size availableSize) => new(48,28);
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        double[] x=[.12,.3,.5,.7,.88], y=[.8,.36,.2,.3,.49];
        for (int i=0; i<5; i++)
        {
            bool active=thumb ? i is 0 or 2 or 3 : count==5 || (i>0 && i<=count);
            dc.DrawEllipse(active ? Colors[i] : null,new Pen(Colors[i],1),new Point((right ? x[i] : 1-x[i])*48,y[i]*28),2.8,2.8);
        }
    }
}
