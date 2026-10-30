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
    private readonly ComboBox _pointer=new() { Margin=new(0,4,0,8) };
    private bool _syncPointer;
    public event Action<int>? PointerFingerCountChanged;
    public void SetPointerFingerCount(int count)
    {
        _syncPointer=true;
        try { _pointer.SelectedIndex=count==1 ? 0 : 1; }
        finally { _syncPointer=false; }
    }
    private readonly TextBlock _installation=new() { TextWrapping=TextWrapping.Wrap,FontSize=11 };
    private readonly DispatcherTimer _timer=new() { Interval=TimeSpan.FromSeconds(1) };
    public StenoConnectionPanel()
    {
        Margin=new(0,10,0,4); Padding=new(10); CornerRadius=new(8);
        System.Windows.Documents.TextElement.SetForeground(this,Brushes.Gainsboro);
        BorderBrush=new SolidColorBrush(Color.FromRgb(57,69,78)); BorderThickness=new(1);
        var content=new StackPanel();
        content.Children.Add(new TextBlock { Text="Steno → Plover",FontWeight=FontWeights.SemiBold,Margin=new(0,0,0,6) });
        content.Children.Add(_status);
        content.Children.Add(new TextBlock { Text="Pointer movement",Margin=new(0,8,0,0) });
        _pointer.Items.Add("One finger"); _pointer.Items.Add("Two fingers"); SetPointerFingerCount(2);
        _pointer.SelectionChanged+=(_,_)=> { if(!_syncPointer && _pointer.SelectedIndex>=0) PointerFingerCountChanged?.Invoke(_pointer.SelectedIndex+1); };
        content.Children.Add(_pointer);
        var install=new Button { Content="Install / update Plover plugin",Margin=new(0,8,0,6),Padding=new(8,4,8,4) };
        install.Click+=async (_,_)=>
        {
            install.IsEnabled=false;
            _installation.Text="Installing into Plover…";
            try
            {
                string script=System.IO.Path.Combine(AppContext.BaseDirectory,"PloverPlugin","Install-PloverPlugin.ps1");
                if(!System.IO.File.Exists(script)) throw new System.IO.FileNotFoundException("The bundled plugin installer is missing. Extract the complete app folder again.");
                var start=new ProcessStartInfo("powershell.exe") {
                    UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,
                    RedirectStandardOutput=true,RedirectStandardError=true
                };
                foreach(string argument in new[] { "-NoProfile","-STA","-ExecutionPolicy","Bypass","-File",script }) start.ArgumentList.Add(argument);
                using var process=Process.Start(start) ?? throw new InvalidOperationException("Could not start the Plover installer.");
                var output=process.StandardOutput.ReadToEndAsync();
                var error=process.StandardError.ReadToEndAsync();
                await process.WaitForExitAsync();
                string details=(await output)+"\n"+(await error);
                _installation.Text=process.ExitCode==0 ? "Installed. Restart Plover, then select AppleMagicTouchstream under Configure → Machine."
                    : "Installation did not complete. "+details.Trim();
            }
            catch(Exception error) { _installation.Text="Installation failed: "+error.Message; }
            finally { install.IsEnabled=true; }
        };
        content.Children.Add(install);
        content.Children.Add(_installation);
        content.Children.Add(new TextBlock { Text="Install the plugin once, restart Plover, then choose Configure → Machine → AppleMagicTouchstream. Enable Plover output and Mouse Takeover here.",TextWrapping=TextWrapping.Wrap,FontSize=11 });
        content.Children.Add(new TextBlock { Text="Lift all fingers to send a chord. Pointer movement cancels the chord until both hands lift. Stationary contacts still chord, including single-finger strokes. Clicking is not assigned in this prototype.",TextWrapping=TextWrapping.Wrap,Margin=new(0,6,0,6),FontSize=11 });
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
