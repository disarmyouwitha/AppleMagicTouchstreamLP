using System.Collections;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace AppleMagicTouchstream;

// Separate search results from ComboBox.Items: filtering must never clear the
// saved selection or fire the editor's SelectionChanged handler. Only choosing
// a result commits. The same control serves gestures, keyboard and shortcut keys.
public sealed class SearchableActionComboBox : ComboBox
{
    private static readonly Lazy<ResourceDictionary> Theme=new(()=>new ResourceDictionary {
        Source=new Uri("/AppleMagicTouchstream;component/ActionPickerResources.xaml",UriKind.Relative) });
    public static readonly DependencyProperty PickerTitleProperty=DependencyProperty.Register(nameof(PickerTitle),typeof(string),typeof(SearchableActionComboBox),new PropertyMetadata("Choose an action"));
    public static readonly DependencyProperty ResultsViewProperty=DependencyProperty.Register(nameof(ResultsView),typeof(ICollectionView),typeof(SearchableActionComboBox));
    public static readonly DependencyProperty CurrentActionTitleProperty=DependencyProperty.Register(nameof(CurrentActionTitle),typeof(string),typeof(SearchableActionComboBox),new PropertyMetadata("None"));
    public static readonly DependencyProperty SelectedActionTitleProperty=DependencyProperty.Register(nameof(SelectedActionTitle),typeof(string),typeof(SearchableActionComboBox),new PropertyMetadata("None"));
    public static readonly DependencyProperty ResultCountTextProperty=DependencyProperty.Register(nameof(ResultCountText),typeof(string),typeof(SearchableActionComboBox),new PropertyMetadata(""));
    public string PickerTitle { get=>(string)GetValue(PickerTitleProperty); set=>SetValue(PickerTitleProperty,value); }
    public ICollectionView? ResultsView { get=>(ICollectionView?)GetValue(ResultsViewProperty); private set=>SetValue(ResultsViewProperty,value); }
    public string CurrentActionTitle { get=>(string)GetValue(CurrentActionTitleProperty); private set=>SetValue(CurrentActionTitleProperty,value); }
    public string SelectedActionTitle { get=>(string)GetValue(SelectedActionTitleProperty); private set=>SetValue(SelectedActionTitleProperty,value); }
    public string ResultCountText { get=>(string)GetValue(ResultCountTextProperty); private set=>SetValue(ResultCountTextProperty,value); }
    internal Func<object,string>? CategorySelector { get; set; }
    internal Func<object,string>? SearchTextSelector { get; set; }
    private TextBox? _search;
    private ListBox? _results;
    private Button? _done;
    private List<Choice> _choices=[];
    private string _query="";
    public sealed record Choice(object Item,string Title,string Category,string SearchText,bool IsCurrent);

    public SearchableActionComboBox()
    {
        Style=(Style)Theme.Value[typeof(SearchableActionComboBox)];
        IsEditable=false; IsTextSearchEnabled=false; MaxDropDownHeight=480;
    }
    public override void OnApplyTemplate()
    {
        if(_search!=null) _search.TextChanged-=SearchChanged;
        if(_results!=null) { _results.PreviewMouseLeftButtonUp-=ResultClicked; _results.SelectionChanged-=ResultHighlighted; }
        if(_done!=null) _done.Click-=DoneClicked;
        base.OnApplyTemplate();
        _search=GetTemplateChild("PART_Search") as TextBox;
        _results=GetTemplateChild("PART_Results") as ListBox;
        _done=GetTemplateChild("PART_Done") as Button;
        if(_search!=null) _search.TextChanged+=SearchChanged;
        if(_results!=null) { _results.PreviewMouseLeftButtonUp+=ResultClicked; _results.SelectionChanged+=ResultHighlighted; }
        if(_done!=null) _done.Click+=DoneClicked;
    }
    protected override void OnPropertyChanged(DependencyPropertyChangedEventArgs e)
    {
        if(e.Property==SelectedItemProperty || e.Property==DisplayMemberPathProperty)
            SelectedActionTitle=Display(SelectedItem);
        base.OnPropertyChanged(e);
    }
    private void DoneClicked(object sender,RoutedEventArgs e)=>IsDropDownOpen=false;
    private void ResultHighlighted(object sender,SelectionChangedEventArgs e)=>e.Handled=true;
    private string Display(object? item)=>item==null ? "None" : string.IsNullOrEmpty(DisplayMemberPath) ? item.ToString() ?? "" : Read(item,DisplayMemberPath);
    private static string Read(object item,string property)=>TypeDescriptor.GetProperties(item)[property]?.GetValue(item)?.ToString() ?? "";
    internal void PrepareResults()
    {
        CurrentActionTitle=Display(SelectedItem);
        _choices=Items.Cast<object>().Select(item=> {
            string title=Display(item),category=CategorySelector?.Invoke(item) ?? Read(item,"Group");
            if(string.IsNullOrWhiteSpace(category)) category="General";
            string search=SearchTextSelector?.Invoke(item) ?? Read(item,"Value");
            return new Choice(item,title,category,title+" "+category+" "+search,Equals(item,SelectedItem));
        }).ToList();
        var view=new ListCollectionView(_choices);
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(Choice.Category)));
        ResultsView=view; SetQuery("");
    }
    internal void SetQuery(string query)
    {
        _query=query.Trim();
        if(ResultsView==null) { PrepareResults(); _query=query.Trim(); }
        if(_search!=null && _search.Text!=query) { _search.Text=query; return; }
        FilterResults();
    }
    private void SearchChanged(object sender,TextChangedEventArgs e) { _query=_search?.Text.Trim() ?? ""; FilterResults(); }
    private void FilterResults()
    {
        if(ResultsView==null) return;
        string[] terms=_query.Split(' ',StringSplitOptions.RemoveEmptyEntries);
        ResultsView.Filter=item=>item is Choice choice && terms.All(term=>choice.SearchText.Contains(term,StringComparison.OrdinalIgnoreCase));
        var visible=ResultsView.Cast<Choice>().ToArray();
        ResultCountText=visible.Length==1 ? "1 action" : $"{visible.Length} actions";
        if(_results!=null) _results.SelectedItem=visible.FirstOrDefault(c=>c.IsCurrent) ?? visible.FirstOrDefault();
    }
    internal bool Choose(Choice choice)
    {
        if(!IsEnabled || !Items.Contains(choice.Item) || ResultsView==null || !ResultsView.Cast<Choice>().Contains(choice)) return false;
        // Close before committing: an editor may rebuild/dispose this control
        // synchronously when its selection handler saves the new assignment.
        IsDropDownOpen=false; SelectedItem=choice.Item; return true;
    }
    private void ResultClicked(object sender,MouseButtonEventArgs e)
    {
        var row=ItemsControl.ContainerFromElement(_results,(DependencyObject)e.OriginalSource) as ListBoxItem;
        if(row?.Content is Choice choice) { e.Handled=true; Choose(choice); }
    }
    internal void MoveHighlight(int offset)
    {
        if(_results is not { Items.Count:>0 }) return;
        _results.SelectedIndex=Math.Clamp(_results.SelectedIndex+offset,0,_results.Items.Count-1);
        _results.ScrollIntoView(_results.SelectedItem);
    }
    protected override void OnDropDownOpened(EventArgs e)
    {
        PrepareResults(); base.OnDropDownOpened(e);
        Dispatcher.BeginInvoke(DispatcherPriority.Input,()=> { if(IsDropDownOpen) { _search?.Focus(); _search?.SelectAll(); } });
    }
    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if(IsDropDownOpen)
        {
            if(e.Key is Key.Escape or Key.F4 || e.Key==Key.Up && Keyboard.Modifiers.HasFlag(ModifierKeys.Alt))
            { IsDropDownOpen=false; e.Handled=true; return; }
            if(e.Key is Key.Down or Key.Up or Key.PageDown or Key.PageUp)
            {
                MoveHighlight(e.Key switch { Key.Down=>1,Key.Up=>-1,Key.PageDown=>8,_=>-8 });
                e.Handled=true; return;
            }
            if(e.Key==Key.Enter) { if(_results?.SelectedItem is Choice choice) Choose(choice); e.Handled=true; return; }
            if(e.Key==Key.Tab) IsDropDownOpen=false;
        }
        else if(e.Key is Key.Enter or Key.Space or Key.F4 || e.Key==Key.Down && Keyboard.Modifiers.HasFlag(ModifierKeys.Alt))
        { IsDropDownOpen=true; e.Handled=true; return; }
        else if(e.Key is Key.Up or Key.Down or Key.Left or Key.Right or Key.Home or Key.End or Key.PageUp or Key.PageDown)
        { e.Handled=true; return; }
        base.OnPreviewKeyDown(e);
    }
    protected override void OnPreviewTextInput(TextCompositionEventArgs e)
    { if(!IsDropDownOpen) e.Handled=true; else base.OnPreviewTextInput(e); }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        // TextBox/ListBox process their own keys first. Never let ComboBox's
        // remaining native type/arrow navigation commit an unchosen result.
        if(IsDropDownOpen) e.Handled=true; else base.OnKeyDown(e);
    }
    protected override void OnPreviewMouseWheel(MouseWheelEventArgs e)
    {
        e.Handled=true;
        if(IsDropDownOpen && _results!=null && FindScroll(_results) is {} scroll)
        {
            int lines=SystemParameters.WheelScrollLines;
            if(lines<0) { if(e.Delta>0) scroll.PageUp(); else scroll.PageDown(); }
            else for(int i=0;i<lines*Math.Max(1,Math.Abs(e.Delta)/120);i++)
            { if(e.Delta>0) scroll.LineUp(); else scroll.LineDown(); }
        }
    }
    private static ScrollViewer? FindScroll(DependencyObject parent)
    {
        if(parent is ScrollViewer scroll) return scroll;
        for(int i=0;i<VisualTreeHelper.GetChildrenCount(parent);i++)
            if(FindScroll(VisualTreeHelper.GetChild(parent,i)) is {} child) return child;
        return null;
    }
}

internal static class ActionPickerCategories
{
    internal static string Gesture(HandGestureAction action)=>action switch {
        HandGestureAction.None=>"General",
        HandGestureAction.Pointer or HandGestureAction.PrimaryDrag or HandGestureAction.Scroll or HandGestureAction.Zoom
            or HandGestureAction.ScrollUp or HandGestureAction.ScrollDown or HandGestureAction.PanLeft or HandGestureAction.PanRight=>"Movement",
        HandGestureAction.PrimaryClick or HandGestureAction.DoubleClick or HandGestureAction.SecondaryClick=>"Mouse Buttons",
        HandGestureAction.Copy or HandGestureAction.Paste or HandGestureAction.Cut or HandGestureAction.Undo or HandGestureAction.Redo or HandGestureAction.SelectAll=>"Keyboard",
        HandGestureAction.OpenConfig=>"Application",
        HandGestureAction.Custom=>"Shortcuts & Apps",
        _=>"System" };
    internal static string ShortcutKey(string key)=>key switch {
        "None" or ""=>"General",
        _ when key.Length==1 && char.IsAsciiLetter(key[0])=>"Letters A–Z",
        _ when key.Length==1 && char.IsAsciiDigit(key[0])=>"Numbers 0–9",
        _ when key.Length==1=>"Symbols & Punctuation",
        _ when key.StartsWith('F') && int.TryParse(key.AsSpan(1),out _)=>"Function Keys",
        _=>"Navigation & Editing" };
}
