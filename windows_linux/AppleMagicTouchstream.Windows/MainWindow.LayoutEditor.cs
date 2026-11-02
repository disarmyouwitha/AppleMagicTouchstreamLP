using System.Windows;
namespace AppleMagicTouchstream;

public partial class MainWindow
{
    private LayoutEditorControl? _layoutEditor;
    private KeymapStore? _layoutEditorKeymap;
    private long _pendingStenoKeys;
    private void ObserveStenoKeys(ulong mask)=>System.Threading.Interlocked.Or(ref _pendingStenoKeys,unchecked((long)mask));
    private void UpdateStenoFlashes()
    {
        ulong mask=unchecked((ulong)System.Threading.Interlocked.Exchange(ref _pendingStenoKeys,0));
        long now=System.Diagnostics.Stopwatch.GetTimestamp();
        foreach(var surface in new[]{LeftSurface,RightSurface})
        {
            foreach(var key in surface.FlashKeys.Where(p=>p.Value<=now).Select(p=>p.Key).ToArray())surface.FlashKeys.Remove(key);
            if(mask==0)continue;var layout=surface.Layout;if(layout==null)continue;
            var legends=new List<string>();
            for(int row=0;row<layout.Rects.Length;row++)for(int col=0;col<layout.Rects[row].Length;col++)
            {
                if(!layout.Visible(row,col,_activeLayer))continue;
                string label=_keymap.ResolveMapping(_activeLayer,GridKeyPosition.StorageKey(surface.Side,row,col),layout.Labels[row][col]).Primary.Label;
                if(GeminiPRPacket.TryResolve(label,out var key) && (mask&(1UL<<(int)key))!=0)
                {surface.FlashKeys[(row,col)]=now+System.Diagnostics.Stopwatch.Frequency/2;legends.Add(GeminiPRPacket.Legend(key));}
            }
            if(legends.Count>0)surface.LastHitLabel=string.Join(" + ",legends);
        }
    }
    private void BeginLayoutEditor()
    {
        if(_layoutEditor!=null || IsReplayMode) return;
        var document=_settings.LayoutDocuments.GetValueOrDefault(_preset.Name) ?? LayoutDocument.Seed(_leftLayout,_rightLayout);
        document=document.Copy();
        var draft=new KeymapStore();
        if(!draft.TryImportFromJson(_keymap.SerializeToJson(),out _)) return;
        draft.SetActiveLayout(_preset.Name);document.MigrateLegacyButtons(draft);_layoutEditorKeymap=draft;
        _layoutEditor=new(document,draft,()=>MacLayoutTemplates.Get(_preset),FinishLayoutEditor,show=>SetRuntimeLayoutEditor(true,show),_left.State,_right.State);
        LayoutEditorHost.Children.Add(_layoutEditor);LayoutEditorHost.Visibility=Visibility.Visible;
        TrackpadScrollViewer.Visibility=Visibility.Collapsed;ControlsPaneBorder.Visibility=Visibility.Collapsed;InspectorResizeThumb.Visibility=Visibility.Collapsed;GestureSettingsTab.IsEnabled=false;
        SetRuntimeLayoutEditor(true,false);
    }
    private void SetRuntimeLayoutEditor(bool active,bool showContacts)
    {
        _runtimeService?.SetLayoutEditor(active,showContacts);
        _handGestures?.Configure(_settings,active,showContacts);
        _touchActor?.SetLayoutEditor(active);
    }
    private void FinishLayoutEditor(LayoutDocument? document)
    {
        if(document!=null)
        {
            if(!document.IsValid()) return;
            var draft=_layoutEditorKeymap!;document.ApplyMappings(draft);
            _keymap.Mappings.Clear();
            foreach(var pair in draft.Mappings) _keymap.Mappings[pair.Key]=pair.Value;
            _keymap.CustomButtons.Clear();_settings.LayoutDocuments[_preset.Name]=document.Copy();_keymap.Save();
        }
        _layoutEditor=null;_layoutEditorKeymap=null;LayoutEditorHost.Children.Clear();LayoutEditorHost.Visibility=Visibility.Collapsed;
        TrackpadScrollViewer.Visibility=Visibility.Visible;ControlsPaneBorder.Visibility=Visibility.Visible;InspectorResizeThumb.Visibility=Visibility.Visible;GestureSettingsTab.IsEnabled=true;
        _activeLayer=0;_settings.ActiveLayer=0;LayerCombo.SelectedIndex=0;
        RebuildLayouts();ApplyCoreSettings();SetRuntimeLayoutEditor(false,false);SaveSettings();
    }
}
