using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
namespace AppleMagicTouchstream;

internal sealed class JavelinDictionaryWindow:Window
{
    private readonly List<StenoDictionarySource> _sources;
    private readonly ListBox _dictionaries=new() {MinWidth=230};
    private readonly ListBox _entries=new();
    private readonly TextBox _search=new() {MinHeight=28};
    private readonly TextBox _outline=new() {MinHeight=28},_translation=new() {MinHeight=28};
    private readonly TextBlock _status=new() {TextWrapping=TextWrapping.Wrap,Foreground=Brushes.IndianRed};
    private readonly Button _record=new() {Content="Record Stroke",Margin=new(0,4,0,10)};
    private Dictionary<string,string> _values=new();
    private readonly Action _changed;
    private readonly Action<Action<ulong>?> _recording;
    private bool _recordingActive;
    internal JavelinDictionaryWindow(UserSettings settings,Action changed,Action<Action<ulong>?> recording)
    {
        Title="STENO Dictionaries";Width=900;Height=640;MinWidth=650;MinHeight=420;_changed=changed;_recording=recording;
        _sources=WindowsJavelinDictionaries.Sources(settings,settings.StenoConnectionMode);
        var root=new Grid {Margin=new(16)};Content=root;root.ColumnDefinitions.Add(new() {Width=new(260)});root.ColumnDefinitions.Add(new());
        var left=new DockPanel {Margin=new(0,0,14,0)};root.Children.Add(left);
        var tools=new WrapPanel();DockPanel.SetDock(tools,Dock.Top);left.Children.Add(tools);
        tools.Children.Add(Button("New",New));tools.Children.Add(Button("Load",Load));tools.Children.Add(Button("Export",Export));tools.Children.Add(Button("Remove",Remove));
        tools.Children.Add(Button("↑",()=>Move(-1)));tools.Children.Add(Button("↓",()=>Move(1)));left.Children.Add(_dictionaries);
        var right=new Grid();Grid.SetColumn(right,1);root.Children.Add(right);right.RowDefinitions.Add(new() {Height=GridLength.Auto});right.RowDefinitions.Add(new());right.RowDefinitions.Add(new() {Height=GridLength.Auto});
        _search.ToolTip="Search outlines or translations";right.Children.Add(_search);_search.TextChanged+=(_,_)=>Filter();
        Grid.SetRow(_entries,1);right.Children.Add(_entries);
        var edit=new StackPanel {Margin=new(0,12,0,0)};Grid.SetRow(edit,2);right.Children.Add(edit);
        var fields=new Grid();fields.ColumnDefinitions.Add(new());fields.ColumnDefinitions.Add(new());edit.Children.Add(fields);
        var outline=new StackPanel {Margin=new(0,0,8,0)};outline.Children.Add(new TextBlock {Text="Outline"});outline.Children.Add(_outline);outline.Children.Add(_record);fields.Children.Add(outline);
        var translation=new StackPanel();translation.Children.Add(new TextBlock {Text="Translation"});translation.Children.Add(_translation);Grid.SetColumn(translation,1);fields.Children.Add(translation);
        _record.Click+=(_,_)=>SetRecording(!_recordingActive);
        var actions=new WrapPanel();actions.Children.Add(Button("Save entry",SaveEntry));actions.Children.Add(Button("Delete entry",DeleteEntry));edit.Children.Add(actions);edit.Children.Add(_status);
        edit.Children.Add(new TextBlock {Text="Higher dictionaries have priority. Bundled dictionaries require Save As before editing. Record captures outlines; normal STENO can type translations.",TextWrapping=TextWrapping.Wrap,Foreground=Brushes.Gray,Margin=new(0,8,0,0)});
        _dictionaries.SelectionChanged+=(_,_)=>SelectDictionary();_entries.SelectionChanged+=(_,_)=> {if(_entries.SelectedItem is KeyValuePair<string,string> entry){_outline.Text=entry.Key;_translation.Text=entry.Value;}};
        Closed+=(_,_)=>SetRecording(false);RefreshSources();
    }
    private static Button Button(string title,Action action)
    {var b=new Button {Content=title,Padding=new(8,4,8,4),Margin=new(2)};b.Click+=(_,_)=>action();return b;}
    private StenoDictionarySource? Selected=>_dictionaries.SelectedItem is ListBoxItem {Tag:StenoDictionarySource source} ? source:null;
    private void RefreshSources(StenoDictionarySource? select=null)
    {
        select??=Selected;_dictionaries.Items.Clear();
        foreach(var source in _sources)
        {
            var check=new CheckBox {Content=Path.GetFileName(source.Path)+(source.Bundled ? " · bundled":""),IsChecked=source.Enabled};
            check.Click+=(_,e)=> {source.Enabled=check.IsChecked==true;_changed();e.Handled=true;};
            var row=new ListBoxItem {Tag=source,Content=check};_dictionaries.Items.Add(row);if(ReferenceEquals(source,select))_dictionaries.SelectedItem=row;
        }
        if(_dictionaries.SelectedItem==null && _dictionaries.Items.Count>0)_dictionaries.SelectedIndex=0;
    }
    private void SelectDictionary()
    {
        SetRecording(false);
        try{_values=Selected is {} source ? WindowsJavelinDictionaries.Read(source):new();_status.Text="";Filter();}
        catch{_values=new();Filter();_status.Text="Could not load this JSON dictionary.";}
    }
    private void Filter()
    {string q=_search.Text.Trim();_entries.ItemsSource=_values.Where(p=>q.Length==0 || p.Key.Contains(q,StringComparison.OrdinalIgnoreCase) || p.Value.Contains(q,StringComparison.OrdinalIgnoreCase)).OrderBy(p=>p.Key).Take(1000).ToArray();_entries.DisplayMemberPath="Key";}
    private string? ChooseSave(string name)
    {var dialog=new SaveFileDialog {Title="Save Dictionary As",Filter="JSON dictionaries|*.json",DefaultExt=".json",FileName=name,OverwritePrompt=true};return dialog.ShowDialog(this)==true ? dialog.FileName:null;}
    private bool EnsureWritable()
    {
        if(Selected is not {} selected)return false;if(!selected.Bundled)return true;
        var path=ChooseSave(Path.GetFileNameWithoutExtension(selected.Path)+"-custom.json");if(path==null)return false;
        var copy=new StenoDictionarySource {Path=path};WindowsJavelinDictionaries.Save(copy,_values);_sources.Insert(0,copy);foreach(var source in _sources.Where(s=>s.Bundled))source.Enabled=false;RefreshSources(copy);_changed();return true;
    }
    private void SaveEntry()
    {
        try
        {
            string outline=WindowsJavelin.Canonical(_outline.Text.Trim()),text=_translation.Text;
            if(!WindowsJavelin.Supported(text)){_status.Text="This translator supports text, affixes and formatting; Plover/raw-key commands require the Plover plugin.";return;}
            if(!EnsureWritable())return;
            _values[outline]=text;WindowsJavelinDictionaries.Save(Selected!,_values);_changed();Filter();_status.Text="Saved";
        }
        catch{_status.Text="Could not save this outline/translation. Check the outline and the native Javelin library.";}
    }
    private void DeleteEntry()
    {try {string key=_outline.Text.Trim();if(!_values.ContainsKey(key) || !EnsureWritable())return;_values.Remove(key);WindowsJavelinDictionaries.Save(Selected!,_values);_changed();Filter();}catch{_status.Text="Could not save the dictionary.";}}
    private void New()
    {
        var path=ChooseSave("custom-steno.json");if(path==null)return;
        try{var source=new StenoDictionarySource {Path=path};WindowsJavelinDictionaries.Save(source,new());foreach(var s in _sources.Where(s=>s.Bundled))s.Enabled=false;_sources.Insert(0,source);RefreshSources(source);_changed();}catch{_status.Text="Could not create dictionary.";}
    }
    private void Load()
    {var dialog=new OpenFileDialog {Filter="JSON dictionaries|*.json",CheckFileExists=true};if(dialog.ShowDialog(this)!=true)return;try{var source=new StenoDictionarySource {Path=dialog.FileName};_=WindowsJavelinDictionaries.Read(source);_sources.Insert(0,source);RefreshSources(source);_changed();}catch{_status.Text="Expected a JSON outline-to-translation dictionary.";}}
    private void Export()
    {if(Selected==null)return;var path=ChooseSave(Path.GetFileName(Selected.Path));if(path==null)return;try{WindowsJavelinDictionaries.Save(new() {Path=path},_values);}catch{_status.Text="Could not export dictionary.";}}
    private void Remove()
    {if(Selected is not {} source)return;_sources.Remove(source);RefreshSources();_changed();} // No automatic re-enabling or file deletion.
    private void Move(int direction)
    {if(Selected is not {} source)return;int index=_sources.IndexOf(source),next=index+direction;if(next<0 || next>=_sources.Count)return;_sources.RemoveAt(index);_sources.Insert(next,source);RefreshSources(source);_changed();}
    private void SetRecording(bool value)
    {
        if(value==_recordingActive)return;_recordingActive=value;_record.Content=value ? "Stop Recording":"Record Stroke";
        if(!value){_recording(null);return;}
        _outline.Clear();
        _recording(mask=>Dispatcher.BeginInvoke(()=> {if(!_recordingActive)return;string stroke=WindowsJavelin.Format(mask);_outline.Text+=(_outline.Text.Length>0 ? "/":"")+stroke;}));
    }
}
