using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace AppleMagicTouchstream;

public sealed class StenoConnectionPanel : Border
{
    private Func<WindowsStenoConnection.Snapshot>? _snapshot;
    private readonly TextBlock _status=new() { Text="Waiting for Plover",TextWrapping=TextWrapping.Wrap };
    private readonly TextBlock _counts=new();
    private readonly DispatcherTimer _timer=new() { Interval=TimeSpan.FromSeconds(1) };
    public StenoConnectionPanel()
    {
        Margin=new(0,10,0,4); Padding=new(10); CornerRadius=new(8);
        System.Windows.Documents.TextElement.SetForeground(this,Brushes.Gainsboro);
        BorderBrush=new SolidColorBrush(Color.FromRgb(57,69,78)); BorderThickness=new(1);
        var content=new StackPanel();
        content.Children.Add(new TextBlock { Text="Steno → Plover",FontWeight=FontWeights.SemiBold,Margin=new(0,0,0,6) });
        content.Children.Add(_status);
        var folder=new Button { Content="Open plugin installer folder",Margin=new(0,8,0,6),Padding=new(8,4,8,4) };
        folder.Click+=(_,_)=>
        {
            string path=System.IO.Path.Combine(AppContext.BaseDirectory,"PloverPlugin");
            if(System.IO.Directory.Exists(path)) Process.Start(new ProcessStartInfo(path) { UseShellExecute=true });
        };
        content.Children.Add(folder);
        content.Children.Add(new TextBlock { Text="Install the plugin once, restart Plover, then choose Configure → Machine → AppleMagicTouchstream. Enable Plover output and Mouse Takeover here.",TextWrapping=TextWrapping.Wrap,FontSize=11 });
        content.Children.Add(new TextBlock { Text="Both hands lift to send a stroke. Ordinary typing and gestures pause in STENO.",TextWrapping=TextWrapping.Wrap,Margin=new(0,6,0,6),FontSize=11 });
        content.Children.Add(_counts); Child=content;
        _timer.Tick+=(_,_)=>Refresh(); Loaded+=(_,_)=> { Refresh(); _timer.Start(); }; Unloaded+=(_,_)=>_timer.Stop();
    }
    internal void Bind(WindowsStenoConnection connection) { _snapshot=()=>connection.Status; Refresh(); }
    private void Refresh()
    {
        if(_snapshot==null) return;
        var state=_snapshot();
        _status.Text=state.Error ?? (state.Connected ? "Plover connected" : "Waiting for Plover");
        _counts.Text=$"Sent: {state.Sent} · Dropped: {state.Dropped}";
    }
}
