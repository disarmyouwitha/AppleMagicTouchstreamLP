namespace AppleMagicTouchstream;

public partial class MainWindow
{
    private void ConfigureKeyboardSavedText()
    {
        string layout=_preset.Name;int layer=_activeLayer,row=_selectedKeyRow,column=_selectedKeyColumn;var side=_selectedKeySide;
        string? custom=_selectedCustomButtonId;bool isCustom=_hasSelectedCustomButton;
        bool library=ShortcutTargetDropdownRadio.IsChecked==true;
        bool hold=ReferenceEquals(GetShortcutTargetCombo(),KeymapHoldCombo);
        string? current=GetShortcutTargetCombo().SelectedValue as string;
        KeyboardTextShortcutEditor.Configure(current,label=>
        {
            // Commit to the target captured when the field was displayed. A
            // simultaneous selection/focus change must never assign text elsewhere.
            if(library){EnsureActionOption(label,ShortcutActionSectionTitle,forceGroup:true);SaveShortcutLibraryAction(label);return;}
            if(_preset.Name!=layout)return;
            if(isCustom)
            {
                var button=_keymap.ResolveCustomButtons(layer,side).FirstOrDefault(b=>b.Id==custom);if(button==null)return;
                if(hold)button.Hold=new(){Label=label};else button.Primary=new(){Label=label};
            }
            else
            {
                if(row<0 || column<0)return;var geometry=side==TrackpadSide.Left ? _leftLayout:_rightLayout;
                if(row>=geometry.Labels.Length || column>=geometry.Labels[row].Length)return;
                string address=GridKeyPosition.StorageKey(side,row,column);
                var mapping=_keymap.ResolveMapping(layer,address,geometry.Labels[row][column]);
                _keymap.Mappings.TryAdd(layer,new());
                _keymap.Mappings[layer][address]=new() {Primary=hold ? mapping.Primary:new() {Label=label},Hold=hold ? new() {Label=label}:mapping.Hold,HoldForceThreshold=mapping.HoldForceThreshold};
            }
            EnsureActionOption(label,ShortcutActionSectionTitle,forceGroup:true);_keymap.Save();ApplyCoreSettings();UpdateLabelMatrices();RefreshKeymapEditor();
        },!_preset.IsSteno && (HasKeymapSelection() || library));
    }
}
