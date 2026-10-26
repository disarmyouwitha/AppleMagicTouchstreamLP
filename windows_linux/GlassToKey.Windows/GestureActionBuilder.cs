using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace GlassToKey;

// Uses the keyboard editor's catalog identities and shortcut formatter.
internal sealed class GestureActionEditor : StackPanel
{
    public string? Assignment { get; private set; }
    public GestureActionEditor(string? current,Action<string> applied)
    {
        var root=this; Margin=new(0,12,0,0);
        var toggles=new WrapPanel(); root.Children.Add(toggles);
        var modifiers=new[] { ("Ctrl",DispatchModifierFlags.Ctrl),("Shift",DispatchModifierFlags.Shift),("Alt",DispatchModifierFlags.Alt),("Win",DispatchModifierFlags.Meta) };
        var left=new[] {DispatchModifierFlags.LeftCtrl,DispatchModifierFlags.LeftShift,DispatchModifierFlags.LeftAlt,DispatchModifierFlags.LeftMeta};
        var right=new[] {DispatchModifierFlags.RightCtrl,DispatchModifierFlags.RightShift,DispatchModifierFlags.RightAlt,DispatchModifierFlags.RightMeta};
        var buttons=modifiers.Select(m=>new ToggleButton { Content=m.Item1, Tag=m.Item2, Padding=new(12,6,12,6), Margin=new(0,0,6,8) }).ToArray();
        foreach (var button in buttons) { button.SetResourceReference(StyleProperty,"ShortcutModifierToggleStyle"); toggles.Children.Add(button); }
        for(int i=0;i<buttons.Length;i++)
        {
            int index=i; var menu=new ContextMenu(); buttons[i].ContextMenu=menu;
            foreach(var choice in new[] {(modifiers[i].Item1,modifiers[i].Item2),("Left "+modifiers[i].Item1,left[i]),("Right "+modifiers[i].Item1,right[i])})
            { var item=new MenuItem {Header=choice.Item1}; item.Click+=(_,_)=> { buttons[index].Tag=choice.Item2; buttons[index].Content=choice.Item1; buttons[index].IsChecked=true; }; menu.Items.Add(item); }
        }
        var hyper=new Button { Content="Hyper", Padding=new(12,6,12,6), Margin=new(0,0,0,8) }; toggles.Children.Add(hyper);
        hyper.Click += (_,_)=> { for(int i=0;i<buttons.Length;i++) { buttons[i].Tag=modifiers[i].Item2; buttons[i].Content=modifiers[i].Item1; buttons[i].IsChecked=true; } };
        root.Children.Add(new TextBlock { Text="Key",Margin=new(0,0,0,4) });
        var keys=new ComboBox { ItemsSource=new[] { "None" }.Concat(DispatchShortcutHelper.ShortcutKeyLabels).ToArray(), SelectedIndex=0, IsEditable=true, MinHeight=28 };
        System.Windows.Automation.AutomationProperties.SetName(keys,"Shortcut key"); root.Children.Add(keys);
        if (current!=null && DispatchShortcutHelper.TryReadShortcut(current,out var flags,out string key))
        { for(int i=0;i<buttons.Length;i++) { var selected=flags&(modifiers[i].Item2|left[i]|right[i]); buttons[i].IsChecked=selected!=DispatchModifierFlags.None;
              if(selected!=DispatchModifierFlags.None) { buttons[i].Tag=selected; buttons[i].Content=selected==modifiers[i].Item2 ? modifiers[i].Item1 : DispatchShortcutHelper.FormatShortcut(selected,""); } }
          keys.Text=string.IsNullOrEmpty(key) ? "None" : key; }
        root.Children.Add(new TextBlock { Text="Or open an app, file, folder or URL", Margin=new(0,16,0,6) });
        var target=new TextBox { MinHeight=28, Padding=new(5), Text=AppLaunchActionHelper.TryParse(current,out var spec) ? spec.FileName : "" };
        System.Windows.Automation.AutomationProperties.SetName(target,"App, file, folder or URL"); root.Children.Add(target);
        root.Children.Add(new TextBlock { Text="Arguments (optional, for apps)", Margin=new(0,8,0,4) });
        var arguments=new TextBox { MinHeight=28, Padding=new(5),Text=AppLaunchActionHelper.TryParse(current,out var existing) ? existing.Arguments : "" };
        System.Windows.Automation.AutomationProperties.SetName(arguments,"Application arguments"); root.Children.Add(arguments);
        root.Children.Add(new TextBlock { Text="Leave the target empty to use the shortcut. Modifier-only shortcuts use Key: None. Hold cards can keep shortcut keys pressed until release.", TextWrapping=TextWrapping.Wrap, Foreground=Brushes.LightSlateGray, Margin=new(0,10,0,8) });
        var error=new TextBlock { TextWrapping=TextWrapping.Wrap, Foreground=Brushes.Salmon }; root.Children.Add(error);
        var actions=new StackPanel { Orientation=Orientation.Horizontal, HorizontalAlignment=HorizontalAlignment.Right, Margin=new(0,12,0,0) }; root.Children.Add(actions);
        var apply=new Button { Content="Apply",Padding=new(14,6,14,6) }; actions.Children.Add(apply);
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
            applied(Assignment);
        };
    }
}
