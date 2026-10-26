using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace GlassToKey;

// Uses the keyboard editor's catalog identities and shortcut formatter.
internal sealed class GestureActionBuilder : Window
{
    public string? Assignment { get; private set; }
    public GestureActionBuilder(string? current)
    {
        Title="Action Builder"; Width=440; SizeToContent=SizeToContent.Height; ResizeMode=ResizeMode.NoResize;
        WindowStartupLocation=WindowStartupLocation.CenterOwner; Background=new SolidColorBrush(Color.FromRgb(20,25,30)); Foreground=Brushes.WhiteSmoke;
        var root=new StackPanel { Margin=new(20) }; Content=root;
        root.Children.Add(new TextBlock { Text="Shortcut Builder", FontSize=17, FontWeight=FontWeights.SemiBold, Margin=new(0,0,0,12) });
        var toggles=new WrapPanel(); root.Children.Add(toggles);
        var modifiers=new[] { ("Ctrl",DispatchModifierFlags.Ctrl),("Shift",DispatchModifierFlags.Shift),("Alt",DispatchModifierFlags.Alt),("Win",DispatchModifierFlags.Meta) };
        var buttons=modifiers.Select(m=>new ToggleButton { Content=m.Item1, Tag=m.Item2, Padding=new(12,6,12,6), Margin=new(0,0,6,8) }).ToArray();
        foreach (var button in buttons) toggles.Children.Add(button);
        var hyper=new Button { Content="Hyper", Padding=new(12,6,12,6), Margin=new(0,0,0,8) }; toggles.Children.Add(hyper);
        hyper.Click += (_,_)=> { foreach (var button in buttons) button.IsChecked=true; };
        root.Children.Add(new TextBlock { Text="Key",Margin=new(0,0,0,4) });
        var keys=new ComboBox { ItemsSource=new[] { "None" }.Concat(DispatchShortcutHelper.ShortcutKeyLabels).ToArray(), SelectedIndex=0, IsEditable=true, MinHeight=28 };
        System.Windows.Automation.AutomationProperties.SetName(keys,"Shortcut key"); root.Children.Add(keys);
        if (current!=null && DispatchShortcutHelper.TryReadShortcut(current,out var flags,out string key))
        { foreach (var button in buttons) button.IsChecked=(flags&(DispatchModifierFlags)button.Tag)!=0; keys.Text=string.IsNullOrEmpty(key) ? "None" : key; }
        root.Children.Add(new TextBlock { Text="Or open an app, file, folder or URL", Margin=new(0,16,0,6) });
        var target=new TextBox { MinHeight=28, Padding=new(5), Text=AppLaunchActionHelper.TryParse(current,out var spec) ? spec.FileName : "" };
        System.Windows.Automation.AutomationProperties.SetName(target,"App, file, folder or URL"); root.Children.Add(target);
        root.Children.Add(new TextBlock { Text="Arguments (optional, for apps)", Margin=new(0,8,0,4) });
        var arguments=new TextBox { MinHeight=28, Padding=new(5),Text=AppLaunchActionHelper.TryParse(current,out var existing) ? existing.Arguments : "" };
        System.Windows.Automation.AutomationProperties.SetName(arguments,"Application arguments"); root.Children.Add(arguments);
        root.Children.Add(new TextBlock { Text="Leave the target empty to use the shortcut. Modifier-only shortcuts use Key: None. Gesture actions fire once; keyboard key holds keep their existing behavior.", TextWrapping=TextWrapping.Wrap, Foreground=Brushes.LightSlateGray, Margin=new(0,10,0,8) });
        var error=new TextBlock { TextWrapping=TextWrapping.Wrap, Foreground=Brushes.Salmon }; root.Children.Add(error);
        var actions=new StackPanel { Orientation=Orientation.Horizontal, HorizontalAlignment=HorizontalAlignment.Right, Margin=new(0,12,0,0) }; root.Children.Add(actions);
        var cancel=new Button { Content="Cancel",IsCancel=true,Padding=new(14,6,14,6),Margin=new(0,0,8,0) }; actions.Children.Add(cancel);
        var apply=new Button { Content="Apply",IsDefault=true,Padding=new(14,6,14,6) }; actions.Children.Add(apply);
        apply.Click += (_,_)=>
        {
            if (!string.IsNullOrWhiteSpace(target.Text)) Assignment=AppLaunchActionHelper.CreateActionLabel(target.Text,arguments.Text);
            else
            {
                var flags=DispatchModifierFlags.None;
                foreach (var button in buttons) if (button.IsChecked==true) flags|=(DispatchModifierFlags)button.Tag;
                string key=keys.Text.Trim(); if (key=="None") key="";
                if (key.Length>0 && !DispatchShortcutHelper.TryNormalizeShortcutKeyLabel(key,out key)) { error.Text="Choose a supported key."; return; }
                Assignment=flags==DispatchModifierFlags.None ? key : DispatchShortcutHelper.FormatShortcut(flags,key);
            }
            if (string.IsNullOrWhiteSpace(Assignment)) { error.Text="Choose a key, modifier, or target."; return; }
            DialogResult=true;
        };
    }
}
