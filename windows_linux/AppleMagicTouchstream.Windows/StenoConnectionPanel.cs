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
    private readonly ExplicitSelectionComboBox _variant=new() {ItemsSource=new[]{"Steno Asterisk","Steno 6x3","Steno Single"},MinWidth=145};
    private readonly Slider _force=new() {Minimum=1,Maximum=WindowsForceSettings.PressureMaximum,TickFrequency=1,IsSnapToTickEnabled=true,ToolTip="Reported per-contact pressure (1–255)."};
    private readonly TextBlock _forceValue=new() {MinWidth=34};
    private readonly CheckBox _touch=new() {Content="Haptic on touch"},_release=new() {Content="Haptic on release"};
    private readonly ExplicitSelectionComboBox _connection=new() {ItemsSource=new[]{"Built-in Javelin (Lapwing)","Built-in Javelin (Plover)","Plover Plugin"},MinWidth=145};
    private readonly Button _manage=new() {Content="Dictionaries…",Padding=new(8,4,8,4)};
    private readonly StackPanel _pluginControls=new();
    private Button? _install;
    private string _mode="javelin";
    private WindowsStenoConnection? _bound;
    private bool _sync;
    public event Action<string>? ConnectionChanged;
    public event Action? ManageDictionaries;
    public event Action<string>? LayoutChanged;
    public event Action<double>? ForceThresholdChanged;
    public event Action<bool,bool>? HapticsChanged;
    public void Configure(UserSettings settings)
    {
        _sync=true;
        try
        {
            _mode=settings.StenoConnectionMode;
            _connection.SelectedIndex=_mode=="plugin" ? 2:_mode=="javelinPlover" ? 1:0;
            _manage.Visibility=_mode=="plugin" ? Visibility.Collapsed:Visibility.Visible;
            _pluginControls.Visibility=_mode=="plugin" ? Visibility.Visible:Visibility.Collapsed;
            _variant.SelectedIndex=settings.LayoutPresetName=="STENO Single" ? 2:settings.LayoutPresetName=="STENO Voyager" ? 1:0;
            _force.Value=WindowsForceSettings.StenoThreshold(settings.StenoForceThreshold);
            _forceValue.Text=((int)_force.Value).ToString();
            _touch.IsChecked=settings.StenoHapticTouch ?? settings.StenoHaptics==StenoHapticMode.KeyContact;
            _release.IsChecked=settings.StenoHapticRelease ?? settings.StenoHaptics==StenoHapticMode.ChordRelease;
        }
        finally {_sync=false;}
    }
    private readonly TextBlock _installation=new() { TextWrapping=TextWrapping.Wrap,FontSize=11 };
    private readonly DispatcherTimer _timer=new() { Interval=TimeSpan.FromSeconds(1) };
    public StenoConnectionPanel()
    {
        Margin=new(0,10,0,4); Padding=new(10); CornerRadius=new(8);
        System.Windows.Documents.TextElement.SetForeground(this,Brushes.Gainsboro);
        BorderBrush=new SolidColorBrush(Color.FromRgb(57,69,78)); BorderThickness=new(1);
        var content=new StackPanel();
        var variant=new Grid();variant.ColumnDefinitions.Add(new());variant.ColumnDefinitions.Add(new());
        variant.Children.Add(new TextBlock {Text="Layout",VerticalAlignment=VerticalAlignment.Center});Grid.SetColumn(_variant,1);variant.Children.Add(_variant);content.Children.Add(variant);
        _variant.SelectionChanged+=(_,_)=> {if(!_sync && _variant.SelectedIndex>=0)LayoutChanged?.Invoke(_variant.SelectedIndex switch {1=>"STENO Voyager",2=>"STENO Single",_=>"STENO"});};
        var connection=new Grid {Margin=new(0,8,0,0)};connection.ColumnDefinitions.Add(new());connection.ColumnDefinitions.Add(new());connection.Children.Add(new TextBlock {Text="Connection",VerticalAlignment=VerticalAlignment.Center});Grid.SetColumn(_connection,1);connection.Children.Add(_connection);content.Children.Add(connection);
        _connection.SelectionChanged+=(_,_)=> {if(!_sync && _connection.SelectedIndex>=0)ConnectionChanged?.Invoke(_connection.SelectedIndex switch {1=>"javelinPlover",2=>"plugin",_=>"javelin"});};
        var statusRow=new Grid {Margin=new(0,8,0,0)};statusRow.ColumnDefinitions.Add(new());statusRow.ColumnDefinitions.Add(new());statusRow.Children.Add(_status);Grid.SetColumn(_manage,1);statusRow.Children.Add(_manage);content.Children.Add(statusRow);_manage.Click+=(_,_)=>ManageDictionaries?.Invoke();
        var retry=new Button {Content="↻ Refresh connection",HorizontalAlignment=HorizontalAlignment.Left,Margin=new(0,4,0,0)};retry.Click+=(_,_)=>_bound?.RefreshConnection(true);content.Children.Add(retry);
        var header=new Grid {Margin=new(0,14,0,6)};header.ColumnDefinitions.Add(new());header.ColumnDefinitions.Add(new());
        header.Children.Add(new TextBlock {Text="STENO Mouse",FontWeight=FontWeights.SemiBold});var disabled=new TextBlock {Text="Configurable gestures are disabled in STENO.",Foreground=Brushes.Gray,TextWrapping=TextWrapping.Wrap,FontSize=10};Grid.SetColumn(disabled,1);header.Children.Add(disabled);content.Children.Add(header);
        content.Children.Add(new TextBlock {Text="1F force drag/select · 2F mouse/left-click · 3F right-click · 4F force scroll",TextWrapping=TextWrapping.Wrap,Margin=new(0,0,0,10)});
        var forceRow=new Grid();forceRow.ColumnDefinitions.Add(new());forceRow.ColumnDefinitions.Add(new());forceRow.Children.Add(new TextBlock {Text="Force Threshold"});
        var forceControls=new DockPanel();DockPanel.SetDock(_forceValue,Dock.Right);forceControls.Children.Add(_forceValue);forceControls.Children.Add(_force);Grid.SetColumn(forceControls,1);forceRow.Children.Add(forceControls);content.Children.Add(forceRow);
        _force.ValueChanged+=(_,_)=> { _forceValue.Text=((int)_force.Value).ToString();if(!_sync && !System.Windows.Input.Mouse.LeftButton.Equals(System.Windows.Input.MouseButtonState.Pressed))ForceThresholdChanged?.Invoke(_force.Value); };
        _force.PreviewMouseLeftButtonUp+=(_,_)=>{if(!_sync)ForceThresholdChanged?.Invoke(_force.Value);};
        _force.AddHandler(System.Windows.Controls.Primitives.Thumb.DragCompletedEvent,new System.Windows.Controls.Primitives.DragCompletedEventHandler((_,_)=> {if(!_sync)ForceThresholdChanged?.Invoke(_force.Value);}));
        var feedback=new System.Windows.Controls.Primitives.UniformGrid {Columns=2,Margin=new(0,10,0,6)};feedback.Children.Add(_touch);feedback.Children.Add(_release);content.Children.Add(feedback);
        void changed(){if(!_sync)HapticsChanged?.Invoke(_touch.IsChecked==true,_release.IsChecked==true);}
        _touch.Click+=(_,_)=>changed();_release.Click+=(_,_)=>changed();
        content.Children.Add(new TextBlock {Text="Uses Haptic Strength in Typing Tuning.",Foreground=Brushes.Gray,FontSize=11,Margin=new(0,0,0,12)});
        content.Children.Add(_pluginControls);
        var install=new Button { Content="Install / update Plover plugin",Margin=new(0,8,0,6),Padding=new(8,4,8,4) };
        _install=install;
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
        _pluginControls.Children.Add(install);
        _pluginControls.Children.Add(_installation);
        _pluginControls.Children.Add(new TextBlock { Text="Install the plugin once, restart Plover, then choose Configure → Machine → AppleMagicTouchstream. Enable Plover output and Mouse Takeover here.",TextWrapping=TextWrapping.Wrap,FontSize=11 });
        content.Children.Add(_counts); Child=content;
        _timer.Tick+=(_,_)=>Refresh(); Loaded+=(_,_)=> { Refresh(); _timer.Start(); }; Unloaded+=(_,_)=>_timer.Stop();
    }
    internal void Bind(WindowsStenoConnection connection) { _bound=connection;_snapshot=()=>connection.Status; Refresh(); }
    private void Refresh()
    {
        if(_snapshot==null) return;
        _bound?.RefreshConnection();
        var state=_snapshot();
        _status.Text=state.Error ?? (state.Connected ? _mode=="plugin" ? "Connected":_mode=="javelinPlover" ? "Plover ready":"Lapwing ready" : "Disconnected");
        _status.Foreground=state.Connected ? Brushes.LimeGreen:Brushes.IndianRed;
        if(_install!=null && _mode=="plugin" && state.Connected){_install.Content="Plugin Installed";_install.IsEnabled=false;}
        _counts.Text=$"Sent: {state.Sent} · Dropped: {state.Dropped}";
    }
}
