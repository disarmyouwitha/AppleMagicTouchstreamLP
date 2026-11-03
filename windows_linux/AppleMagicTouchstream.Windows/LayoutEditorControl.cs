using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
namespace AppleMagicTouchstream;

// Draft-only UI. Runtime geometry is compiled exclusively by the Apply callback.
internal sealed class LayoutEditorControl:Grid
{
    internal LayoutDocument Document { get; private set; }
    private readonly string _original;
    internal bool Dirty=>System.Text.Json.JsonSerializer.Serialize(Document,LayoutDocument.JsonOptions)!=_original;
    private bool _dragging;
    private readonly LayoutDocumentHistory _history=new();
    private readonly HashSet<Guid> _selection=new();
    private readonly EditorPad[] _pads;
    private readonly StackPanel _inspector=new();
    private readonly ToggleButton _mirror=new() { Content="◫ Mirror Edit",IsChecked=true,Margin=new(10,0,8,0) };
    private readonly ToggleButton _contacts=new() {Content="☝ Show Contacts"};
    private readonly Button _undo=new() {Content="↶"},_redo=new() {Content="↷"};
    private readonly Func<LayoutDocument> _reset;
    private readonly Action<LayoutDocument?> _finish;
    private readonly Action<bool> _showContacts;
    private readonly KeymapStore _map;
    private readonly ComboBox _layer=new() {ItemsSource=Enumerable.Range(0,4).Select(i=>"Layer"+i).ToArray(),SelectedIndex=0,MinWidth=90};
    private readonly ComboBox _side=new() {ItemsSource=new[]{"Left","Right"},SelectedIndex=1,MinWidth=80};
    private int _columnKeys=3;
    private bool _numericCommit;
    private string? _pendingPulse;
    internal int Layer=>Math.Max(0,_layer.SelectedIndex);
    internal LayoutEditorControl(LayoutDocument document,KeymapStore map,Func<LayoutDocument> reset,Action<LayoutDocument?> finish,Action<bool> showContacts,TouchState left,TouchState right)
    {
        Document=document.Copy();Document.InferMirrors();_original=System.Text.Json.JsonSerializer.Serialize(Document,LayoutDocument.JsonOptions);_map=map;_reset=reset;_finish=finish;_showContacts=showContacts;
        Background=new SolidColorBrush(Color.FromRgb(12,15,18));
        RowDefinitions.Add(new() {Height=GridLength.Auto});RowDefinitions.Add(new());
        ColumnDefinitions.Add(new());ColumnDefinitions.Add(new() {Width=new(333)});
        var toolbar=new DockPanel {Margin=new(8,8,8,16)};Grid.SetColumnSpan(toolbar,2);Children.Add(toolbar);
        var actions=new StackPanel {Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right};DockPanel.SetDock(actions,Dock.Right);toolbar.Children.Add(actions);
        actions.Children.Add(_undo);actions.Children.Add(_redo);actions.Children.Add(Button("⟲ Reset",()=>Edit(()=>{Document=_reset();_selection.Clear();},false)));actions.Children.Add(Button("Cancel",()=>_finish(null)));actions.Children.Add(Button("✓ Apply",()=>_finish(Document.Copy())));
        var title=new StackPanel {Orientation=Orientation.Horizontal,VerticalAlignment=VerticalAlignment.Center};toolbar.Children.Add(title);
        title.Children.Add(Text("▣ Layout Editor",17));title.Children.Add(_mirror);title.Children.Add(_contacts);
        _mirror.SetResourceReference(StyleProperty,"ShortcutModifierToggleStyle");_contacts.SetResourceReference(StyleProperty,"ShortcutModifierToggleStyle");
        _mirror.Click+=(_,_)=> {if(_mirror.IsChecked==true)_selection.IntersectWith(Document.Keys.Where(k=>k.Right==(_side.SelectedIndex==1)).Select(k=>k.Id));Refresh();};
        _undo.Click+=(_,_)=> { Document=_history.Undo(Document);Refresh(); };_redo.Click+=(_,_)=> { Document=_history.Redo(Document);Refresh(); };
        _contacts.Click+=(_,_)=> { bool enabled=_contacts.IsChecked==true;foreach(var p in _pads ?? []) p.ShowContacts(enabled);_showContacts(enabled); };
        var surfaces=new Grid {Margin=new(4,0,12,0)};Grid.SetRow(surfaces,1);Children.Add(surfaces);surfaces.ColumnDefinitions.Add(new());surfaces.ColumnDefinitions.Add(new());
        _pads=[new(this,false,left),new(this,true,right)];
        for(int i=0;i<2;i++) { Grid.SetColumn(_pads[i],i);_pads[i].Margin=new(8);surfaces.Children.Add(_pads[i]); }
        var scroll=new ScrollViewer {Content=_inspector,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,Margin=new(12,0,8,0)};Grid.SetColumn(scroll,1);Grid.SetRow(scroll,1);Children.Add(scroll);
        _layer.SelectionChanged+=(_,_)=> { _selection.Clear();Refresh(); };
        PreviewKeyDown+=(_,e)=>
        {
            if(_dragging)return;
            bool text=Keyboard.FocusedElement is TextBox or PasswordBox;
            if(e.Key==Key.Escape){_finish(null);e.Handled=true;}
            else if(!text && e.Key==Key.Return){_finish(Document.Copy());e.Handled=true;}
            else if(!text && (Keyboard.Modifiers&ModifierKeys.Control)!=0)
            {
                if(e.Key==Key.Z && (Keyboard.Modifiers&ModifierKeys.Shift)==0){Document=_history.Undo(Document);Refresh();e.Handled=true;}
                else if(e.Key==Key.Y || e.Key==Key.Z && (Keyboard.Modifiers&ModifierKeys.Shift)!=0){Document=_history.Redo(Document);Refresh();e.Handled=true;}
                else if(e.Key==Key.A){_selection.ReplaceWith(Document.Keys.Where(k=>k.Right==(_side.SelectedIndex==1) && k.Visible(Layer)).Select(k=>k.Id));Refresh();e.Handled=true;}
            }
        };
        Refresh();
    }
    private static TextBlock Text(string text,double size=12)=>new() {Text=text,FontSize=size,Foreground=Brushes.LightGray,TextWrapping=TextWrapping.Wrap,Margin=new(0,0,0,8)};
    private Button Button(string label,Action action)
    {
        var button=new Button {Content=label,Padding=new(8),Margin=new(3),MinHeight=38};
        void pulse()
        {
            var brush=new SolidColorBrush(Colors.DodgerBlue);button.BorderBrush=brush;button.BorderThickness=new(2);
            brush.BeginAnimation(SolidColorBrush.ColorProperty,new ColorAnimation(Colors.DodgerBlue,Colors.SlateGray,TimeSpan.FromMilliseconds(450)));
        }
        if(_pendingPulse==label){_pendingPulse=null;pulse();}
        button.Click+=(_,_)=> { if(_dragging)return;_pendingPulse=label;action();if(_pendingPulse==label){_pendingPulse=null;pulse();} };return button;
    }
    private void Refresh()
    {
        _selection.IntersectWith(Document.Keys.Select(k=>k.Id));_undo.IsEnabled=_history.CanUndo && !_dragging;_redo.IsEnabled=_history.CanRedo && !_dragging;
        foreach(var pad in _pads) pad.Redraw();BuildInspector();
    }
    private void Edit(Action edit,bool mirrorGeometry=true)
    {
        var before=Document.Copy();edit();
        if(_mirror.IsChecked==true && mirrorGeometry) Document.MirrorChanges(before,_selection);
        if(!Document.IsValid()) {Document=before;return;}
        if(System.Text.Json.JsonSerializer.Serialize(before,LayoutDocument.JsonOptions)==System.Text.Json.JsonSerializer.Serialize(Document,LayoutDocument.JsonOptions)) return;
        _history.Record(before);Refresh();
    }
    private void BuildInspector()
    {
        if(_numericCommit) return;
        _inspector.Children.Clear();_inspector.Children.Add(Text("Selection",16));_inspector.Children.Add(Text(_selection.Count==0 ? "Click a key, or drag a box around keys. Shift adds to selection.":$"{_selection.Count} selected"));
        if(_selection.Count>0)
        {
            bool side=Document.Keys.First(k=>_selection.Contains(k.Id)).Right;
            if(Document.Frame(_selection,side) is {} frame)
            {
                _inspector.Children.Add(Text("Selection size · mm"));
                Number("Width",frame.Rect.Width*160,mm=>Edit(()=>Document.Resize(_selection,mm/(frame.Rect.Width*160),frame.Independent ? 1:mm/(frame.Rect.Width*160)))) ;
                Number("Height",frame.Rect.Height*114.9,mm=>Edit(()=>Document.Resize(_selection,frame.Independent ? 1:mm/(frame.Rect.Height*114.9),mm/(frame.Rect.Height*114.9))));
                _inspector.Children.Add(Text("Selection spacing · mm"));
                if(Document.Spacing(_selection,side,true) is {} x) Number("X",x,mm=>Edit(()=>Document.SetSpacing(_selection,true,mm)));
                if(Document.Spacing(_selection,side,false) is {} y) Number("Y",y,mm=>Edit(()=>Document.SetSpacing(_selection,false,mm)));
            }
        }
        _inspector.Children.Add(new Separator {Margin=new(0,12,0,12)});_inspector.Children.Add(Text("Arrange",16));
        var tools=new UniformGrid {Columns=3};_inspector.Children.Add(tools);
        void tool(string label,Action action,int minimum=1) { var b=Button(label,action);b.IsEnabled=_selection.Count>=minimum;b.MinHeight=64;tools.Children.Add(b); }
        tool("⇲\nSmaller 5%",()=>Edit(()=>Document.Resize(_selection,.95,.95)));
        tool("⇱\nLarger 5%",()=>Edit(()=>Document.Resize(_selection,1.05,1.05)));
        tool("↶\nRotate left 5°",()=>Edit(()=>Document.Rotate(_selection,-5)));
        tool("▤\nAlign column",()=>Edit(()=>Document.Align(_selection,true)),2);
        tool("▥\nAlign row",()=>Edit(()=>Document.Align(_selection,false)),2);
        tool("↷\nRotate right 5°",()=>Edit(()=>Document.Rotate(_selection,5)));
        tool("↔\nSpace horizontally",()=>Edit(()=>EvenSpacing(true)),2);
        tool("↕\nSpace vertically",()=>Edit(()=>EvenSpacing(false)),2);
        tool("▣\nDuplicate",()=>Edit(()=>
        {
            bool side=_side.SelectedIndex==1;var copies=Document.Duplicate(_mirror.IsChecked==true ? Document.Paired(_selection):_selection);
            if(_mirror.IsChecked==true)foreach(var key in Document.Keys.Where(k=>copies.Contains(k.Id) && k.Right!=side))key.Rect=key.Rect with {X=key.Rect.X-.04};
            _selection.ReplaceWith(_mirror.IsChecked==true ? Document.Keys.Where(k=>copies.Contains(k.Id) && k.Right==side).Select(k=>k.Id):copies);
        },false));
        tool("⇥⇤\nSpacing −5%",()=>Edit(()=>Document.ScaleSpacing(_selection,.95)),2);
        tool("⇤⇥\nSpacing +5%",()=>Edit(()=>Document.ScaleSpacing(_selection,1.05)),2);
        tool("⌫\nDelete",()=>Edit(()=> {Document.Delete(_mirror.IsChecked==true ? Document.Paired(_selection):_selection);_selection.Clear();},false));
        _inspector.Children.Add(new Separator {Margin=new(0,14,0,12)});_inspector.Children.Add(Text("Add",16));
        if(_side.Parent is Panel oldSide)oldSide.Children.Remove(_side);
        if(_layer.Parent is Panel oldLayer)oldLayer.Children.Remove(_layer);
        var options=new Grid();options.ColumnDefinitions.Add(new());options.ColumnDefinitions.Add(new());_inspector.Children.Add(options);
        options.Children.Add(_side);Grid.SetColumn(_layer,1);options.Children.Add(_layer);
        var add=new UniformGrid {Columns=3,Margin=new(0,10,0,0)};_inspector.Children.Add(add);
        add.Children.Add(Button("⊞\nKey",()=>AddKeys(1)));
        add.Children.Add(Button("▤\nColumn",()=>AddKeys(_columnKeys)));
        var count=new ComboBox {ItemsSource=Enumerable.Range(1,12).Select(i=>$"{i} keys").ToArray(),SelectedIndex=_columnKeys-1,VerticalAlignment=VerticalAlignment.Center};count.SelectionChanged+=(_,_)=>_columnKeys=count.SelectedIndex+1;add.Children.Add(count);
        _inspector.Children.Add(Text("1 mm snap · drag to move · drag empty space to select. Resize the selection using its single corner handle."));
    }
    private void EvenSpacing(bool x)
    { foreach(bool side in new[]{false,true}) { var ids=Document.Keys.Where(k=>k.Right==side && _selection.Contains(k.Id)).Select(k=>k.Id).ToHashSet(); if(Document.Spacing(ids,side,x) is {} gap) Document.SetSpacing(ids,x,gap); } }
    private void Number(string label,double value,Action<double> commit)
    {
        var row=new Grid {Margin=new(0,0,0,6)};row.ColumnDefinitions.Add(new());row.ColumnDefinitions.Add(new());row.Children.Add(Text(label));
        var box=new TextBox {Text=value.ToString("0.###",CultureInfo.InvariantCulture),MinHeight=28};Grid.SetColumn(box,1);row.Children.Add(box);_inspector.Children.Add(row);
        double committed=value;
        void save() { if(double.TryParse(box.Text,NumberStyles.Float,CultureInfo.InvariantCulture,out var mm) && double.IsFinite(mm) && Math.Abs(mm-committed)>1e-12) { committed=mm;_numericCommit=true;try {commit(mm);} finally {_numericCommit=false;} Dispatcher.BeginInvoke(Refresh); } }
        box.LostKeyboardFocus+=(_,_)=>save();box.KeyDown+=(_,e)=> {if(e.Key==Key.Return) {save();e.Handled=true;} }; // Validation on commit permits empty/zero intermediate edits.
    }
    private void AddKeys(int count)
    {
        Edit(()=> { _selection.Clear(); bool right=_side.SelectedIndex==1;for(int i=0;i<count;i++) {var rect=new NormalizedRect(.4,.15+i*.17,.08,.16);var id=_mirror.IsChecked==true ? Document.AddMirrored(right,Layer,rect):Document.Add(right,Layer,rect);_selection.Add(id);} },false);
    }
    private sealed class EditorPad:Grid
    {
        private readonly LayoutEditorControl _editor; private readonly bool _right;
        private readonly KeyCanvas _keys; private readonly ContactCanvas _contacts;
        internal EditorPad(LayoutEditorControl editor,bool right,TouchState state)
        { _editor=editor;_right=right;_keys=new(editor,right);_contacts=new(state);Children.Add(_keys);Children.Add(_contacts); }
        internal void Redraw()=>_keys.InvalidateVisual();
        internal void ShowContacts(bool show)=>_contacts.Show(show);
    }
    private sealed class ContactCanvas:FrameworkElement
    {
        private readonly TouchState _state;private readonly DispatcherTimer _timer=new() {Interval=TimeSpan.FromMilliseconds(33)};
        internal ContactCanvas(TouchState state) { _state=state;IsHitTestVisible=false;Visibility=Visibility.Collapsed;_timer.Tick+=(_,_)=>InvalidateVisual();Unloaded+=(_,_)=>_timer.Stop(); }
        internal void Show(bool visible) {Visibility=visible ? Visibility.Visible:Visibility.Collapsed;if(visible) _timer.Start();else _timer.Stop();}
        protected override void OnRender(DrawingContext dc)
        { Span<TouchContact> contacts=stackalloc TouchContact[PtpReport.MaxContacts];int count=_state.Snapshot(contacts,out ushort x,out ushort y,out _);if(x==0 || y==0)return;var pad=KeyCanvas.Pad(ActualWidth,ActualHeight);foreach(var c in contacts[..count]) dc.DrawEllipse(Brushes.Black,new Pen(Brushes.SlateGray,1.5),new Point(pad.X+c.X/(double)x*pad.Width,pad.Y+c.Y/(double)y*pad.Height),5,5); }
    }
    private sealed class KeyCanvas:FrameworkElement
    {
        private readonly LayoutEditorControl _editor;private readonly bool _right;
        private Point? _start;private LayoutDocument? _before;private HashSet<Guid> _sources=new();private bool _resize,_marquee;private NormalizedRect? _box;
        internal KeyCanvas(LayoutEditorControl editor,bool right)
        { _editor=editor;_right=right;Focusable=true;MouseLeftButtonDown+=Down;MouseMove+=Move;MouseLeftButtonUp+=Up;LostMouseCapture+=(_,_)=> {if(_before!=null) End();};KeyDown+=(_,e)=> {if(e.Key==Key.Delete) {_editor.Edit(()=>_editor.Document.Delete(_editor._mirror.IsChecked==true ? _editor.Document.Paired(_editor._selection):_editor._selection),false);e.Handled=true;} }; }
        internal static Rect Pad(double width,double height)
        { double w=Math.Max(1,Math.Min(width-12,160*2.7)),h=w*114.9/160;if(h>height-35) {h=Math.Max(1,height-35);w=h*160/114.9;} return new((width-w)/2,28,w,h); }
        private Point Position(MouseEventArgs e) {var p=e.GetPosition(this);var r=Pad(ActualWidth,ActualHeight);return new((p.X-r.X)/r.Width,(p.Y-r.Y)/r.Height);}
        private void Down(object sender,MouseButtonEventArgs e)
        {
            var p=Position(e);if(p.X<0 || p.X>1 || p.Y<0 || p.Y>1)return;Focus();
            _editor._side.SelectedIndex=_right ? 1:0;
            if(_editor._mirror.IsChecked==true)_editor._selection.IntersectWith(_editor.Document.Keys.Where(k=>k.Right==_right).Select(k=>k.Id));
            var frame=_editor.Document.Frame(_editor._selection,_right);var pad=Pad(ActualWidth,ActualHeight);
            _resize=frame is {} f && Math.Abs(p.X-Corner(f.Rect).X)*pad.Width<10 && Math.Abs(p.Y-Corner(f.Rect).Y)*pad.Height<10;
            var hit=_editor.Document.Hit(_right,_editor.Layer,p.X,p.Y);bool shift=(Keyboard.Modifiers&ModifierKeys.Shift)!=0;
            if(!_resize) { if(hit is {} id) { if(shift) {if(!_editor._selection.Add(id))_editor._selection.Remove(id);} else if(!_editor._selection.Contains(id)) {_editor._selection.Clear();_editor._selection.Add(id);} } else if(!shift)_editor._selection.Clear(); }
            _editor._dragging=true;_before=_editor.Document.Copy();_start=p;_sources=_editor._selection.ToHashSet();_marquee=!_resize && hit==null;CaptureMouse();_editor.Refresh();e.Handled=true;
        }
        private void Move(object sender,MouseEventArgs e)
        {
            if(_start is not {} start || _before==null)return;var p=Position(e);double dx=Math.Round((p.X-start.X)*160)/160,dy=Math.Round((p.Y-start.Y)*114.9)/114.9;
            _editor.Document=_before.Copy();
            if(_marquee) {_box=new(Math.Min(start.X,p.X),Math.Min(start.Y,p.Y),Math.Abs(p.X-start.X),Math.Abs(p.Y-start.Y));_editor._selection.ReplaceWith(_sources.Concat(_before.Marquee(_right,_editor.Layer,_box.Value)));}
            else if(_resize && _before.Frame(_sources,_right) is {} f) {double a=f.Rect.RotationDegrees*Math.PI/180,c=Math.Cos(a),s=Math.Sin(a);double lx=(dx*160*c+dy*114.9*s)/160,ly=(-dx*160*s+dy*114.9*c)/114.9;double sx=Math.Max(.01,(f.Rect.Width+lx)/f.Rect.Width),sy=Math.Max(.01,(f.Rect.Height+ly)/f.Rect.Height);if(!f.Independent)sy=sx;_editor.Document.Resize(_sources,sx,sy); }
            else _editor.Document.Translate(_sources,dx,dy);
            if(!_marquee && _editor._mirror.IsChecked==true)_editor.Document.MirrorChanges(_before,_sources);
            foreach(var pad in _editor._pads)pad.Redraw();e.Handled=true;
        }
        private void Up(object sender,MouseButtonEventArgs e) {End();ReleaseMouseCapture();e.Handled=true;}
        private void End()
        { if(_before!=null && !_marquee) {if(_editor.Document.IsValid()) {if(System.Text.Json.JsonSerializer.Serialize(_before,LayoutDocument.JsonOptions)!=System.Text.Json.JsonSerializer.Serialize(_editor.Document,LayoutDocument.JsonOptions)){_editor._history.Record(_before);}}else _editor.Document=_before;} _before=null;_start=null;_box=null;_editor._dragging=false;_editor.Refresh(); }
        protected override void OnRender(DrawingContext dc)
        {
            var pad=Pad(ActualWidth,ActualHeight);dc.DrawText(Format(_right ? "Right trackpad":"Left trackpad",14),new(pad.X,3));dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(18,22,28)),new Pen(Brushes.SlateGray,1),pad,10,10);
            var gridPen=new Pen(new SolidColorBrush(Color.FromArgb(30,180,180,180)),.5);
            for(int i=5;i<160;i+=5)dc.DrawLine(gridPen,new(pad.X+i/160.0*pad.Width,pad.Y),new(pad.X+i/160.0*pad.Width,pad.Bottom));
            for(int i=5;i<114;i+=5)dc.DrawLine(gridPen,new(pad.X,pad.Y+i/114.9*pad.Height),new(pad.Right,pad.Y+i/114.9*pad.Height));
            foreach(var key in _editor.Document.Keys.Where(k=>k.Right==_right && k.Visible(_editor.Layer)))
            {
                var r=key.DisplayRect;var rect=new Rect(pad.X+r.X*pad.Width,pad.Y+r.Y*pad.Height,r.Width*pad.Width,r.Height*pad.Height);var center=new Point(rect.X+rect.Width/2,rect.Y+rect.Height/2);dc.PushTransform(new RotateTransform(r.RotationDegrees,center.X,center.Y));
                bool selected=_editor._selection.Contains(key.Id);dc.DrawRoundedRectangle(selected ? new SolidColorBrush(Color.FromArgb(100,0,122,255)):Brushes.Transparent,new Pen(selected ? Brushes.DodgerBlue:Brushes.Gray,selected ? 2:1),rect,5,5);
                string source=GridKeyPosition.StorageKey(_right ? TrackpadSide.Right:TrackpadSide.Left,key.CopySourceRow ?? key.Row,key.CopySourceColumn ?? key.Column);
                string label=_editor._map.ResolveMapping(_editor.Layer,source,key.Label).Primary.Label;if(TextShortcutReference.TryRead(label,out _))label="Text";
                var text=Format(GeminiPRPacket.Display(label),Math.Max(9,Math.Min(13,rect.Width/5)));dc.DrawText(text,new(center.X-text.Width/2,center.Y-text.Height/2));dc.Pop();
            }
            if(_editor.Document.Frame(_editor._selection,_right) is {} frame)
            {var r=frame.Rect;var box=new Rect(pad.X+r.X*pad.Width,pad.Y+r.Y*pad.Height,r.Width*pad.Width,r.Height*pad.Height);dc.PushTransform(new RotateTransform(r.RotationDegrees,box.X+box.Width/2,box.Y+box.Height/2));dc.DrawRectangle(null,new Pen(Brushes.DodgerBlue,1),box);dc.DrawRectangle(Brushes.DodgerBlue,null,new Rect(box.Right-5,box.Bottom-5,10,10));dc.Pop();}
            if(_box is {} b)dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(30,0,122,255)),new Pen(Brushes.DodgerBlue,1),new Rect(pad.X+b.X*pad.Width,pad.Y+b.Y*pad.Height,b.Width*pad.Width,b.Height*pad.Height));
        }
        private static Point Corner(NormalizedRect r)
        {double a=r.RotationDegrees*Math.PI/180,c=Math.Cos(a),s=Math.Sin(a);return new(r.CenterX+(r.Width*160/2*c-r.Height*114.9/2*s)/160,r.CenterY+(r.Width*160/2*s+r.Height*114.9/2*c)/114.9);}
        private static FormattedText Format(string text,double size)=>new(text,CultureInfo.InvariantCulture,FlowDirection.LeftToRight,new Typeface("Segoe UI"),size,Brushes.LightGray,1);
    }
}
internal static class EditorSelectionExtensions
{ internal static void ReplaceWith(this HashSet<Guid> set,IEnumerable<Guid> values) {var copy=values.ToArray();set.Clear();set.UnionWith(copy);} }
