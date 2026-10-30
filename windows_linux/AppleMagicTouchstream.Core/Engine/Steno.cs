using System.Diagnostics;

namespace AppleMagicTouchstream;

// Stable identities and wire order match the Mac implementation and Plover's
// Gemini PR chart. These are steno actions, never native keyboard keycodes.
public enum StenoKey : ushort
{
    Fn,N1,N2,N3,N4,N5,N6,S1,S2,TL,KL,PL,WL,HL,RL,A,O,ST1,ST2,RES1,RES2,
    PWR,ST3,ST4,E,U,FR,RR,PR,BR,LR,GR,TR,SR,DR,N7,N8,N9,NA,NB,NC,ZR
}
public static class GeminiPRPacket
{
    public const ulong KeyMask=(1UL<<42)-1;
    private static readonly string[] Legends=["Fn","#1","#2","#3","#4","#5","#6","S-","S-","T-","K-","P-","W-","H-",
        "R-","A","O","*","*","res1","res2","pwr","*","*","E","U","-F","-R","-P","-B","-L","-G","-T","-S","-D","#7","#8","#9","#A","#B","#C","-Z"];
    public static string Label(StenoKey key)=>key==StenoKey.Fn ? "STN_FN" : "STN_"+key;
    public static string Legend(StenoKey key)=>Legends[(int)key];
    public static bool TryResolve(string? label,out StenoKey key)
    {
        key=default;
        if(label=="STN_FN") { key=StenoKey.Fn; return true; }
        return label!=null && label.StartsWith("STN_",StringComparison.Ordinal) && Enum.TryParse(label[4..],out key)
            && (uint)key<42 && Label(key)==label;
    }
    public static string Display(string label)=>TryResolve(label,out var key) ? Legend(key) : label;
    public static void Write(ulong mask,Span<byte> bytes)
    {
        if(bytes.Length<6 || mask==0 || (mask&~KeyMask)!=0) throw new ArgumentException("Invalid Gemini PR stroke.");
        bytes[..6].Clear(); bytes[0]=0x80;
        for(int i=0;i<42;i++) if((mask&(1UL<<i))!=0) bytes[i/7]|=(byte)(0x40>>(i%7));
    }
    public static string RecordingLabel(ulong mask) { Span<byte> bytes=stackalloc byte[6]; Write(mask,bytes); return "GeminiPR:"+Convert.ToHexString(bytes); }
}

public sealed class StenoOutputState
{
    public object Sync { get; }=new();
    public long Generation { get; private set; }=1;
    public bool Enabled { get; private set; }
    public void Configure(bool enabled) { lock(Sync) { Enabled=enabled; Generation++; } }
    public void Invalidate() { lock(Sync) Generation++; }
    public bool IsCurrent(long generation) { lock(Sync) return Enabled && Generation==generation; }
}

public readonly record struct StenoRegion(StenoKey Key,KeyHitGeometry Geometry);

public sealed class StenoChordEngine
{
    private ulong _chord;
    private byte _down;
    private bool _blocked;
    private readonly double[] _times=[-1,-1];
    public byte DownPads=>_down;
    public bool FrameInvalidated { get; private set; }
    public void Cancel(byte? downPads=null)
    {
        if(downPads.HasValue) _down=downPads.Value;
        _chord=0; _blocked=_down!=0; _times[0]=_times[1]=-1;
    }
    public void RemoveDevice(TrackpadSide side) { _down&=(byte)~(1<<(int)side); Cancel(); }
    public bool Tick(double now)
    {
        for(int i=0;i<2;i++) if((_down&(1<<i))!=0 && _times[i]>=0 && now-_times[i]>.25)
        { Cancel(); return true; }
        return false;
    }
    public ulong Process(TrackpadSide side,in InputFrame frame,ushort maxX,ushort maxY,double time,ReadOnlySpan<StenoRegion> regions)
    {
        FrameInvalidated=Tick(time);
        int index=(int)side; if((uint)index>1) return 0;
        bool valid=double.IsFinite(time) && time>=0 && maxX>0 && maxY>0 && frame.ContactCount<=InputFrame.MaxContacts
            && (_times[index]<0 || time>_times[index]);
        if(_times[index]>=0 && (_down&(1<<index))!=0 && time-_times[index]>.25) valid=false;
        int count=0; ulong keys=0;
        for(int i=0;i<frame.GetClampedContactCount();i++)
        {
            var contact=frame.GetContact(i); if(!contact.TipSwitch) continue; count++;
            if(contact.X>maxX || contact.Y>maxY) { valid=false; continue; }
            for(int j=0;j<i;j++) if(frame.GetContact(j).TipSwitch && frame.GetContact(j).Id==contact.Id) valid=false;
            double x=contact.X/(double)maxX,y=contact.Y/(double)maxY;
            foreach(var region in regions) if(region.Geometry.Contains(x,y)) keys|=1UL<<(int)region.Key;
        }
        if(frame.ContactCount>InputFrame.MaxContacts) count=Math.Max(count,1);
        if(count>0) _down|=(byte)(1<<index); else _down&=(byte)~(1<<index);
        _times[index]=double.IsFinite(time) ? time : -1;
        if(!valid) { FrameInvalidated=true; _chord=0; _blocked=_down!=0; return 0; }
        if(_blocked) { if(_down==0) _blocked=false; return 0; }
        _chord|=keys;
        if(_down!=0) return 0;
        ulong stroke=_chord; _chord=0; return stroke;
    }
}

public static class StenoLayoutDefinition
{
    private static readonly StenoKey?[][] Left=[ [StenoKey.N1], [StenoKey.S1,StenoKey.TL,StenoKey.PL,StenoKey.HL,StenoKey.ST1],
        [StenoKey.S2,StenoKey.KL,StenoKey.WL,StenoKey.RL], [StenoKey.A,StenoKey.O] ];
    private static readonly StenoKey?[][] Right=[ [StenoKey.N6], [StenoKey.ST3,StenoKey.FR,StenoKey.PR,StenoKey.LR,StenoKey.TR,StenoKey.DR],
        [StenoKey.RR,StenoKey.BR,StenoKey.GR,StenoKey.SR,StenoKey.ZR], [StenoKey.E,StenoKey.U] ];
    private static readonly StenoKey?[][] VoyagerLeft=[ [StenoKey.N5,StenoKey.N4,StenoKey.N3,StenoKey.N2,StenoKey.N1,StenoKey.NC],
        [StenoKey.ST1,StenoKey.HL,StenoKey.PL,StenoKey.TL,StenoKey.S1,null], [StenoKey.ST2,StenoKey.RL,StenoKey.WL,StenoKey.KL,StenoKey.S2,null], [StenoKey.A,StenoKey.O] ];
    private static readonly StenoKey?[][] VoyagerRight=[ [StenoKey.N6,StenoKey.N7,StenoKey.N8,StenoKey.N9,StenoKey.NA,StenoKey.NB],
        [StenoKey.ST3,StenoKey.FR,StenoKey.PR,StenoKey.LR,StenoKey.TR,StenoKey.DR], [StenoKey.ST4,StenoKey.RR,StenoKey.BR,StenoKey.GR,StenoKey.SR,StenoKey.ZR], [StenoKey.E,StenoKey.U] ];
    public static string[][] Labels(bool voyager,bool left)=>(voyager ? left ? VoyagerLeft : VoyagerRight : left ? Left : Right)
        .Select(row=>row.Select(key=>key.HasValue ? GeminiPRPacket.Label(key.Value) : "None").ToArray()).ToArray();
    public static KeyLayout Build(TrackpadLayoutPreset preset,bool left,ColumnLayoutSettings[] columns,KeymapStore? map,double spacing)
    {
        bool voyager=preset.Name=="STENO Voyager";
        var rows=new List<NormalizedRect[]>();
        if(voyager) rows.AddRange(LayoutBuilder.BuildLayout(TrackpadLayoutPreset.SixByThree,160,114.9,18,17,columns,left,spacing).Rects);
        else if(left)
        {
            rows.Add([new(.06,.1,.66,.05)]);
            rows.Add(Enumerable.Range(0,4).Select(i=>new NormalizedRect(.06+i*.17,.18,.15,.23)).Append(new(.76,.18,.16,.48)).ToArray());
            rows.Add(Enumerable.Range(0,4).Select(i=>new NormalizedRect(.06+i*.17,.43,.15,.23)).ToArray());
        }
        else
        {
            rows.Add([new(.22,.1,.72,.05)]);
            rows.Add(new[] {new NormalizedRect(.04,.18,.15,.48)}.Concat(Enumerable.Range(0,5).Select(i=>new NormalizedRect(.22+i*.145,.18,.13,.23))).ToArray());
            rows.Add(Enumerable.Range(0,5).Select(i=>new NormalizedRect(.22+i*.145,.43,.13,.23)).ToArray());
        }
        rows.Add(left ? [new(.56,.79,.15,.18),new(.76,.79,.15,.18)] : [new(.06,.79,.15,.18),new(.26,.79,.15,.18)]);
        for(int r=0;r<rows.Count;r++) for(int c=0;c<rows[r].Length;c++)
            if(map!=null) rows[r][c]=LayoutBuilder.ApplyKeyGeometryOverride(rows[r][c],map.ResolveKeyGeometry(GridKeyPosition.StorageKey(left ? TrackpadSide.Left : TrackpadSide.Right,r,c)));
        return new(rows.ToArray(),Labels(voyager,left),isSteno:true);
    }
}
