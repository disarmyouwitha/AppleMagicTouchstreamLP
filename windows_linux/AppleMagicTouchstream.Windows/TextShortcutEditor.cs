using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
namespace AppleMagicTouchstream;

// Selection does not fetch plaintext. Reveal is explicit; leaving the field or
// changing assignment clears it. New text commits on Return/focus loss.
public sealed class TextShortcutEditor:StackPanel
{
    private readonly PasswordBox _hidden=new() { MinHeight=28,VerticalContentAlignment=VerticalAlignment.Center };
    private readonly TextBox _visible=new() { MinHeight=28,VerticalContentAlignment=VerticalAlignment.Center,Visibility=Visibility.Collapsed };
    private readonly TextBlock _placeholder=new() { Text="Encrypted for your Windows account",Foreground=Brushes.Gray,Margin=new(6,0,0,0),VerticalAlignment=VerticalAlignment.Center,IsHitTestVisible=false };
    private readonly TextBlock _status=new() { TextWrapping=TextWrapping.Wrap,Foreground=Brushes.Salmon,FontSize=11 };
    private readonly Button _eye=new() { Content="◉",Width=76,Height=28,ToolTip="Show or hide saved text" };
    private Action<string>? _applied;
    private string? _current;
    private bool _dirty,_updating,_revealed,_saving;
    private int _revision;
    public TextShortcutEditor()
    {
        var row=new Grid { Margin=new(0,8,0,0) }; Children.Add(row);
        row.ColumnDefinitions.Add(new() {Width=GridLength.Auto});row.ColumnDefinitions.Add(new());row.ColumnDefinitions.Add(new() {Width=GridLength.Auto});
        row.Children.Add(new TextBlock { Text="Text",Foreground=Brushes.LightSlateGray,VerticalAlignment=VerticalAlignment.Center,Margin=new(0,0,8,0) });
        var field=new Grid(); Grid.SetColumn(field,1);row.Children.Add(field);field.Children.Add(_hidden);field.Children.Add(_visible);field.Children.Add(_placeholder);
        Grid.SetColumn(_eye,2);_eye.Margin=new(8,0,0,0);row.Children.Add(_eye);Children.Add(_status);
        _hidden.PasswordChanged+=(_,_)=> { if(!_updating){_dirty=true;_revision++;} Placeholder(); };
        _visible.TextChanged+=(_,_)=> { if(!_updating){_dirty=true;_revision++;} Placeholder(); };
        _hidden.LostKeyboardFocus+=(_,e)=> { if(!ReferenceEquals(e.NewFocus,_eye)) Commit(); };
        _visible.LostKeyboardFocus+=(_,e)=> { if(!ReferenceEquals(e.NewFocus,_eye)) Commit(); };
        _hidden.KeyDown+=(_,e)=> { if(e.Key==Key.Return) { Commit(); e.Handled=true; } };
        _visible.KeyDown+=(_,e)=> { if(e.Key==Key.Return) { Commit(); e.Handled=true; } };
        _eye.Click+=async (_,_)=>
        {
            if(_revealed) { Commit(); Conceal(); return; }
            int revision=_revision;
            string text=_hidden.Password;
            if(!_dirty && TextShortcutReference.TryRead(_current,out var id))
            {
                try { text=await Task.Run(()=>WindowsTextShortcutStore.Shared.Load(id)); }
                catch { _status.Text="Saved text unavailable. Re-enter it on this Windows account."; return; }
                if(revision!=_revision || !IsLoaded) return;
            }
            _updating=true;_visible.Text=text;_hidden.Clear();_updating=false;_revealed=true;_visible.Visibility=Visibility.Visible;_hidden.Visibility=Visibility.Collapsed;_eye.Content="⊘";Placeholder();
        };
        Unloaded+=(_,_)=> { _revision++;Conceal(); };
    }
    public void Configure(string? current,Action<string> applied,bool enabled=true)
    { if(_current!=current) { _revision++;Conceal();_dirty=false; } _current=current;_applied=applied;IsEnabled=enabled; }
    private void Placeholder()=>_placeholder.Visibility=(_revealed ? _visible.Text.Length==0 : _hidden.Password.Length==0) ? Visibility.Visible:Visibility.Collapsed;
    private void Conceal()
    { _updating=true;_hidden.Clear();_visible.Clear();_updating=false;_revealed=false;_visible.Visibility=Visibility.Collapsed;_hidden.Visibility=Visibility.Visible;_eye.Content="◉";Placeholder(); }
    private void Commit()
    {
        if(!_dirty || _saving || _applied==null) return;
        string text=_revealed ? _visible.Text:_hidden.Password;
        if(!TextShortcutReference.Valid(text)) { _status.Text="Enter text up to 64 KB."; return; }
        _saving=true;
        try { string label=TextShortcutReference.Label(WindowsTextShortcutStore.Shared.Save(text)); _dirty=false;_current=label;Conceal();_status.Text="";_applied(label); }
        catch { _status.Text="Could not encrypt saved text for this Windows account."; }
        finally { _saving=false; }
    }
}
