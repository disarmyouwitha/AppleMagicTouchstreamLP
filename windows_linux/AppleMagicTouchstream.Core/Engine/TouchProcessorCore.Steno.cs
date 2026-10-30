using System.Diagnostics;

namespace AppleMagicTouchstream;

internal sealed partial class TouchProcessorCore
{
    private readonly StenoChordEngine _stenoChord=new();
    public StenoOutputState StenoOutput { get; }=new();
    public bool IsSteno=>_leftLayout.IsSteno && _rightLayout.IsSteno;
    private byte _seenContactMask;
    private bool _layoutWaitForAllUp,_stenoAdmitted=true;
    private StenoRegion[][]? _stenoRegions;
    private int _stenoRegionLayer=-1;

    internal void SetLayoutTransitionContacts(byte contacts)
    { _seenContactMask=contacts; _layoutWaitForAllUp=contacts!=0; CancelSteno(); }
    internal void SetStenoAdmission(bool admitted)
    { if(_stenoAdmitted!=admitted) { _stenoAdmitted=admitted; CancelSteno(); } }
    internal void RemoveStenoDevice(TrackpadSide side)
    {
        _seenContactMask&=(byte)~(1<<(int)side); _stenoChord.RemoveDevice(side); StenoOutput.Invalidate();
        if(_seenContactMask==0) _layoutWaitForAllUp=false;
    }
    internal void TickSteno(long timestamp)
    { if(IsSteno && _stenoChord.Tick(timestamp/(double)Stopwatch.Frequency)) StenoOutput.Invalidate(); }
    private void CancelSteno()
    { _stenoChord.Cancel(_seenContactMask); _stenoRegions=null; StenoOutput.Invalidate(); }
    private void PrepareStenoLayouts(KeyLayout left,KeyLayout right)
    {
        bool next=left.IsSteno && right.IsSteno;
        if(!IsSteno && !next) return;
        ResetState(); _layoutWaitForAllUp=_seenContactMask!=0; StenoOutput.Configure(next);
        EnqueueDispatchEvent(DispatchEventKind.ReleaseAllKeyboard,0,DispatchMouseButton.None,0,DispatchEventFlags.None,
            TrackpadSide.Left,Stopwatch.GetTimestamp(),"steno_layout_change");
    }
    private bool ProcessStenoOrBarrier(TrackpadSide side,in InputFrame frame,ushort maxX,ushort maxY,long timestamp)
    {
        bool down=frame.ContactCount>InputFrame.MaxContacts;
        for(int i=0;i<frame.GetClampedContactCount();i++) down|=frame.GetContact(i).TipSwitch;
        if(down) _seenContactMask|=(byte)(1<<(int)side); else _seenContactMask&=(byte)~(1<<(int)side);
        if(_layoutWaitForAllUp)
        {
            _stenoChord.Cancel(_seenContactMask);
            if(_seenContactMask==0) _layoutWaitForAllUp=false;
            return true;
        }
        if(!IsSteno) return false;
        if(!_stenoAdmitted || !_typingEnabled) { _stenoChord.Cancel(_seenContactMask); return true; }
        if(_stenoRegions==null || _stenoRegionLayer!=_activeLayer) BuildStenoRegions();
        ulong mask=_stenoChord.Process(side,in frame,maxX,maxY,timestamp/(double)Stopwatch.Frequency,_stenoRegions![(int)side]);
        if(mask!=0)
            lock(StenoOutput.Sync)
                EnqueueDispatchEvent(DispatchEventKind.StenoStroke,0,DispatchMouseButton.None,0,DispatchEventFlags.None,
                    side,timestamp,GeminiPRPacket.RecordingLabel(mask),stenoMask:mask,stenoGeneration:StenoOutput.Generation);
        return true;
    }
    private void BuildStenoRegions()
    {
        _stenoRegions=new StenoRegion[2][]; _stenoRegionLayer=_activeLayer;
        for(int s=0;s<2;s++)
        {
            var layout=s==0 ? _leftLayout : _rightLayout; var regions=new List<StenoRegion>();
            for(int r=0;r<layout.Rects.Length;r++) for(int c=0;c<layout.Rects[r].Length;c++)
            {
                string label=_keymap.ResolveMapping(_activeLayer,GridKeyPosition.StorageKey((TrackpadSide)s,r,c),layout.Labels[r][c]).Primary.Label;
                if(!GeminiPRPacket.TryResolve(label,out var key)) continue;
                var rect=layout.Rects[r][c];
                // Match Mac's 1.5mm edge expansion, including upper/lower seams.
                rect=rect with { X=rect.X-1.5/160,Y=rect.Y-1.5/114.9,Width=rect.Width+3.0/160,Height=rect.Height+3.0/114.9 };
                regions.Add(new(key,KeyHitGeometry.FromRect(rect)));
            }
            _stenoRegions[s]=regions.ToArray();
        }
    }
}
