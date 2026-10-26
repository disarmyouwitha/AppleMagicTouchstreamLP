using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace GlassToKey;

// Mac GestureAssignmentWorkspace: navigation | assignment cards | Action inspector.
// This owns the full Gestures workspace, never the keyboard's inspector frame.
internal sealed class HandGesturePanel : Grid
{
    private UserSettings _settings;
    private readonly Action _changed;
    private readonly ListBox _navigation=new() { Background=Brushes.Transparent,BorderThickness=new(0) };
    private readonly StackPanel _pageContent=new(), _inspector=new();
    private readonly CheckBox _mirror=new() { Content="Mirror Edit",Margin=new(0,8,0,12) };
    private readonly TextBox _search=new() { Margin=new(0,0,0,12),MinHeight=28,ToolTip="Search gestures or assigned actions" };
    private readonly TextBlock _status=new() { TextWrapping=TextWrapping.Wrap,FontSize=11,Foreground=Secondary };
    private readonly RadioButton[] _scopes=new RadioButton[3];
    private readonly Dictionary<string,Slot> _slots=new();
    private readonly List<Page> _pages=new();
    private HandGestureScope _scope=HandGestureScope.Left;
    private string _page="2-main", _selected="TwoFingerMove", _independentPage="2-main", _bothPage="both-OuterCorners";
    private bool _refreshing,_showBuilder;
    private static readonly Brush TextColor=new SolidColorBrush(Color.FromRgb(225,231,235));
    private static readonly Brush Secondary=new SolidColorBrush(Color.FromRgb(151,169,182));
    private sealed record Page(string Id,string Group,string Title,int Count=0,bool Shape=false,bool Corners=false,CoordinatedHandChord? Chord=null);
    private sealed record Slot(string Key,string Title,HandGestureTrigger? Trigger=null,int HoldCount=0,bool Corner=false,HandMovementDirection? Direction=null,CoordinatedHandChord? Chord=null,bool Hold=false)
    { public bool IsHold=>HoldCount>0 || Corner || Hold; }
    internal HandGestureScope EditingScope { get=>_scope; set=>SetScope(value); }
    internal bool MirrorEdits { get=>_mirror.IsChecked==true; set=>_mirror.IsChecked=value; }
    internal string SelectedSlot=>_selected;
    internal void SelectPage(string page) { _page=page; _selected=""; Rebuild(); }
    internal void SelectSlot(string key) { if(_slots.ContainsKey(key)) { _selected=key; _showBuilder=false; Rebuild(); } }
    public HandGesturePanel(UserSettings settings,Action changed)
    {
        _settings=settings; _changed=changed;
        SetValue(System.Windows.Documents.TextElement.ForegroundProperty,TextColor);
        ColumnDefinitions.Add(new() { Width=new(250),MinWidth=200 }); ColumnDefinitions.Add(new() { Width=new(6) });
        ColumnDefinitions.Add(new() { Width=new(1,GridUnitType.Star),MinWidth=240 }); ColumnDefinitions.Add(new() { Width=new(6) });
        ColumnDefinitions.Add(new() { Width=new(320),MinWidth=260 });
        var navigation=new Grid { Margin=new(12) };
        navigation.RowDefinitions.Add(new() { Height=GridLength.Auto }); navigation.RowDefinitions.Add(new() { Height=new(1,GridUnitType.Star) }); navigation.RowDefinitions.Add(new() { Height=GridLength.Auto });
        var controls=new StackPanel(); controls.Children.Add(Label("Gestures",20,true));
        var scopes=new UniformGrid { Rows=1,Margin=new(0,14,0,0) }; controls.Children.Add(scopes);
        foreach(var scope in Enum.GetValues<HandGestureScope>())
        {
            var button=new RadioButton { Content=scope.ToString(),GroupName="GestureHand"+GetHashCode(),Foreground=TextColor,IsChecked=scope==_scope };
            button.SetResourceReference(StyleProperty,"GestureScopeButtonStyle"); button.Checked+=(_,_)=>SetScope(scope);
            _scopes[(int)scope]=button; scopes.Children.Add(button);
        }
        controls.Children.Add(_mirror); controls.Children.Add(_search); navigation.Children.Add(controls);
        _search.Tag="Search gestures or actions"; _search.SetResourceReference(StyleProperty,"WatermarkTextBoxStyle");
        System.Windows.Automation.AutomationProperties.SetName(_search,"Search gestures or actions");
        Grid.SetRow(_navigation,1); navigation.Children.Add(_navigation);
        Grid.SetRow(_status,2); _status.Margin=new(0,12,0,0); navigation.Children.Add(_status); Children.Add(navigation);
        AddDivider(1); AddDivider(3);
        var pageScroll=new ScrollViewer { Content=_pageContent,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,Padding=new(22,12,22,20) };
        Grid.SetColumn(pageScroll,2); Children.Add(pageScroll);
        var actionScroll=new ScrollViewer { Content=_inspector,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,Padding=new(18,12,18,20),Background=new SolidColorBrush(Color.FromRgb(13,17,21)) };
        Grid.SetColumn(actionScroll,4); Children.Add(actionScroll);
        _mirror.Checked+=(_,_)=>Rebuild(); _mirror.Unchecked+=(_,_)=>Rebuild();
        _search.TextChanged+=(_,_)=>FilterNavigation();
        _navigation.SelectionChanged+=(_,_)=> { if(!_refreshing && _navigation.SelectedItem is ListBoxItem { Tag:Page page }) SelectPage(page.Id); };
        Rebuild();
    }
    private void AddDivider(int column)
    {
        var divider=new GridSplitter { Width=6,HorizontalAlignment=HorizontalAlignment.Stretch,ResizeDirection=GridResizeDirection.Columns,ResizeBehavior=GridResizeBehavior.PreviousAndNext,Background=new SolidColorBrush(Color.FromRgb(40,49,57)) };
        System.Windows.Automation.AutomationProperties.SetName(divider,column==1 ? "Gesture navigation width" : "Action inspector width"); Grid.SetColumn(divider,column); Children.Add(divider);
    }
    public void SetStatus(string text) { if(_status.Text!=text) _status.Text=text; }
    public void Refresh(UserSettings settings) { _settings=settings; Rebuild(); }
    private void SetScope(HandGestureScope value)
    {
        if(_scope==value) return;
        if(_scope==HandGestureScope.Both) _bothPage=_page; else _independentPage=_page;
        _scope=value; _page=value==HandGestureScope.Both ? _bothPage : _independentPage; _selected="";
        _scopes[(int)value].IsChecked=true; Rebuild();
    }
    private void Commit(Action action)
    { if(_refreshing) return; _refreshing=true; try { action(); _changed(); } finally { _refreshing=false; } Rebuild(); }
    private void Apply(Action<PerHandGestureSettings> action)
    { if(_scope==HandGestureScope.Both) return; if(_scope==HandGestureScope.Left || MirrorEdits) action(_settings.HandGesturesV1.Left); if(_scope==HandGestureScope.Right || MirrorEdits) action(_settings.HandGesturesV1.Right); }
    private PerHandGestureSettings Hand=>_scope==HandGestureScope.Right ? _settings.HandGesturesV1.Right : _settings.HandGesturesV1.Left;
    private static TextBlock Label(string text,double size=12,bool bold=false)=>new() { Text=text,FontSize=size,Foreground=TextColor,FontWeight=bold ? FontWeights.SemiBold : FontWeights.Normal,TextWrapping=TextWrapping.Wrap,Margin=new(0,0,0,8) };
    private static TextBlock Note(string text)=>new() { Text=text,Foreground=Secondary,FontSize=12,TextWrapping=TextWrapping.Wrap,Margin=new(0,4,0,12) };
    private void Rebuild()
    {
        if(_refreshing) return; _refreshing=true;
        try
        {
            _settings.HandGesturesV1.Normalize(); _mirror.IsEnabled=_scope!=HandGestureScope.Both;
            _pages.Clear(); _slots.Clear(); _pageContent.Children.Clear(); _inspector.Children.Clear(); _navigation.Items.Clear();
            if(_scope==HandGestureScope.Both)
                foreach(var entry in Enum.GetValues<CoordinatedHandChord>()) _pages.Add(new("both-"+entry,"COORDINATED TWO-HAND INPUT",ChordTitle(entry),Chord:entry));
            else
            {
                for(int count=1;count<=5;count++)
                {
                    _pages.Add(new($"{count}-main",$"{count} FINGER{(count==1 ? "" : "S")}",count==1 ? "Force Click" : "Tap and Move",count));
                    if(count>=2) _pages.Add(new($"{count}-shape",$"{count} FINGERS","Pinch and Spread",count,true));
                    if(count==3) _pages.Add(new("thumb","3 FINGERS","Thumb + 2",3));
                    if(count==4) _pages.Add(new("corners","4 FINGERS","Outer Corners",4,Corners:true));
                }
            }
            var page=_pages.FirstOrDefault(p=>p.Id==_page) ?? _pages[0]; _page=page.Id;
            if(_selected.Length==0) _selected=page.Chord is {} selectedChord ? selectedChord+"/"+(selectedChord is CoordinatedHandChord.ThreeFingers or CoordinatedHandChord.FourFingers ? "Tap" : "Hold")
                : page.Corners ? "CornerHold" : page.Id=="thumb" ? nameof(HandGestureTrigger.ThumbTwoTap) : page.Shape ? PerHandGestureSettings.Pinch(page.Count)!.Value.ToString()
                : page.Count==1 ? nameof(HandGestureTrigger.OneFingerForce) : PerHandGestureSettings.Movement(page.Count)!.Value.ToString();
            string? previousGroup=null;
            foreach(var item in _pages)
            {
                if(item.Group!=previousGroup) { _navigation.Items.Add(new ListBoxItem { Tag=item.Group,Content=Note(item.Group),IsHitTestVisible=false,Focusable=false,Padding=new(9,10,0,0) }); previousGroup=item.Group; }
                var row=new ListBoxItem { Tag=item,Content=Label(item.Title,13),Padding=new(10,7,10,1),Foreground=TextColor,Margin=new(0,0,0,3) };
                row.SetResourceReference(StyleProperty,"GestureNavigationItemStyle"); _navigation.Items.Add(row); if(item==page) _navigation.SelectedItem=row;
            }
            _pageContent.Children.Add(Note(_scope==HandGestureScope.Both ? "Gestures / Both hands" : $"Gestures / {ScopeTitle}"));
            var heading=new Grid(); heading.ColumnDefinitions.Add(new() { Width=new(1,GridUnitType.Star) }); heading.ColumnDefinitions.Add(new() { Width=new(180) });
            heading.RowDefinitions.Add(new() { Height=GridLength.Auto }); heading.RowDefinitions.Add(new() { Height=GridLength.Auto });
            FrameworkElement demo=page.Chord is {} exampleChord ? new CoordinatedGestureDemonstration(exampleChord) : new GestureDemonstration(page.Count,page.Shape,page.Corners)
            { Holding=_selected.StartsWith("Hold") || page.Corners,Force=_selected.EndsWith("Force"),Tapping=_selected.EndsWith("Tap") };
            demo.Width=170; demo.Height=120; Grid.SetColumn(demo,1); heading.Children.Add(demo);
            var title=new StackPanel(); title.Children.Add(Label(page.Chord!=null ? page.Title : $"{page.Count} finger{(page.Count==1 ? "" : "s")}",25,true)); title.Children.Add(Note(page.Title)); heading.Children.Add(title);
            heading.SizeChanged+=(_,e)=> { bool compact=e.NewSize.Width<380; Grid.SetColumnSpan(title,compact ? 2 : 1); Grid.SetColumn(demo,compact ? 0 : 1); Grid.SetRow(demo,compact ? 1 : 0); Grid.SetColumnSpan(demo,compact ? 2 : 1); };
            _pageContent.Children.Add(heading);
            _pageContent.Children.Add(new Separator { Margin=new(0,14,0,18) }); _pageContent.Children.Add(Note("ASSIGNMENTS"));
            if(page.Chord is {} chord)
            {
                _pageContent.Children.Add(Note(Placement(chord)));
                var cards=new UniformGrid { Columns=2 }; _pageContent.Children.Add(cards);
                if(chord is CoordinatedHandChord.ThreeFingers or CoordinatedHandChord.FourFingers) AddCard(cards,new(chord+"/Tap","Tap",Chord:chord));
                AddCard(cards,new(chord+"/Hold","Hold",Chord:chord,Hold:true));
            }
            else if(page.Corners) AddCard(_pageContent,new("CornerHold","Hold",Corner:true));
            else if(page.Shape)
            { var cards=new UniformGrid { Columns=2 }; _pageContent.Children.Add(cards); AddCard(cards,TriggerSlot(PerHandGestureSettings.Pinch(page.Count)!.Value,"Pinch")); AddCard(cards,TriggerSlot(PerHandGestureSettings.Pinch(page.Count,true)!.Value,"Spread")); }
            else if(page.Id=="thumb")
            { _pageContent.Children.Add(Note("Thumb identity and rotation are deferred on Windows. The saved tap assignment remains available for compatibility.")); AddCard(_pageContent,TriggerSlot(HandGestureTrigger.ThumbTwoTap,"Tap")); }
            else if(page.Count==1) AddCard(_pageContent,TriggerSlot(HandGestureTrigger.OneFingerForce,"Force Click"));
            else
            {
                var move=PerHandGestureSettings.Movement(page.Count)!.Value;
                var cross=new UniformGrid { Columns=3 }; _pageContent.Children.Add(cross);
                var tap=page.Count switch { 2=>HandGestureTrigger.TwoFingerTap,3=>HandGestureTrigger.ThreeFingerTap,4=>HandGestureTrigger.FourFingerTap,_=>HandGestureTrigger.FiveFingerTap };
                AddCard(cross,TriggerSlot(tap,"Tap")); AddCard(cross,new(move+"/Up","↑ Move Up",move,Direction:HandMovementDirection.Up)); AddCard(cross,TriggerSlot(PerHandGestureSettings.Force(page.Count)!.Value,"Force Click"));
                AddCard(cross,new(move+"/Left","← Move Left",move,Direction:HandMovementDirection.Left)); AddCard(cross,TriggerSlot(move,"Movement")); AddCard(cross,new(move+"/Right","Move Right →",move,Direction:HandMovementDirection.Right));
                AddCard(cross,new("Hold"+page.Count,"Hold",HoldCount:page.Count)); AddCard(cross,new(move+"/Down","↓ Move Down",move,Direction:HandMovementDirection.Down)); cross.Children.Add(new Border());
            }
            _pageContent.Children.Add(new Separator { Margin=new(0,22,0,14) });
            _pageContent.Children.Add(Note("Choose a card to edit its action. Hold shortcuts can keep their keys pressed until you lift your fingers."));
            _pageContent.Children.Add(Note(_scope==HandGestureScope.Both ? "Both hands form one gesture. Lift both pads to re-arm." : "Lift all fingers to re-arm. Mirror Edit changes independent assignments on Left + Right."));
            if(!_slots.ContainsKey(_selected)) _selected=_slots.Values.FirstOrDefault(s=>s.Trigger is {} t && PerHandGestureSettings.IsMovement(t) && s.Direction==null)?.Key ?? _slots.Keys.First();
            BuildInspector(_slots[_selected]); FilterNavigation();
        }
        finally { _refreshing=false; }
    }
    private string ScopeTitle=>MirrorEdits && _scope!=HandGestureScope.Both ? "Left + Right" : _scope.ToString();
    private static Slot TriggerSlot(HandGestureTrigger trigger,string title)=>new(trigger.ToString(),title,trigger);
    private HandGestureAction Get(PerHandGestureSettings hand,Slot s)=>s.Corner ? hand.CornerAction(HandCornerChord.OuterCorners) : s.HoldCount>0 ? hand.Hold(s.HoldCount) : s.Direction is {} d ? hand.DirectionalMovement?.GetValueOrDefault(s.Trigger!.Value)?.Get(d) ?? HandGestureAction.None : hand.Get(s.Trigger!.Value);
    private HandGestureAction? Get(Slot s)
    {
        if(s.Chord is {} chord) return _settings.HandGesturesV1.Coordinated.Action(chord,s.Hold);
        var left=Get(_settings.HandGesturesV1.Left,s); var right=Get(_settings.HandGesturesV1.Right,s);
        if(MirrorEdits && (left!=right || (left==HandGestureAction.Custom && (_settings.HandGesturesV1.Left.CustomActions?.GetValueOrDefault(s.Key)!=_settings.HandGesturesV1.Right.CustomActions?.GetValueOrDefault(s.Key)
            || s.IsHold && _settings.HandGesturesV1.Left.HeldShortcuts.Contains(s.Key)!=_settings.HandGesturesV1.Right.HeldShortcuts.Contains(s.Key))))) return null;
        return _scope==HandGestureScope.Right ? right : left;
    }
    private string? Custom(Slot s)=>s.Chord!=null ? _settings.HandGesturesV1.Coordinated.CustomActions.GetValueOrDefault(s.Key) : Hand.CustomActions?.GetValueOrDefault(s.Key);
    private string Display(Slot s)=>Get(s) is {} action ? action==HandGestureAction.Custom ? AppLaunchActionHelper.GetDisplayLabel(Custom(s)) : ActionTitle(action) : "Mixed";
    private void Set(Slot s,HandGestureAction action)
    {
        if(s.Chord is {} chord) { (s.Hold ? _settings.HandGesturesV1.Coordinated.HoldActions : _settings.HandGesturesV1.Coordinated.TapActions)[chord]=action; return; }
        Apply(hand=>
        {
            if(s.Corner) (hand.CornerHoldActions ??= new())[HandCornerChord.OuterCorners]=action;
            else if(s.HoldCount>0) (hand.HoldActions ??= new())[s.HoldCount]=action;
            else if(s.Direction is {} d) Directions(hand,s.Trigger!.Value).Actions[d]=action;
            else hand.Set(s.Trigger!.Value,action);
        });
    }
    private static HandDirectionalSettings Directions(PerHandGestureSettings hand,HandGestureTrigger trigger)
    { hand.DirectionalMovement ??= new(); if(!hand.DirectionalMovement.TryGetValue(trigger,out var value)) hand.DirectionalMovement[trigger]=value=new(); return value; }
    private bool Active(Slot s)=>s.Trigger is not {} trigger || !PerHandGestureSettings.IsMovement(trigger) || ((Hand.Directional(trigger)!=null)==s.Direction.HasValue);
    private void AddCard(Panel parent,Slot slot)
    {
        _slots[slot.Key]=slot; var content=new StackPanel(); content.Children.Add(Note(slot.Title)); content.Children.Add(Label(Display(slot),14,true));
        content.Children.Add(Note(slot.IsHold ? "After the hold threshold" : slot.Trigger is {} trigger && PerHandGestureSettings.IsMovement(trigger) ? Active(slot) ? slot.Direction==null ? "Continuous" : "Directional" : "Inactive · click to switch" : "Once per gesture"));
        var card=new Button { Tag=slot.Key,Content=content,MinHeight=120,HorizontalContentAlignment=HorizontalAlignment.Stretch,VerticalContentAlignment=VerticalAlignment.Top,Padding=new(8),Margin=new(4),Background=new SolidColorBrush(Color.FromRgb(23,31,38)),BorderBrush=slot.Key==_selected ? Brushes.DeepSkyBlue : new SolidColorBrush(Color.FromRgb(48,62,73)),BorderThickness=new(slot.Key==_selected ? 2 : 1),Opacity=Active(slot) ? 1 : .55 };
        card.Click+=(_,_)=>
        {
            _selected=slot.Key; _showBuilder=false;
            if(slot.Trigger is {} trigger && PerHandGestureSettings.IsMovement(trigger)) Commit(()=>Apply(h=>Directions(h,trigger).Enabled=slot.Direction!=null)); else Rebuild();
        };
        System.Windows.Automation.AutomationProperties.SetName(card,slot.Title+", "+Display(slot)); parent.Children.Add(card);
    }
    private void BuildInspector(Slot slot)
    {
        _inspector.Children.Add(Label("Action",20,true)); _inspector.Children.Add(Note(ScopeTitle+" · "+slot.Title));
        var allowed=Enum.GetValues<HandGestureAction>().Where(a=>slot.Direction!=null || slot.IsHold || slot.Chord!=null ? PerHandGestureSettings.IsDiscrete(a) : PerHandGestureSettings.Allows(slot.Trigger!.Value,a));
        var options=allowed.Select(a=>new ActionOption(a,ActionTitle(a))).ToList(); var value=Get(slot); if(value==null) options.Insert(0,new(null,"Mixed"));
        var combo=new ComboBox { Tag=slot.Trigger,DisplayMemberPath=nameof(ActionOption.Title),MinHeight=30,MaxDropDownHeight=380,ItemsSource=options,SelectedItem=options.FirstOrDefault(o=>o.Action==value),Margin=new(0,0,0,12) };
        MakeSearchable(combo,options); _inspector.Children.Add(combo);
        combo.SelectionChanged+=(_,_)=> { if(_refreshing || combo.SelectedItem is not ActionOption { Action:{} action }) return;
            if(action==HandGestureAction.Custom) { _showBuilder=true; Rebuild(); } else Commit(()=>Set(slot,action)); };
        if(slot.IsHold)
        {
            AddNumber(_inspector,"Hold threshold (ms)",HoldTime(slot),100,5000,v=>SetHoldTime(slot,v));
            bool held=slot.Chord!=null ? _settings.HandGesturesV1.Coordinated.HeldShortcuts.Contains(slot.Key) : Hand.HeldShortcuts.Contains(slot.Key);
            bool available(PerHandGestureSettings hand)=>Get(hand,slot)==HandGestureAction.Custom && hand.CustomActions?.GetValueOrDefault(slot.Key) is {} label && !AppLaunchActionHelper.TryParse(label,out _);
            bool canHold=slot.Chord!=null ? value==HandGestureAction.Custom && Custom(slot) is {} label && !AppLaunchActionHelper.TryParse(label,out _)
                : MirrorEdits ? available(_settings.HandGesturesV1.Left) && available(_settings.HandGesturesV1.Right) : available(Hand);
            bool? heldValue=held;
            if(slot.Chord==null && MirrorEdits && _settings.HandGesturesV1.Left.HeldShortcuts.Contains(slot.Key)!=_settings.HandGesturesV1.Right.HeldShortcuts.Contains(slot.Key)) heldValue=null;
            var hold=new CheckBox { Content="Hold keys until release",Tag="HeldShortcut",IsThreeState=true,IsChecked=heldValue,IsEnabled=canHold,Margin=new(0,8,0,12) };
            hold.Click+=(_,_)=>Commit(()=> { if(slot.Chord!=null) { if(hold.IsChecked==true) _settings.HandGesturesV1.Coordinated.HeldShortcuts.Add(slot.Key); else _settings.HandGesturesV1.Coordinated.HeldShortcuts.Remove(slot.Key); }
                else Apply(h=> { if(hold.IsChecked==true) h.HeldShortcuts.Add(slot.Key); else h.HeldShortcuts.Remove(slot.Key); }); });
            if(canHold) { _inspector.Children.Add(hold); _inspector.Children.Add(Note("Shortcuts may fire once or keep their keys down until this gesture releases.")); }
        }
        if(slot.Direction is {} direction)
            AddNumber(_inspector,"Repeat ms (0 = once)",Hand.DirectionalMovement?.GetValueOrDefault(slot.Trigger!.Value)?.Repeat(direction) ?? 0,0,5000,v=>Apply(h=>Directions(h,slot.Trigger!.Value).RepeatMilliseconds[direction]=v));
        if(value is HandGestureAction.Pointer or HandGestureAction.PrimaryDrag) AddGain("Pointer sensitivity",0);
        if(value==HandGestureAction.Scroll) { AddGain("Scroll sensitivity",1); var natural=new CheckBox { Content="Natural scrolling",IsChecked=Hand.NaturalScrolling,Margin=new(0,8,0,12) }; natural.Click+=(_,_)=>Commit(()=>Apply(h=>h.NaturalScrolling=natural.IsChecked==true)); _inspector.Children.Add(natural); }
        if(value==HandGestureAction.Zoom) AddGain("Zoom sensitivity",2);
        var builder=new Expander { Header="Shortcut Builder",Foreground=TextColor,IsExpanded=_showBuilder || value==HandGestureAction.Custom,Margin=new(0,16,0,0) };
        builder.SetResourceReference(StyleProperty,"GestureSectionStyle");
        builder.Content=new GestureActionEditor(Custom(slot),label=>Commit(()=> { if(slot.Chord!=null) _settings.HandGesturesV1.Coordinated.CustomActions[slot.Key]=label; else Apply(h=>(h.CustomActions ??= new())[slot.Key]=label); Set(slot,HandGestureAction.Custom); _showBuilder=true; })); _inspector.Children.Add(builder);
    }
    private double HoldTime(Slot s)=>s.Chord is {} chord ? _settings.HandGesturesV1.Coordinated.Milliseconds(chord) : s.Corner ? Hand.CornerMilliseconds(HandCornerChord.OuterCorners) : Hand.HoldMilliseconds(s.HoldCount);
    private void SetHoldTime(Slot s,double value)
    { if(s.Chord is {} chord) _settings.HandGesturesV1.Coordinated.HoldThresholds[chord]=value; else Apply(h=> { if(s.Corner) (h.CornerHoldThresholds ??= new())[HandCornerChord.OuterCorners]=value; else (h.HoldThresholds ??= new())[s.HoldCount]=value; }); }
    private void AddNumber(Panel parent,string title,double value,double min,double max,Action<double> apply)
    {
        parent.Children.Add(Note(title)); var box=new TextBox { Text=value.ToString("0",System.Globalization.CultureInfo.InvariantCulture),MinHeight=28,Margin=new(0,0,0,10) }; parent.Children.Add(box);
        void save() { if(!_refreshing && double.TryParse(box.Text,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out var number) && double.IsFinite(number)) Commit(()=>apply(Math.Clamp(number,min,max))); }
        box.LostKeyboardFocus+=(_,_)=>save(); box.KeyDown+=(_,e)=> { if(e.Key==System.Windows.Input.Key.Enter) { save(); e.Handled=true; } };
    }
    private void AddGain(string title,int kind)
    {
        double get(PerHandGestureSettings h)=>kind==0 ? h.PointerSensitivity : kind==1 ? h.ScrollSensitivity : h.ZoomSensitivity;
        var label=Note(MirrorEdits && get(_settings.HandGesturesV1.Left)!=get(_settings.HandGesturesV1.Right)
            ? $"{title} · Mixed · L {get(_settings.HandGesturesV1.Left):0.00}× / R {get(_settings.HandGesturesV1.Right):0.00}×" : $"{title} · {get(Hand):0.00}×"); _inspector.Children.Add(label);
        var slider=new Slider { Tag=kind,Minimum=.25,Maximum=2,Value=get(Hand),TickFrequency=.01,IsSnapToTickEnabled=true,SmallChange=.01,Margin=new(0,0,0,12) }; _inspector.Children.Add(slider);
        slider.ValueChanged+=(_,_)=> { if(_refreshing) return; double value=Math.Round(slider.Value,2); label.Text=$"{title} · {value:0.00}×"; _refreshing=true;
            try { Apply(h=> { if(kind==0) h.PointerSensitivity=value; else if(kind==1) h.ScrollSensitivity=value; else h.ZoomSensitivity=value; }); _changed(); } finally { _refreshing=false; } };
        slider.AddHandler(Thumb.DragCompletedEvent,new DragCompletedEventHandler((_,_)=>Rebuild()));
    }
    private void FilterNavigation()
    {
        string query=_search.Text.Trim();
        bool matches(Page page)=>(page.Group+" "+page.Title+" "+SearchActions(page)).Contains(query,StringComparison.OrdinalIgnoreCase);
        foreach(ListBoxItem row in _navigation.Items) row.Visibility=row.Tag is Page page ? matches(page) ? Visibility.Visible : Visibility.Collapsed
            : row.Tag is string group && _pages.Any(p=>p.Group==group && matches(p)) ? Visibility.Visible : Visibility.Collapsed;
    }
    private string SearchActions(Page page)
    {
        if(page.Chord is {} chord) return ActionTitle(_settings.HandGesturesV1.Coordinated.Action(chord,false))+" "+ActionTitle(_settings.HandGesturesV1.Coordinated.Action(chord,true));
        if(page.Corners) return ActionTitle(Hand.CornerAction(HandCornerChord.OuterCorners));
        string prefix=page.Count switch {1=>"One",2=>"Two",3=>"Three",4=>"Four",_=>"Five"};
        return string.Join(" ",Enum.GetValues<HandGestureTrigger>().Where(t=>t.ToString().StartsWith(prefix)).Select(t=>ActionTitle(Hand.Get(t))))
            +" "+string.Join(" ",(Hand.CustomActions ?? new()).Where(p=>p.Key.StartsWith(prefix) || p.Key=="Hold"+page.Count).Select(p=>AppLaunchActionHelper.GetDisplayLabel(p.Value)));
    }
    private sealed record ActionOption(HandGestureAction? Action,string Title);
    private void MakeSearchable(ComboBox combo,List<ActionOption> options)
    {
        combo.IsEditable=true; combo.IsTextSearchEnabled=false; combo.StaysOpenOnEdit=true; var selected=combo.SelectedItem;
        combo.ItemsSource=new System.Windows.Data.ListCollectionView(options); combo.SelectedItem=selected;
        combo.AddHandler(TextBoxBase.TextChangedEvent,new TextChangedEventHandler((_,e)=> { if(_refreshing || !combo.IsKeyboardFocusWithin || e.OriginalSource is not TextBox edit) return;
            if(combo.SelectedItem is ActionOption current && current.Title==edit.Text) return; FilterActionOptions(combo,edit.Text); combo.IsDropDownOpen=true; }));
        combo.DropDownClosed+=(_,_)=> { if(_refreshing || combo.SelectedItem!=null) return; _refreshing=true; try { ((System.Windows.Data.ListCollectionView)combo.ItemsSource).Filter=null; combo.SelectedItem=selected; } finally { _refreshing=false; } };
    }
    internal void FilterActionOptions(ComboBox combo,string query)
    { bool before=_refreshing; _refreshing=true; try { if(combo.ItemsSource is System.Windows.Data.ListCollectionView view) view.Filter=o=>o is ActionOption option && option.Title.Contains(query.Trim(),StringComparison.OrdinalIgnoreCase); combo.SelectedItem=null; combo.Text=query; } finally { _refreshing=before; } }
    internal static string Title(HandGestureTrigger trigger)=>trigger.ToString();
    internal static string ActionTitle(HandGestureAction action)=>action switch
    { HandGestureAction.None=>"None",HandGestureAction.Pointer=>"Move Pointer",HandGestureAction.PrimaryDrag=>"Drag / Select",HandGestureAction.Scroll=>"Scroll / Pan",HandGestureAction.PrimaryClick=>"Primary Click",HandGestureAction.SecondaryClick=>"Secondary Click",HandGestureAction.DoubleClick=>"Double-Click",HandGestureAction.NotificationCenter=>"Notification Center",HandGestureAction.TaskView=>"Task View",HandGestureAction.StartMenu=>"Start Menu",HandGestureAction.ShowDesktop=>"Show Desktop",HandGestureAction.OpenConfig=>"Open Config",HandGestureAction.Custom=>"Custom Shortcut / App / File / URL…",HandGestureAction.Voice=>"Voice",_=>action.ToString() };
    private static string ChordTitle(CoordinatedHandChord chord)=>chord switch
    { CoordinatedHandChord.ThreeFingers=>"3 fingers per hand",CoordinatedHandChord.FourFingers=>"4 fingers per hand",CoordinatedHandChord.OuterCorners=>"Outer Corners",CoordinatedHandChord.InnerCorners=>"Inner Corners",CoordinatedHandChord.TopOuter=>"Top Outer Corners",CoordinatedHandChord.BottomOuter=>"Bottom Outer Corners",CoordinatedHandChord.TopInner=>"Top Inner Corners",_=>"Bottom Inner Corners" };
    private static string Placement(CoordinatedHandChord chord)=>chord switch
    { CoordinatedHandChord.ThreeFingers=>"Use three fingers on each pad. Both hands form one gesture.",CoordinatedHandChord.FourFingers=>"Use four fingers on each pad. Both hands form one gesture.",CoordinatedHandChord.OuterCorners=>"Left pad: both left corners. Right pad: both right corners.",CoordinatedHandChord.InnerCorners=>"Left pad: both right corners. Right pad: both left corners.",CoordinatedHandChord.TopOuter=>"Left pad: top left. Right pad: top right.",CoordinatedHandChord.BottomOuter=>"Left pad: bottom left. Right pad: bottom right.",CoordinatedHandChord.TopInner=>"Left pad: top right. Right pad: top left.",_=>"Left pad: bottom right. Right pad: bottom left." };
}
