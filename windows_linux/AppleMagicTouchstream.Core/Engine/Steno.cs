using System.Diagnostics;

namespace AppleMagicTouchstream;

// Stable identities and wire order match the Mac implementation and Plover's
// Gemini PR chart. These are steno actions, never native keyboard keycodes.
public enum StenoHapticMode { Off,KeyContact,ChordRelease }

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
    private readonly ulong[] _touchingKeys=new ulong[2];
    private byte _strokePads,_pendingTouch;
    private readonly double[] _touchDue=new double[2];
    public byte TouchFeedbackPads {get;private set;}
    public ulong NewlyPressedKeys { get; private set; }
    public byte StrokePads { get; private set; }
    private byte _down;
    private bool _blocked;
    private readonly double[] _times=[-1,-1];
    public byte DownPads=>_down;
    public bool FrameInvalidated { get; private set; }
    public void Cancel(byte? downPads=null)
    {
        if(downPads.HasValue) _down=downPads.Value;
        _chord=0; _blocked=_down!=0; _times[0]=_times[1]=-1;
        _touchingKeys[0]=_touchingKeys[1]=0; _strokePads=_pendingTouch=0; NewlyPressedKeys=0; StrokePads=TouchFeedbackPads=0;
    }
    public void RemoveDevice(TrackpadSide side) { _down&=(byte)~(1<<(int)side); Cancel(); }
    public byte DrainSettledTouch(double now)
    {
        byte pads=0;
        for(int i=0;i<2;i++)if((_pendingTouch&(1<<i))!=0 && now>=_touchDue[i]){pads|=(byte)(1<<i);_pendingTouch&=(byte)~(1<<i);}
        return pads;
    }
    public bool Tick(double now)
    {
        for(int i=0;i<2;i++) if((_down&(1<<i))!=0 && _times[i]>=0 && now-_times[i]>.25)
        { Cancel(); return true; }
        return false;
    }
    public ulong Process(TrackpadSide side,in InputFrame frame,ushort maxX,ushort maxY,double time,ReadOnlySpan<StenoRegion> regions)
    {
        NewlyPressedKeys=0; StrokePads=TouchFeedbackPads=0;
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
        if(!valid) { FrameInvalidated=true; Cancel(); return 0; }
        if(_blocked) { if(_down==0) _blocked=false; return 0; }
        NewlyPressedKeys=keys&~_touchingKeys[index]; _touchingKeys[index]=keys;
        byte pad=(byte)(1<<index);
        if(NewlyPressedKeys!=0 && (_pendingTouch&pad)==0) {_pendingTouch|=pad;_touchDue[index]=time+.08;}
        if((_pendingTouch&pad)!=0 && time>=_touchDue[index]){TouchFeedbackPads|=pad;_pendingTouch&=(byte)~pad;}
        if(keys!=0) _strokePads|=(byte)(1<<index);
        _chord|=keys;
        if(_down!=0) return 0;
        ulong stroke=_chord; _chord=0; StrokePads=_strokePads; _strokePads=0;
        if(stroke!=0)TouchFeedbackPads|=_pendingTouch;
        _pendingTouch=0;return stroke;
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
    public static string[][] SingleLabels(bool left)=>left ? [] : new StenoKey[][] { [StenoKey.N1,StenoKey.N6], [StenoKey.S1,StenoKey.TL,StenoKey.PL,StenoKey.HL,StenoKey.ST1,StenoKey.FR,StenoKey.PR,StenoKey.LR,StenoKey.TR,StenoKey.DR], [StenoKey.S2,StenoKey.KL,StenoKey.WL,StenoKey.RL,StenoKey.RR,StenoKey.BR,StenoKey.GR,StenoKey.SR,StenoKey.ZR], [StenoKey.A,StenoKey.O,StenoKey.E,StenoKey.U] }.Select(row=>row.Select(GeminiPRPacket.Label).ToArray()).ToArray();
    private static NormalizedRect[][] Asterisk(bool left)
    {
        const double scale=234.0/626;
        double upper=25.1304,row=25/scale;
        NormalizedRect r(double x,double y,double w,double h)=>new(x,y,w,h);
        var rows=left ? new NormalizedRect[][] {
            [r(9.13078,3.9384,177.665,upper-3.9384)],
            [r(9.06885,upper,32.78585,row),r(57.4512,upper,32.7859,row),r(104.634,upper,32.786,row),r(153.1,upper,32.786,row),r(191.316,upper,39.662,2*row)],
            new[]{9.13078,57.0502,104.97,152.89}.Select(x=>r(x,upper+row,33.4535,row)).ToArray(),
            new[]{151.534,194.933}.Select(x=>r(x,181.603,32.549,56.961)).ToArray()
        } : new NormalizedRect[][] {
            [r(392.941,3.71233,176.761,upper-3.71233)],
            new[]{r(347.734,upper,39.662,2*row)}.Concat(new[]{392.901,441.283,488.466,536.933}.Select(x=>r(x,upper,32.786,row))).Append(r(577.839,upper,40.6866,row)).ToArray(),
            new[]{392.489,440.409,488.329,536.248}.Select(x=>r(x,upper+row,33.4535,row)).Append(r(577.839,upper+row,40.6866,row)).ToArray(),
            new[]{351.35,394.749}.Select(x=>r(x,181.603,32.549,56.961)).ToArray()
        };
        double min=left ? 9.06885:347.734,max=left ? 230.978:618.5256,ox=(160-(max-min)*scale)/2,oy=(114.9-90)/2;
        return rows.Select(row=>row.Select(k=>r((ox+(k.X-min)*scale)/160,(oy+k.Y*scale)/114.9,k.Width*scale/160,k.Height*scale/114.9)).ToArray()).ToArray();
    }
    public static KeyLayout Build(TrackpadLayoutPreset preset,bool left,ColumnLayoutSettings[] columns,KeymapStore? map,double spacing)
    {
        bool voyager=preset.Name=="STENO Voyager",single=preset.Name=="STENO Single";
        var rows=new List<NormalizedRect[]>();
        if(single && !left)
        {
            const double gap=.01,width=(.95-9*gap)/10.5,margin=.005;
            double star=1.5*width+2*(.025-margin),x=margin,height=25/114.9;
            var upper=new List<NormalizedRect>();
            for(int c=0;c<10;c++) { double w=c==4 ? star:width; upper.Add(new(x,.18,w,c==4 ? 2*height:height)); x+=w+gap; }
            rows.Add([new(upper[0].X,.1,upper[3].X+width-upper[0].X,.08),new(upper[5].X,.1,upper[9].X+width-upper[5].X,.08)]);
            rows.Add(upper.ToArray()); rows.Add(upper.Where((_,c)=>c!=4).Select(k=>new NormalizedRect(k.X,.18+height,k.Width,height)).ToArray());
            double vx=(1-(4*width+3*gap))/2;
            rows.Add(Enumerable.Range(0,4).Select(c=>new NormalizedRect(vx+c*(width+gap),.79,width,.18)).ToArray());
        }
        else if(voyager)
        {
            rows.AddRange(LayoutBuilder.BuildLayout(TrackpadLayoutPreset.SixByThree,160,114.9,18,17,columns,left,spacing).Rects);
            rows.Add(left ? [new(.56,.79,.15,.18),new(.76,.79,.15,.18)] : [new(.06,.79,.15,.18),new(.26,.79,.15,.18)]);
        }
        else if(!single) rows.AddRange(Asterisk(left));
        if(!voyager && rows.Count>3)
        {
            for(int c=0;c<rows[3].Length-1;c+=2)
            { var a=rows[3][c];var b=rows[3][c+1];double seam=(a.X+a.Width+b.X)/2;rows[3][c]=a with {Width=seam-a.X};rows[3][c+1]=b with {X=seam,Width=b.X+b.Width-seam}; }
            double shift=single ? (rows[2][3].CenterX+rows[2][4].CenterX)/2-(rows[3][0].CenterX+rows[3][3].CenterX)/2:0;
            for(int c=0;c<rows[3].Length;c++) { var r=rows[3][c];double top=single ? Asterisk(false)[3][0].Y:r.Y;rows[3][c]=r with {X=r.X+shift,Y=top,Height=1-.8/114.9-top}; }
        }
        var display=rows.Select(row=>row.Select(r=>r with { X=r.X-1.5/160,Y=r.Y-1.5/114.9,Width=r.Width+3.0/160,Height=r.Height+3.0/114.9 }).ToArray()).ToArray();
        for(int r=0;r<rows.Count;r++) for(int c=0;c<rows[r].Length;c++)
            if(map!=null) { rows[r][c]=LayoutBuilder.ApplyKeyGeometryOverride(rows[r][c],map.ResolveKeyGeometry(GridKeyPosition.StorageKey(left ? TrackpadSide.Left : TrackpadSide.Right,r,c))); display[r][c]=rows[r][c] with {X=rows[r][c].X-1.5/160,Y=rows[r][c].Y-1.5/114.9,Width=rows[r][c].Width+3.0/160,Height=rows[r][c].Height+3.0/114.9}; }
        return new(rows.ToArray(),single ? SingleLabels(left):Labels(voyager,left),isSteno:true) {DisplayRects=display};
    }
}
