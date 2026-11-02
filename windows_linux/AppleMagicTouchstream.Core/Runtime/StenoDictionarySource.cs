namespace AppleMagicTouchstream;
public sealed record StenoDictionarySource
{
    public string Path {get;set;}="";
    public bool Bundled {get;set;}
    public bool Enabled {get;set;}=true;
    public StenoDictionarySource Copy()=>this with {};
}
