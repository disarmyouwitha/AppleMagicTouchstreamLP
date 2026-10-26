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
    private readonly HashSet<string> _expanded = ["2-main", "3-main", "4-main", "5-main", "1-main", "thumb", "corners", "2-shape", "3-shape", "4-shape", "5-shape"];
    private readonly RadioButton[] _scopeButtons = new RadioButton[3];
    private HandGestureScope _scope = HandGestureScope.Left;
    private readonly ListBox _navigation = new() { BorderThickness=new(0), Background=Brushes.Transparent, Foreground=TextColor, MinWidth=105 };
    private readonly CheckBox _mirror = new() { Content="Mirror Edit", Foreground=TextColor, Margin=new(0,0,0,10) };
    private string _page = "2-main";
    internal bool MirrorEdits { get => _mirror.IsChecked == true; set => _mirror.IsChecked=value; }
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
        Children.Add(header);
        _mirror.Checked += (_,_) => Rebuild(); _mirror.Unchecked += (_,_) => Rebuild();
        Children.Add(_mirror);
        var workspace = new Grid();
        workspace.ColumnDefinitions.Add(new() { Width=new(132), MinWidth=105 });
        workspace.ColumnDefinitions.Add(new() { Width=new(6) });
        workspace.ColumnDefinitions.Add(new() { Width=new(1,GridUnitType.Star), MinWidth=170 });
        workspace.Children.Add(_navigation);
        var splitter = new GridSplitter { Width=5, HorizontalAlignment=HorizontalAlignment.Stretch, Background=new SolidColorBrush(Color.FromRgb(43,47,51)), ResizeDirection=GridResizeDirection.Columns, ResizeBehavior=GridResizeBehavior.PreviousAndNext };
        Grid.SetColumn(splitter,1); workspace.Children.Add(splitter);
        _rows.Margin = new(10,0,0,0); Grid.SetColumn(_rows,2); workspace.Children.Add(_rows);
        _navigation.SelectionChanged += (_,_) =>
        {
            if (_refreshing || _navigation.SelectedItem is not ListBoxItem { Tag:string page }) return;
            _page=page; UpdatePageVisibility();
        };
        Children.Add(workspace);
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
            _settings.HandGesturesV1 ??= new(); _settings.HandGesturesV1.Normalize(); _rows.Children.Clear(); _navigation.Items.Clear();
            _mirror.IsEnabled = _scope != HandGestureScope.Both;
            if (_scope == HandGestureScope.Both)
            { BuildCoordinated(); UpdatePageVisibility(); return; }
            for (int count=1; count<=5; count++)
            {
                var group=new StackPanel { Tag=$"{count}-main", Margin=new(0,0,0,16) };
                AddPage($"{count}-main", $"{count} finger{(count==1 ? "" : "s")}\n{(count==1 ? "Force Click" : "Tap and Move")}");
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
                    4 => [HandGestureTrigger.FourFingerTap,HandGestureTrigger.FourFingerForce,HandGestureTrigger.FourFingerMove],
                    _ => [HandGestureTrigger.FiveFingerTap,HandGestureTrigger.FiveFingerForce,HandGestureTrigger.FiveFingerMove]
                };
                group.Children.Add(new GestureDemonstration(count,false,false));
                AddSection(group,$"{count}-main",count==1 ? "Force Click" : "Tap and Move",main);
                if (count>=2) AddHold(group,count);
                _rows.Children.Add(group);
                if (count>=2)
                {
                    var shape=new StackPanel { Tag=$"{count}-shape" };
                    AddPage($"{count}-shape",$"{count} fingers\nPinch / Spread");
                    shape.Children.Add(new GestureDemonstration(count,true,false));
                    AddSection(shape,$"{count}-shape","Pinch and Spread",[PerHandGestureSettings.Pinch(count)!.Value,PerHandGestureSettings.Pinch(count,true)!.Value]);
                    _rows.Children.Add(shape);
                }
            }
            var thumb=new StackPanel { Tag="thumb" }; AddPage("thumb","3 fingers\nThumb + 2");
            var thumbHeader=new StackPanel { Orientation=Orientation.Horizontal };
            thumbHeader.Children.Add(new GestureChordDiagram(3,_scope==HandGestureScope.Right,true));
            thumbHeader.Children.Add(new TextBlock { Text="Thumb + 2 fingers", FontWeight=FontWeights.SemiBold, FontSize=14, Margin=new(8,0,0,0), VerticalAlignment=VerticalAlignment.Center });
            thumb.Children.Add(thumbHeader);
            if (_scope==HandGestureScope.Both) thumbHeader.Children.Add(new GestureChordDiagram(3,true,true) { Margin=new(8,0,0,0) });
            AddSection(thumb,"thumb","Tap",[HandGestureTrigger.ThumbTwoTap]); _rows.Children.Add(thumb);
            var corners=new StackPanel { Tag="corners" }; AddPage("corners","4 fingers\nOuter Corners");
            corners.Children.Add(new GestureDemonstration(4,false,true));
            corners.Children.Add(Note("Hold one contact in each of the four corners of this trackpad. Corner targets occupy the outer quarter of each axis."));
            AddDiscreteEditor(corners,"Hold", hand=>hand.CornerAction(HandCornerChord.OuterCorners), (hand,a)=>(hand.CornerHoldActions ??= new())[HandCornerChord.OuterCorners]=a,"CornerHold");
            AddMilliseconds(corners,"Hold threshold (ms)",hand=>hand.CornerMilliseconds(HandCornerChord.OuterCorners),(hand,v)=>(hand.CornerHoldThresholds ??= new())[HandCornerChord.OuterCorners]=v,100,5000);
            _rows.Children.Add(corners);
            UpdatePageVisibility();
        }
        finally { _refreshing=false; }
    }
    private void AddPage(string id,string title)
    {
        var item=new ListBoxItem { Tag=id, Content=new TextBlock { Text=title, TextWrapping=TextWrapping.Wrap, FontSize=11 }, Padding=new(6,8,4,8), Foreground=TextColor };
        _navigation.Items.Add(item);
        if (_page==id) _navigation.SelectedItem=item;
    }
    private void UpdatePageVisibility()
    {
        if (!_rows.Children.OfType<FrameworkElement>().Any(e=>Equals(e.Tag,_page)))
            _page=_rows.Children.OfType<FrameworkElement>().FirstOrDefault()?.Tag as string ?? "2-main";
        foreach (var row in _rows.Children.OfType<FrameworkElement>()) row.Visibility=Equals(row.Tag,_page) ? Visibility.Visible : Visibility.Collapsed;
        foreach (ListBoxItem item in _navigation.Items) if (Equals(item.Tag,_page)) { _navigation.SelectedItem=item; break; }
    }
    private void AddSection(StackPanel parent, string id, string title, HandGestureTrigger[] triggers)
    {
        var content=new StackPanel { Margin=new(12,6,4,8) };
        foreach (var trigger in triggers) AddAction(content,trigger);
        bool uses(HandGestureAction action) => triggers.Any(t => ((_scope!=HandGestureScope.Right || MirrorEdits) && _settings.HandGesturesV1.Left.Get(t)==action)
            || ((_scope!=HandGestureScope.Left || MirrorEdits) && _settings.HandGesturesV1.Right.Get(t)==action));
        if (uses(HandGestureAction.Pointer) || uses(HandGestureAction.PrimaryDrag)) AddGain(content,"Pointer sensitivity",0);
        if (uses(HandGestureAction.Scroll)) { AddGain(content,"Scroll sensitivity",1); AddNaturalScrolling(content); }
        if (uses(HandGestureAction.Zoom)) AddGain(content,"Zoom sensitivity",2);
        if (triggers.Any(PerHandGestureSettings.IsForce)) content.Children.Add(Note("Force click requires reported pressure P ≥ 130. It fires once until all fingers lift. Pressure-free decoders cannot trigger it; Windows pressure feel still needs testing."));
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
        HandGestureAction? value=MirrorEdits ? (left==right ? left : null) : _scope==HandGestureScope.Right ? right : left;
        var options=Enum.GetValues<HandGestureAction>().Where(a=>PerHandGestureSettings.Allows(trigger,a)).Select(a=>new ActionOption(a,ActionTitle(a))).ToList();
        if (value==null) options.Insert(0,new(null,"Mixed"));
        var combo=new ComboBox { Tag=trigger, ItemsSource=options, DisplayMemberPath=nameof(ActionOption.Title), SelectedItem=options.First(o=>o.Action==value), Height=26 };
        MakeSearchable(combo,options);
        System.Windows.Automation.AutomationProperties.SetName(combo,Title(trigger));
        combo.SelectionChanged += (_,_) =>
        {
            if (_refreshing || combo.SelectedItem is not ActionOption { Action:{} action }) return;
            if (action==HandGestureAction.Custom && !EditCustom(trigger.ToString())) { Rebuild(); return; }
            ApplyToScope(hand=>hand.Set(trigger,action)); _changed(); Rebuild();
        };
        parent.Children.Add(combo);
        if (value==HandGestureAction.Custom) AddCustomSummary(parent,trigger.ToString());
        if (PerHandGestureSettings.IsMovement(trigger)) AddDirections(parent,trigger);
        if (value==null) parent.Children.Add(Note($"Left: {ActionTitle(left)} · Right: {ActionTitle(right)}"));
    }
    private void ApplyToScope(Action<PerHandGestureSettings> apply)
    {
        if (_scope == HandGestureScope.Both) return;
        if (_scope==HandGestureScope.Left || MirrorEdits) apply(_settings.HandGesturesV1.Left);
        if (_scope==HandGestureScope.Right || MirrorEdits) apply(_settings.HandGesturesV1.Right);
    }
    private void AddNaturalScrolling(StackPanel parent)
    {
        bool left=_settings.HandGesturesV1.Left.NaturalScrolling, right=_settings.HandGesturesV1.Right.NaturalScrolling;
        bool? value=MirrorEdits ? (left==right ? left : null) : _scope==HandGestureScope.Right ? right : left;
        var check=new CheckBox { Content="Natural scrolling", IsThreeState=true, IsChecked=value, Foreground=TextColor, Margin=new(0,10,0,0), ToolTip="Content follows your fingers. Uncheck to reverse both axes and momentum." };
        check.Click += (_,_) => { if (_refreshing) return; bool enabled=value!=true; check.IsChecked=enabled; ApplyToScope(hand=>hand.NaturalScrolling=enabled); _changed(); Rebuild(); };
        parent.Children.Add(check);
    }
    private PerHandGestureSettings SelectedHand => _scope==HandGestureScope.Right ? _settings.HandGesturesV1.Right : _settings.HandGesturesV1.Left;
    private void AddHold(StackPanel parent,int count)
    {
        parent.Children.Add(Note("Hold fires once after the threshold. Keep the chord within 2 mm; lift all fingers to re-arm."));
        AddDiscreteEditor(parent,"Hold",h=>h.Hold(count),(h,a)=>(h.HoldActions ??= new())[count]=a,"Hold"+count);
        AddMilliseconds(parent,"Hold threshold (ms)",h=>h.HoldMilliseconds(count),(h,v)=>(h.HoldThresholds ??= new())[count]=v,100,5000);
    }
    private ComboBox ActionPicker(HandGestureAction value, Action<HandGestureAction> apply, string slot, bool coordinated=false)
    {
        var options=Enum.GetValues<HandGestureAction>().Where(PerHandGestureSettings.IsDiscrete)
            .Select(a=>new ActionOption(a,ActionTitle(a))).ToList();
        var combo=new ComboBox { ItemsSource=options, DisplayMemberPath=nameof(ActionOption.Title), SelectedItem=options.FirstOrDefault(o=>o.Action==value), MinHeight=28, MaxDropDownHeight=320, Margin=new(0,4,0,6) };
        combo.SelectionChanged += (_,_) => { if (!_refreshing && combo.SelectedItem is ActionOption { Action:{} a })
        { if (a==HandGestureAction.Custom && !EditCustom(slot,coordinated)) { Rebuild(); return; } apply(a); _changed(); Rebuild(); } };
        MakeSearchable(combo,options);
        return combo;
    }
    private void MakeSearchable(ComboBox combo,List<ActionOption> options)
    {
        combo.IsEditable=true; combo.IsTextSearchEnabled=false; combo.StaysOpenOnEdit=true;
        combo.ToolTip="Search actions, then choose an assignment";
        var view=new System.Windows.Data.ListCollectionView(options);
        var selected=combo.SelectedItem;
        combo.ItemsSource=view; combo.SelectedItem=selected;
        combo.AddHandler(TextBoxBase.TextChangedEvent,new TextChangedEventHandler((sender,e)=>
        {
            if (_refreshing || e.OriginalSource is not TextBox edit || !combo.IsKeyboardFocusWithin) return;
            string query=edit.Text;
            if (combo.SelectedItem is ActionOption current && current.Title==query) return;
            FilterActionOptions(combo,query);
            combo.IsDropDownOpen=true;
        }));
        combo.DropDownClosed += (_,_)=>
        {
            if (_refreshing || combo.SelectedItem!=null) return;
            _refreshing=true;
            try { view.Filter=null; combo.SelectedItem=selected; combo.Text=(selected as ActionOption)?.Title ?? ""; }
            finally { _refreshing=false; }
        };
    }
    internal void FilterActionOptions(ComboBox combo,string query)
    {
        bool previous=_refreshing; _refreshing=true;
        try
        {
            if (combo.ItemsSource is System.Windows.Data.ListCollectionView view)
                view.Filter=item=>item is ActionOption option && option.Title.Contains(query.Trim(),StringComparison.OrdinalIgnoreCase);
            combo.SelectedItem=null; combo.Text=query;
        }
        finally { _refreshing=previous; }
    }
    private void AddDiscreteEditor(StackPanel parent,string title,Func<PerHandGestureSettings,HandGestureAction> get,Action<PerHandGestureSettings,HandGestureAction> set,string slot)
    {
        parent.Children.Add(Note(title));
        parent.Children.Add(ActionPicker(get(SelectedHand),a=>ApplyToScope(h=>set(h,a)),slot));
        if (get(SelectedHand)==HandGestureAction.Custom) AddCustomSummary(parent,slot);
        if (MirrorEdits && get(_settings.HandGesturesV1.Left)!=get(_settings.HandGesturesV1.Right)) parent.Children.Add(Note("Mixed · choosing an action updates Left + Right"));
    }
    private bool EditCustom(string slot,bool coordinated=false)
    {
        string? current=coordinated ? _settings.HandGesturesV1.Coordinated.CustomActions.GetValueOrDefault(slot) : SelectedHand.CustomActions?.GetValueOrDefault(slot);
        var builder=new GestureActionBuilder(current);
        if (Window.GetWindow(this) is {} owner) { builder.Owner=owner; builder.Resources=owner.Resources; }
        if (builder.ShowDialog()!=true || builder.Assignment is not {} label) return false;
        if (coordinated) _settings.HandGesturesV1.Coordinated.CustomActions[slot]=label;
        else ApplyToScope(h=>(h.CustomActions ??= new())[slot]=label);
        return true;
    }
    private void AddCustomSummary(StackPanel parent,string slot,bool coordinated=false)
    {
        string? label=coordinated ? _settings.HandGesturesV1.Coordinated.CustomActions.GetValueOrDefault(slot) : SelectedHand.CustomActions?.GetValueOrDefault(slot);
        parent.Children.Add(Note(label==null ? "No custom assignment" : AppLaunchActionHelper.GetDisplayLabel(label)));
        var edit=new Button { Content="Edit in Action Builder…",Padding=new(8,4,8,4),Margin=new(0,2,0,8) };
        edit.Click += (_,_)=> { if (EditCustom(slot,coordinated)) { _changed(); Rebuild(); } }; parent.Children.Add(edit);
    }
    private void AddMilliseconds(StackPanel parent,string title,Func<PerHandGestureSettings,double> get,Action<PerHandGestureSettings,double> set,double minimum,double maximum)
        => AddNumber(parent,title,get(SelectedHand),v=> { ApplyToScope(h=>set(h,v)); _changed(); },minimum,maximum);
    private void AddNumber(StackPanel parent,string title,double value,Action<double> apply,double minimum,double maximum)
    {
        var row=new DockPanel { Margin=new(0,4,0,8) };
        var box=new TextBox { Text=value.ToString("0",System.Globalization.CultureInfo.InvariantCulture), Width=62, Margin=new(6,0,0,0), Padding=new(4) };
        System.Windows.Automation.AutomationProperties.SetName(box,title);
        DockPanel.SetDock(box,Dock.Right); row.Children.Add(box); row.Children.Add(Note(title)); parent.Children.Add(row);
        void commit()
        {
            if (_refreshing) return;
            if (double.TryParse(box.Text,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out double number) && double.IsFinite(number))
            { number=Math.Clamp(number,minimum,maximum); box.Text=number.ToString("0",System.Globalization.CultureInfo.InvariantCulture); apply(number); }
            else box.Text=value.ToString("0",System.Globalization.CultureInfo.InvariantCulture);
        }
        box.LostKeyboardFocus += (_,_)=>commit();
        box.KeyDown += (_,e)=> { if (e.Key==System.Windows.Input.Key.Enter) { commit(); e.Handled=true; } };
    }
    private void AddDirections(StackPanel parent,HandGestureTrigger trigger)
    {
        var config=SelectedHand.DirectionalMovement?.GetValueOrDefault(trigger) ?? new();
        bool? enabled=config.Enabled;
        if (MirrorEdits && (_settings.HandGesturesV1.Left.Directional(trigger)!=null)!=(_settings.HandGesturesV1.Right.Directional(trigger)!=null)) enabled=null;
        var toggle=new CheckBox { Content="Directional movement", IsThreeState=true, IsChecked=enabled, Foreground=TextColor, Margin=new(0,6,0,6) };
        toggle.Click += (_,_)=>
        {
            bool next=enabled!=true;
            ApplyToScope(h=> { h.DirectionalMovement ??= new(); if (!h.DirectionalMovement.TryGetValue(trigger,out var item)) h.DirectionalMovement[trigger]=item=new(); item.Enabled=next; });
            _changed(); Rebuild();
        };
        parent.Children.Add(toggle);
        if (!config.Enabled) return;
        foreach (var direction in Enum.GetValues<HandMovementDirection>())
        {
            parent.Children.Add(Note(direction.ToString()));
            parent.Children.Add(ActionPicker(config.Get(direction),a=>ApplyToScope(h=>
            { h.DirectionalMovement ??= new(); if (!h.DirectionalMovement.TryGetValue(trigger,out var item)) h.DirectionalMovement[trigger]=item=new() { Enabled=true }; item.Actions[direction]=a; }),trigger+"/"+direction));
            if (config.Get(direction)==HandGestureAction.Custom) AddCustomSummary(parent,trigger+"/"+direction);
            AddNumber(parent,"Repeat ms (0 = once)",config.Repeat(direction),v=>
            {
                ApplyToScope(h=> { h.DirectionalMovement ??= new(); if (!h.DirectionalMovement.TryGetValue(trigger,out var item)) h.DirectionalMovement[trigger]=item=new() { Enabled=true }; item.RepeatMilliseconds[direction]=v; });
                _changed();
            },0,5000);
        }
        parent.Children.Add(Note("Move 3 mm to choose a direction. Repeating also requires continued travel; holding still does not repeat."));
    }
    private void BuildCoordinated()
    {
        _settings.HandGesturesV1.Coordinated ??= new();
        var settings=_settings.HandGesturesV1.Coordinated;
        foreach (var chord in Enum.GetValues<CoordinatedHandChord>())
        {
            string title=chord switch { CoordinatedHandChord.ThreeFingers=>"3 fingers / hand", CoordinatedHandChord.FourFingers=>"4 fingers / hand",
                CoordinatedHandChord.OuterCorners=>"Outer Corners", CoordinatedHandChord.InnerCorners=>"Inner Corners", CoordinatedHandChord.TopOuter=>"Top Outer Corners",
                CoordinatedHandChord.BottomOuter=>"Bottom Outer Corners", CoordinatedHandChord.TopInner=>"Top Inner Corners", _=>"Bottom Inner Corners" };
            string id="both-"+chord; AddPage(id,title);
            var content=new StackPanel { Tag=id }; content.Children.Add(new TextBlock { Text=title, Foreground=TextColor, FontWeight=FontWeights.SemiBold, FontSize=14 });
            content.Children.Add(Note("Both hands form one gesture on two different selected pads. Land within 80 ms; keep each chord still within 2 mm. Mirror Edit does not change these assignments."));
            if (chord is CoordinatedHandChord.ThreeFingers or CoordinatedHandChord.FourFingers)
            { content.Children.Add(Note("Tap")); content.Children.Add(ActionPicker(settings.Action(chord,false),a=>settings.TapActions[chord]=a,chord+"/Tap",true));
                if (settings.Action(chord,false)==HandGestureAction.Custom) AddCustomSummary(content,chord+"/Tap",true); }
            else content.Children.Add(Note(chord switch
            {
                CoordinatedHandChord.OuterCorners=>"Left pad: both left corners. Right pad: both right corners.",
                CoordinatedHandChord.InnerCorners=>"Left pad: both right corners. Right pad: both left corners.",
                CoordinatedHandChord.TopOuter=>"Left pad: top left. Right pad: top right.",
                CoordinatedHandChord.BottomOuter=>"Left pad: bottom left. Right pad: bottom right.",
                CoordinatedHandChord.TopInner=>"Left pad: top right. Right pad: top left.",
                _=>"Left pad: bottom right. Right pad: bottom left."
            }));
            content.Children.Add(Note("Hold")); content.Children.Add(ActionPicker(settings.Action(chord,true),a=>settings.HoldActions[chord]=a,chord+"/Hold",true));
            if (settings.Action(chord,true)==HandGestureAction.Custom) AddCustomSummary(content,chord+"/Hold",true);
            AddNumber(content,"Hold threshold (ms)",settings.Milliseconds(chord),v=> { settings.HoldThresholds[chord]=v; _changed(); },100,5000);
            content.Children.Add(Note("Lift both hands to re-arm. A tap must end within 500 ms; the hands must lift within 150 ms of each other."));
            _rows.Children.Add(content);
        }
    }
    private void AddGain(StackPanel parent, string title, int kind)
    {
        double get(PerHandGestureSettings h) => kind==0 ? h.PointerSensitivity : kind==1 ? h.ScrollSensitivity : h.ZoomSensitivity;
        double left=get(_settings.HandGesturesV1.Left), right=get(_settings.HandGesturesV1.Right);
        double? value=MirrorEdits ? (left==right ? left : null) : _scope==HandGestureScope.Right ? right : left;
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
        if (PerHandGestureSettings.IsForce(trigger)) return $"{(int)trigger-(int)HandGestureTrigger.OneFingerForce+1}-finger force click";
        if (PerHandGestureSettings.IsPinch(trigger))
        {
            bool spread=trigger>=HandGestureTrigger.TwoFingerSpread;
            int count=(int)trigger-(int)(spread ? HandGestureTrigger.TwoFingerSpread : HandGestureTrigger.TwoFingerPinch)+2;
            return $"{count}-finger {(spread ? "spread" : "pinch")}";
        }
        return trigger switch { HandGestureTrigger.TwoFingerMove=>"2-finger movement", HandGestureTrigger.TwoFingerTap=>"2-finger tap",
            HandGestureTrigger.ThreeFingerMove=>"3-finger movement", HandGestureTrigger.ThreeFingerTap=>"3-finger tap",
            HandGestureTrigger.FourFingerMove=>"4-finger movement", HandGestureTrigger.FourFingerTap=>"4-finger tap",
            HandGestureTrigger.FiveFingerMove=>"5-finger movement", HandGestureTrigger.FiveFingerTap=>"5-finger tap", _=>"Spread thumb + 2 fingertips tap" };
    }
    internal static string ActionTitle(HandGestureAction action) => action switch
    {
        HandGestureAction.None=>"None", HandGestureAction.Pointer=>"Move Pointer", HandGestureAction.PrimaryDrag=>"Drag / Select", HandGestureAction.Scroll=>"Scroll / Pan",
        HandGestureAction.PrimaryClick=>"Primary Click", HandGestureAction.DoubleClick=>"Double-Click", HandGestureAction.SecondaryClick=>"Secondary Click",
        HandGestureAction.Zoom=>"Zoom", HandGestureAction.NotificationCenter=>"Notification Center", HandGestureAction.TaskView=>"Task View",
        HandGestureAction.StartMenu=>"Start Menu", HandGestureAction.ShowDesktop=>"Show Desktop", HandGestureAction.OpenConfig=>"Open Config",
        HandGestureAction.ScrollUp=>"Scroll Up", HandGestureAction.ScrollDown=>"Scroll Down", HandGestureAction.PanLeft=>"Pan Left", HandGestureAction.PanRight=>"Pan Right",
        HandGestureAction.SelectAll=>"Select All", HandGestureAction.Voice=>"Voice (Windows dictation)", HandGestureAction.Custom=>"Shortcut / App / File / URL…", _=>action.ToString()
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
