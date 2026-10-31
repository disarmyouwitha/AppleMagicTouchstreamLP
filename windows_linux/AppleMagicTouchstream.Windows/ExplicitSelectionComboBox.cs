using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;

namespace AppleMagicTouchstream;

// Plover output must not type-search a closed settings selector or change it
// with arrow/wheel events after the user has made their selection.
public sealed class ExplicitSelectionComboBox : ComboBox
{
    public ExplicitSelectionComboBox() { IsTextSearchEnabled=false; SetResourceReference(StyleProperty,typeof(ComboBox)); }
    protected override void OnPreviewTextInput(TextCompositionEventArgs e)
    {
        e.Handled=true;
    }
    protected override void OnPreviewMouseWheel(MouseWheelEventArgs e)
    {
        if(!IsDropDownOpen) { e.Handled=true; return; }
        base.OnPreviewMouseWheel(e);
    }
    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        bool openKey=e.Key==Key.F4 || (e.Key==Key.Down && (Keyboard.Modifiers&ModifierKeys.Alt)!=0);
        if(!IsDropDownOpen && !openKey && e.Key is Key.Up or Key.Down or Key.Left or Key.Right or Key.Home or Key.End or Key.PageUp or Key.PageDown or Key.Space or Key.Enter)
        { e.Handled=true; return; }
        base.OnPreviewKeyDown(e);
    }
    protected override void OnDropDownClosed(System.EventArgs e)
    {
        base.OnDropDownClosed(e);
        Dispatcher.BeginInvoke(DispatcherPriority.Input,()=>
        {
            if(!IsDropDownOpen && IsKeyboardFocusWithin)
            {
                Keyboard.ClearFocus();
                if(Window.GetWindow(this) is {} window) FocusManager.SetFocusedElement(window,null);
            }
        });
    }
}
