using System.Text.Json;

namespace AppleMagicTouchstream;

// Same authoring schema as Mac. UUIDs and immutable binding addresses are distinct;
// moving/resizing never changes actions. Compilation is a configuration operation.
public sealed class LayoutDocument
{
    public sealed class Key
    {
        public Guid Id { get; set; }=Guid.NewGuid();
        public bool Right { get; set; }
        public int Row { get; set; }
        public int Column { get; set; }
        public string Label { get; set; }="None";
        public int[]? Layers { get; set; }
        public NormalizedRect Rect { get; set; }
        public Guid? Group { get; set; }
        public Guid? MirrorID { get; set; }
        public int? CopySourceRow { get; set; }
        public int? CopySourceColumn { get; set; }
        public double[] Edges { get; set; }=[0,0,0,0];
        [System.Text.Json.Serialization.JsonIgnore] public NormalizedRect DisplayRect=>Rect with { X=Rect.X-Edges[0],Y=Rect.Y-Edges[1],Width=Rect.Width+Edges[0]+Edges[2],Height=Rect.Height+Edges[1]+Edges[3] };
        public bool Visible(int layer)=>Layers==null || Array.IndexOf(Layers,layer)>=0;
        public Key Copy()=>new() { Id=Id,Right=Right,Row=Row,Column=Column,Label=Label,Layers=Layers?.ToArray(),Rect=Rect,Group=Group,MirrorID=MirrorID,CopySourceRow=CopySourceRow,CopySourceColumn=CopySourceColumn,Edges=Edges.ToArray() };
    }
    public sealed record Group(Guid Id,string Name);
    public List<Key> Keys { get; set; }=new();
    public List<Group> Groups { get; set; }=new();
    public int NextRow { get; set; }
    public LayoutDocument Copy()=>new() { Keys=Keys.Select(k=>k.Copy()).ToList(),Groups=Groups.ToList(),NextRow=NextRow };
    public static readonly JsonSerializerOptions JsonOptions=new() { PropertyNameCaseInsensitive=true,PropertyNamingPolicy=JsonNamingPolicy.CamelCase };
    public bool IsValid()
    {
        if(Keys==null || Groups==null || Keys.Count>2048 || NextRow<0 || NextRow>=4096 || Keys.Any(k=>k==null) || Groups.Any(g=>g==null) || Keys.Select(k=>k.Id).Distinct().Count()!=Keys.Count || Groups.Select(g=>g.Id).Distinct().Count()!=Groups.Count) return false;
        var addresses=new HashSet<(bool,int,int)>(); var ids=Keys.ToDictionary(k=>k.Id); var groups=Groups.Select(g=>g.Id).ToHashSet();
        foreach(var key in Keys)
        {
            var r=key.Rect;
            if(key.Id==Guid.Empty || key.Row<0 || key.Row>=NextRow || key.Column<0 || key.Column>=128 || !addresses.Add((key.Right,key.Row,key.Column)) || key.Label==null
                || !new[]{r.X,r.Y,r.Width,r.Height,r.RotationDegrees}.All(double.IsFinite) || r.Width is <=0 or >2 || r.Height is <=0 or >2 || Math.Abs(r.X)>2 || Math.Abs(r.Y)>2
                || key.Layers is {} layers && (layers.Length==0 || layers.Distinct().Count()!=layers.Length || layers.Any(l=>l<0 || l>7))
                || key.Edges is not {Length:4} || key.Edges.Any(e=>!double.IsFinite(e) || Math.Abs(e)>=1) || key.DisplayRect.Width<=0 || key.DisplayRect.Height<=0
                || key.Group is {} group && !groups.Contains(group) || key.MirrorID is {} mirror && (!ids.TryGetValue(mirror,out var other) || other.MirrorID!=key.Id || other.Right==key.Right)) return false;
        }
        return true;
    }
    public KeyLayout Compile(bool right,bool steno)
    {
        if(!IsValid()) throw new ArgumentException("Invalid layout document.");
        var keys=Keys.Where(k=>k.Right==right).ToArray(); int rows=keys.Length==0 ? 0 : keys.Max(k=>k.Row)+1;
        var rects=new NormalizedRect[rows][]; var display=new NormalizedRect[rows][]; var labels=new string[rows][];
        var layers=new Dictionary<(int,int),int[]>();
        for(int row=0;row<rows;row++)
        {
            int columns=keys.Where(k=>k.Row==row).Select(k=>k.Column+1).DefaultIfEmpty(0).Max();
            rects[row]=new NormalizedRect[columns]; display[row]=new NormalizedRect[columns]; labels[row]=Enumerable.Repeat("None",columns).ToArray();
        }
        foreach(var key in keys)
        { rects[key.Row][key.Column]=key.Rect; display[key.Row][key.Column]=key.DisplayRect; labels[key.Row][key.Column]=key.Label; if(key.Layers!=null) layers[(key.Row,key.Column)]=key.Layers.ToArray(); }
        return new(rects,labels,steno,physicalRotation:true) { DisplayRects=display,KeyLayers=layers };
    }
    public static LayoutDocument Seed(KeyLayout left,KeyLayout right)
    {
        var result=new LayoutDocument();
        foreach(var side in new[]{false,true})
        {
            var layout=side ? right : left;
            for(int r=0;r<layout.Rects.Length;r++) for(int c=0;c<layout.Rects[r].Length;c++)
            {
                var rect=layout.Rects[r][c]; if(rect.Width<=0 || rect.Height<=0) continue;
                var display=layout.DisplayRects?[r][c] ?? rect;
                result.Keys.Add(new() { Right=side,Row=r,Column=c,Label=layout.Labels[r][c],Rect=rect,
                    Edges=[rect.X-display.X,rect.Y-display.Y,display.X+display.Width-rect.X-rect.Width,display.Y+display.Height-rect.Y-rect.Height],Layers=layout.KeyLayers.GetValueOrDefault((r,c))?.ToArray() });
                result.NextRow=Math.Max(result.NextRow,r+1);
            }
        }
        result.InferMirrors(); return result;
    }
    public void InferMirrors()
    {
        var candidates=new List<(Key Left,Key Right,double Cost)>();
        foreach(var l in Keys.Where(k=>!k.Right && k.MirrorID==null)) foreach(var r in Keys.Where(k=>k.Right && k.MirrorID==null))
        {
            double dx=Math.Abs(1-l.Rect.CenterX-r.Rect.CenterX),dy=Math.Abs(l.Rect.CenterY-r.Rect.CenterY);
            double wr=l.Rect.Width/r.Rect.Width,hr=l.Rect.Height/r.Rect.Height;
            if(dx<.25 && dy<.2 && wr is >=.33 and <=3 && hr is >=.33 and <=3) candidates.Add((l,r,dx*dx+dy*dy+.1*Math.Pow(Math.Abs(l.Rect.Width-r.Rect.Width)+Math.Abs(l.Rect.Height-r.Rect.Height),2)));
        }
        foreach(var (l,r,_) in candidates.OrderBy(c=>c.Cost)) if(l.MirrorID==null && r.MirrorID==null) { l.MirrorID=r.Id; r.MirrorID=l.Id; }
    }
    public HashSet<Guid> Paired(ISet<Guid> selected)=>selected.Concat(Keys.Where(k=>selected.Contains(k.Id) && k.MirrorID!=null).Select(k=>k.MirrorID!.Value)).ToHashSet();
    public void MirrorChanges(LayoutDocument before,ISet<Guid> sources)
    {
        var old=before.Keys.ToDictionary(k=>k.Id); var indices=Keys.ToDictionary(k=>k.Id);
        foreach(var key in Keys.Where(k=>sources.Contains(k.Id)).ToArray())
        {
            if(!old.TryGetValue(key.Id,out var prior) || prior.MirrorID is not {} id || sources.Contains(id) || !old.TryGetValue(id,out var partner) || !indices.TryGetValue(id,out var target)) continue;
            var a=prior.Rect; var b=key.Rect; var p=partner.Rect;
            double w=Math.Clamp(p.Width+b.Width-a.Width,.005,1),h=Math.Clamp(p.Height+b.Height-a.Height,.005,1);
            target.Rect=p with { X=p.X-(b.X-a.X)-(w-p.Width),Y=p.Y+b.Y-a.Y,Width=w,Height=h,RotationDegrees=p.RotationDegrees-b.RotationDegrees+a.RotationDegrees };
            int[] reflection=[2,1,0,3]; for(int i=0;i<4;i++) target.Edges[i]=partner.Edges[i]+key.Edges[reflection[i]]-prior.Edges[reflection[i]];
        }
    }
    public Guid? Hit(bool right,int layer,double x,double y)=>Keys.Where(k=>k.Right==right && k.Visible(layer) && KeyHitGeometry.FromPhysicalRect(k.DisplayRect).Contains(x,y)).OrderByDescending(k=>KeyHitGeometry.FromPhysicalRect(k.DisplayRect).DistanceToEdge(x,y)).ThenBy(k=>k.DisplayRect.Width*k.DisplayRect.Height).Select(k=>(Guid?)k.Id).FirstOrDefault();
    public HashSet<Guid> Marquee(bool right,int layer,NormalizedRect box)=>Keys.Where(k=>k.Right==right && k.Visible(layer)).Where(k=> { var g=KeyHitGeometry.FromPhysicalRect(k.DisplayRect); return g.MaxX>=box.X && g.MinX<=box.X+box.Width && g.MaxY>=box.Y && g.MinY<=box.Y+box.Height; }).Select(k=>k.Id).ToHashSet();
    public Guid Add(bool right,int layer,NormalizedRect? rect=null,string label="None")
    {
        var key=new Key { Right=right,Row=NextRow++,Layers=[layer],Rect=rect ?? new(.4,.4,.08,.18),Label=label }; Keys.Add(key); return key.Id;
    }
    public Guid AddMirrored(bool right,int layer,NormalizedRect? rect=null,string label="None")
    { var id=Add(right,layer,rect,label); var a=Keys[^1]; var other=Add(!right,layer,a.Rect.MirrorHorizontally(),label); a.MirrorID=other; Keys[^1].MirrorID=id; return id; }
    public void Delete(ISet<Guid> ids)
    { Keys.RemoveAll(k=>ids.Contains(k.Id)); foreach(var k in Keys) if(k.MirrorID is {} id && ids.Contains(id)) k.MirrorID=null; Groups.RemoveAll(g=>!Keys.Any(k=>k.Group==g.Id)); }
    public HashSet<Guid> Duplicate(ISet<Guid> ids)
    {
        var copies=Keys.Where(k=>ids.Contains(k.Id)).Select(k=>k.Copy()).ToArray(); var map=copies.ToDictionary(k=>k.Id,k=>Guid.NewGuid());
        foreach(var k in copies) { var old=k.Id; k.Id=map[old]; k.CopySourceRow??=k.Row; k.CopySourceColumn??=k.Column; k.Row=NextRow++; k.Column=0; k.MirrorID=k.MirrorID is {} id && map.TryGetValue(id,out var mirror) ? mirror : null; k.Rect=k.Rect with { X=k.Rect.X+.02,Y=k.Rect.Y+.02 }; Keys.Add(k); }
        return copies.Select(k=>k.Id).ToHashSet();
    }
    public void Translate(ISet<Guid> ids,double dx,double dy)
    { var selected=Keys.Where(k=>ids.Contains(k.Id)).ToArray(); if(selected.Length==0) return; dx=Math.Clamp(dx,-selected.Min(k=>k.Rect.X),Math.Max(-selected.Min(k=>k.Rect.X),1-selected.Max(k=>k.Rect.X+k.Rect.Width))); dy=Math.Clamp(dy,-selected.Min(k=>k.Rect.Y),Math.Max(-selected.Min(k=>k.Rect.Y),1-selected.Max(k=>k.Rect.Y+k.Rect.Height))); foreach(var k in selected) k.Rect=k.Rect with { X=k.Rect.X+dx,Y=k.Rect.Y+dy }; }
    // All transforms use physical mm: normalized X and Y do not have equal scale.
    public (NormalizedRect Rect,bool Independent)? Frame(ISet<Guid> ids,bool right)
    {
        var selected=Keys.Where(k=>ids.Contains(k.Id) && k.Right==right).ToArray(); if(selected.Length==0) return null;
        double angle=selected[0].Rect.RotationDegrees; bool shared=selected.All(k=>Math.Abs(Math.IEEERemainder(k.Rect.RotationDegrees-angle,180))<.00001); if(!shared) angle=0;
        double a=angle*Math.PI/180,c=Math.Cos(a),s=Math.Sin(a); var points=new List<(double X,double Y)>();
        foreach(var k in selected)
        {
            var r=k.Rect; double ka=r.RotationDegrees*Math.PI/180,cc=Math.Cos(ka),ss=Math.Sin(ka);
            foreach(var x in new[]{-.5,.5}) foreach(var y in new[]{-.5,.5})
            { double px=r.CenterX*160+x*r.Width*160*cc-y*r.Height*114.9*ss,py=r.CenterY*114.9+x*r.Width*160*ss+y*r.Height*114.9*cc; points.Add((px*c+py*s,-px*s+py*c)); }
        }
        double lowX=points.Min(p=>p.X),highX=points.Max(p=>p.X),lowY=points.Min(p=>p.Y),highY=points.Max(p=>p.Y),cx=(lowX+highX)/2,cy=(lowY+highY)/2,w=(highX-lowX)/160,h=(highY-lowY)/114.9;
        return(new((cx*c-cy*s)/160-w/2,(cx*s+cy*c)/114.9-h/2,w,h) { RotationDegrees=angle },shared);
    }
    public void Resize(ISet<Guid> ids,double sx,double sy)
    {
        if(!double.IsFinite(sx) || !double.IsFinite(sy) || sx<=0 || sy<=0) return;
        var selected=Keys.Where(k=>ids.Contains(k.Id)).ToArray(); if(selected.Length==0) return;
        bool uniform=Math.Abs(sx-sy)<1e-7;
        if(!uniform && new[]{false,true}.Any(side=>Frame(ids,side) is {Independent:false})) return;
        double minX=selected.Max(k=>.005/k.Rect.Width),minY=selected.Max(k=>.005/k.Rect.Height),maxX=selected.Min(k=>1/k.Rect.Width),maxY=selected.Min(k=>1/k.Rect.Height);
        if(uniform) { sx=Math.Clamp(sx,Math.Max(minX,minY),Math.Max(Math.Max(minX,minY),Math.Min(maxX,maxY))); sy=sx; }
        else { sx=Math.Clamp(sx,minX,Math.Max(minX,maxX)); sy=Math.Clamp(sy,minY,Math.Max(minY,maxY)); }
        foreach(var side in new[]{false,true})
        {
            if(Frame(ids,side) is not {} frame) continue; var r=frame.Rect; double a=r.RotationDegrees*Math.PI/180,c=Math.Cos(a),s=Math.Sin(a);
            double ax=r.CenterX*160-r.Width*160/2*c+r.Height*114.9/2*s,ay=r.CenterY*114.9-r.Width*160/2*s-r.Height*114.9/2*c;
            foreach(var key in selected.Where(k=>k.Right==side))
            { var k=key.Rect; double dx=k.CenterX*160-ax,dy=k.CenterY*114.9-ay,x=(dx*c+dy*s)*sx,y=(-dx*s+dy*c)*sy,w=k.Width*sx,h=k.Height*sy; key.Rect=k with { X=(ax+x*c-y*s)/160-w/2,Y=(ay+x*s+y*c)/114.9-h/2,Width=w,Height=h }; }
        }
    }
    public void Rotate(ISet<Guid> ids,double degrees)
    {
        foreach(var side in new[]{false,true})
        { var keys=Keys.Where(k=>ids.Contains(k.Id) && k.Right==side).ToArray(); if(keys.Length==0) continue; double cx=keys.Average(k=>k.Rect.CenterX*160),cy=keys.Average(k=>k.Rect.CenterY*114.9),a=degrees*Math.PI/180; foreach(var key in keys) { var r=key.Rect; double x=r.CenterX*160-cx,y=r.CenterY*114.9-cy; key.Rect=r with { X=(cx+x*Math.Cos(a)-y*Math.Sin(a))/160-r.Width/2,Y=(cy+x*Math.Sin(a)+y*Math.Cos(a))/114.9-r.Height/2,RotationDegrees=r.RotationDegrees+degrees }; } }
    }
    private List<(Key[] Keys,double Low,double High)> Bands(ISet<Guid> ids,bool right,bool xAxis)
    {
        if(Frame(ids,right) is not {Independent:true} frame) return new();
        double a=frame.Rect.RotationDegrees*Math.PI/180,c=Math.Cos(a),s=Math.Sin(a);
        var values=Keys.Where(k=>ids.Contains(k.Id) && k.Right==right).Select(k=>(Key:k,Pos:xAxis ? k.Rect.CenterX*160*c+k.Rect.CenterY*114.9*s : -k.Rect.CenterX*160*s+k.Rect.CenterY*114.9*c,Size:xAxis ? k.Rect.Width*160 : k.Rect.Height*114.9)).OrderBy(v=>v.Pos).ToArray();
        var bands=new List<(Key[] Keys,double Low,double High)>(); double center=double.NegativeInfinity;
        foreach(var v in values) if(Math.Abs(v.Pos-center)<=.5 && bands.Count>0) { var b=bands[^1]; bands[^1]=(b.Keys.Append(v.Key).ToArray(),Math.Min(b.Low,v.Pos-v.Size/2),Math.Max(b.High,v.Pos+v.Size/2)); } else { bands.Add(([v.Key],v.Pos-v.Size/2,v.Pos+v.Size/2)); center=v.Pos; }
        return bands;
    }
    public double? Spacing(ISet<Guid> ids,bool right,bool xAxis)
    { var b=Bands(ids,right,xAxis); return b.Count<2 ? null : Enumerable.Range(1,b.Count-1).Average(i=>b[i].Low-b[i-1].High); }
    public void SetSpacing(ISet<Guid> ids,bool xAxis,double mm)
    {
        if(!double.IsFinite(mm)) return;
        foreach(var side in new[]{false,true})
        { var bands=Bands(ids,side,xAxis); if(Frame(ids,side) is not {} frame) continue; double a=frame.Rect.RotationDegrees*Math.PI/180,c=Math.Cos(a),s=Math.Sin(a),shift=0; for(int i=1;i<bands.Count;i++) { shift+=mm-(bands[i].Low-bands[i-1].High); foreach(var key in bands[i].Keys) key.Rect=key.Rect with { X=key.Rect.X+(xAxis ? shift*c : -shift*s)/160,Y=key.Rect.Y+(xAxis ? shift*s : shift*c)/114.9 }; } }
    }
    public void ScaleSpacing(ISet<Guid> ids,double factor)
    {
        if(!double.IsFinite(factor) || factor<=0) return;
        foreach(var side in new[]{false,true})
        { var xs=Bands(ids,side,true); var ys=Bands(ids,side,false); if(xs.Count==0 || ys.Count==0 || Frame(ids,side) is not {} frame) continue; double a=frame.Rect.RotationDegrees*Math.PI/180,c=Math.Cos(a),s=Math.Sin(a),ox=(xs[0].Low+xs[0].High)/2,oy=(ys[0].Low+ys[0].High)/2; foreach(var key in Keys.Where(k=>ids.Contains(k.Id) && k.Right==side)) { var r=key.Rect; double x=r.CenterX*160,y=r.CenterY*114.9,dx=xs.Count>1 ? (x*c+y*s-ox)*(factor-1):0,dy=ys.Count>1 ? (-x*s+y*c-oy)*(factor-1):0; key.Rect=r with { X=r.X+(dx*c-dy*s)/160,Y=r.Y+(dx*s+dy*c)/114.9 }; } }
    }
    public void Align(ISet<Guid> ids,bool xAxis)
    { foreach(var side in new[]{false,true}) { var keys=Keys.Where(k=>ids.Contains(k.Id) && k.Right==side).ToArray(); if(keys.Length<2) continue; double center=keys.Average(k=>xAxis ? k.Rect.CenterX : k.Rect.CenterY); foreach(var k in keys) k.Rect=xAxis ? k.Rect with { X=center-k.Rect.Width/2 } : k.Rect with { Y=center-k.Rect.Height/2 }; } }
    // Mutates a draft keymap only. Callers keep the live map unchanged until Apply.
    public void MigrateLegacyButtons(KeymapStore draft)
    {
        foreach(var pair in draft.CustomButtons) foreach(var button in pair.Value)
        {
            var bytes=System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes($"{draft.ActiveLayoutKey}/{pair.Key}/{button.Side}/{button.Id}"));
            var stable=new Guid(bytes.AsSpan(0,16));
            var key=Keys.FirstOrDefault(k=>k.Id==stable || (Guid.TryParse(button.Id,out var legacy) && k.Id==legacy));
            if(key==null) { var id=Add(button.Side==TrackpadSide.Right,pair.Key,button.Rect,button.Primary.Label);key=Keys.Single(k=>k.Id==id);key.Id=stable; }
            draft.Mappings.TryAdd(pair.Key,new());
            draft.Mappings[pair.Key][GridKeyPosition.StorageKey(button.Side,key.Row,key.Column)]=new() {Primary=new() {Label=button.Primary.Label},Hold=button.Hold==null ? null:new() {Label=button.Hold.Label},HoldForceThreshold=button.HoldForceThreshold};
        }
    }
    public void ApplyMappings(KeymapStore map)
    {
        var surviving=Keys.Select(k=>GridKeyPosition.StorageKey(k.Right ? TrackpadSide.Right : TrackpadSide.Left,k.Row,k.Column)).ToHashSet();
        foreach(var layer in map.Mappings.Values)
        {
            foreach(var key in Keys.Where(k=>k.CopySourceRow!=null && k.CopySourceColumn!=null))
            { string source=GridKeyPosition.StorageKey(key.Right ? TrackpadSide.Right : TrackpadSide.Left,key.CopySourceRow!.Value,key.CopySourceColumn!.Value),target=GridKeyPosition.StorageKey(key.Right ? TrackpadSide.Right : TrackpadSide.Left,key.Row,key.Column); if(layer.TryGetValue(source,out var mapping)) layer[target]=new() { Primary=new() {Label=mapping.Primary.Label},Hold=mapping.Hold==null ? null : new() {Label=mapping.Hold.Label},HoldForceThreshold=mapping.HoldForceThreshold }; }
            foreach(var key in layer.Keys.Where(k=>!surviving.Contains(k)).ToArray()) layer.Remove(key);
        }
        foreach(var key in Keys) { key.CopySourceRow=null;key.CopySourceColumn=null; }
    }
}

public sealed class LayoutDocumentHistory
{
    private readonly List<LayoutDocument> _past=new(),_future=new();
    public bool CanUndo=>_past.Count>0;
    public bool CanRedo=>_future.Count>0;
    public void Record(LayoutDocument before) { _past.Add(before.Copy()); if(_past.Count>100) _past.RemoveAt(0); _future.Clear(); }
    public LayoutDocument Undo(LayoutDocument current) { if(!CanUndo) return current; _future.Add(current.Copy()); var value=_past[^1]; _past.RemoveAt(_past.Count-1); return value.Copy(); }
    public LayoutDocument Redo(LayoutDocument current) { if(!CanRedo) return current; _past.Add(current.Copy()); var value=_future[^1]; _future.RemoveAt(_future.Count-1); return value.Copy(); }
}
