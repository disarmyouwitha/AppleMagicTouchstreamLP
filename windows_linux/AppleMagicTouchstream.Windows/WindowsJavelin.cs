using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
namespace AppleMagicTouchstream;

internal readonly record struct JavelinEdit(int Backspaces,string Text);
// Serial host wrapper. This translator never reads a device or posts input.
internal sealed class WindowsJavelin:IDisposable
{
    private IntPtr _engine;
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern IntPtr AMTJavelinCreate();
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern void AMTJavelinDestroy(IntPtr engine);
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern int AMTJavelinAdd(IntPtr engine,[MarshalAs(UnmanagedType.LPUTF8Str)] string outline,[MarshalAs(UnmanagedType.LPUTF8Str)] string text);
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern void AMTJavelinReset(IntPtr engine);
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern int AMTJavelinProcess(IntPtr engine,uint stroke);
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern nuint AMTJavelinDeleteCount(IntPtr engine);
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern nuint AMTJavelinTextCount(IntPtr engine);
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern uint AMTJavelinTextAt(IntPtr engine,nuint index);
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern int AMTJavelinCanonicalOutline([MarshalAs(UnmanagedType.LPUTF8Str)]string input,byte[] output,nuint capacity);
    [DllImport("AMTJavelin",CallingConvention=CallingConvention.Cdecl)] private static extern int AMTJavelinFormatStroke(uint stroke,byte[] output,nuint capacity);
    internal int Entries {get;private set;}
    internal WindowsJavelin(IEnumerable<Dictionary<string,string>> dictionaries,bool plover=false)
    {
        _engine=AMTJavelinCreate();if(_engine==IntPtr.Zero)throw new InvalidOperationException("Could not create the Javelin translator.");
        try
        {
            foreach(var dictionary in dictionaries)foreach(var pair in dictionary)
            {if(string.IsNullOrEmpty(pair.Key) || pair.Key.Length>2048 || pair.Key.Contains('\0'))throw new ArgumentException("Dictionary outline exceeds the supported limit.");string text=Supported(pair.Value) ? pair.Value:"";if(AMTJavelinAdd(_engine,pair.Key,text)!=0)Entries++;}
            if(plover)
            {
                const string digits="1234506789";
                for(int subset=1;subset<(1<<10);subset++)
                {string number=new(Enumerable.Range(0,10).Where(i=>(subset&(1<<i))!=0).Select(i=>digits[i]).ToArray());AMTJavelinAdd(_engine,number,"{&"+number+"}");}
            }
        }
        catch {Dispose();throw;}
    }
    internal static bool Supported(string text)=>text!=null && Encoding.UTF8.GetByteCount(text)<=65536 && !text.StartsWith('=') && !text.Contains('\0') && !text.Contains("{#") && !text.Contains("{PLOVER:") && !text.Contains("{MODE:") && !Regex.IsMatch(text,@"\{:[^}]") && !new[]{"{*}","{*+}","{*?}","{*("}.Any(text.Contains);
    internal void Reset(){if(_engine!=IntPtr.Zero)AMTJavelinReset(_engine);}
    internal JavelinEdit Translate(ulong mask)
    {
        if(_engine==IntPtr.Zero || AMTJavelinProcess(_engine,Stroke(mask))==0)throw new InvalidOperationException("Javelin cancelled an invalid edit.");
        nuint backspaces=AMTJavelinDeleteCount(_engine),count=AMTJavelinTextCount(_engine);
        if(backspaces>4096 || count>65536){Reset();throw new InvalidOperationException("Javelin edit exceeded the output limit.");}
        var text=new StringBuilder();for(nuint i=0;i<count;i++){uint scalar=AMTJavelinTextAt(_engine,i);if(!Rune.IsValid((int)scalar)){Reset();throw new InvalidOperationException("Invalid translated Unicode.");}text.Append(new Rune((int)scalar).ToString());}
        return new((int)backspaces,text.ToString());
    }
    internal static uint Stroke(ulong mask)
    {
        StenoKey?[] keys=[null,StenoKey.S2,StenoKey.TL,StenoKey.KL,StenoKey.PL,StenoKey.WL,StenoKey.HL,StenoKey.RL,StenoKey.A,StenoKey.O,StenoKey.ST1,StenoKey.E,StenoKey.U,StenoKey.FR,StenoKey.RR,StenoKey.PR,StenoKey.BR,StenoKey.LR,StenoKey.GR,StenoKey.TR,StenoKey.SR,StenoKey.DR,StenoKey.ZR];
        uint result=0;for(int i=0;i<keys.Length;i++)if(keys[i] is {} key && (mask&(1UL<<(int)key))!=0)result|=1u<<i;
        if((mask&(1UL<<(int)StenoKey.S1))!=0)result|=1u<<1;
        if((mask&((1UL<<(int)StenoKey.ST2)|(1UL<<(int)StenoKey.ST3)|(1UL<<(int)StenoKey.ST4)))!=0)result|=1u<<10;
        foreach(var key in new[]{StenoKey.N1,StenoKey.N2,StenoKey.N3,StenoKey.N4,StenoKey.N5,StenoKey.N6,StenoKey.N7,StenoKey.N8,StenoKey.N9,StenoKey.NA,StenoKey.NB,StenoKey.NC})if((mask&(1UL<<(int)key))!=0)result|=1;
        return result;
    }
    internal static string Canonical(string outline)
    {var buffer=new byte[4096];if(outline.Length>2048 || outline.Contains('\0') || AMTJavelinCanonicalOutline(outline,buffer,(nuint)buffer.Length)==0)throw new ArgumentException("Enter a valid steno outline, with / between strokes.");return Encoding.UTF8.GetString(buffer,0,Array.IndexOf(buffer,(byte)0));}
    internal static string Format(ulong mask)
    {var buffer=new byte[128];if(AMTJavelinFormatStroke(Stroke(mask),buffer,(nuint)buffer.Length)==0)return "";return Encoding.UTF8.GetString(buffer,0,Array.IndexOf(buffer,(byte)0));}
    public void Dispose(){if(_engine!=IntPtr.Zero){AMTJavelinDestroy(_engine);_engine=IntPtr.Zero;}GC.SuppressFinalize(this);}
    ~WindowsJavelin(){Dispose();}
}

internal static class WindowsJavelinDictionaries
{
    internal static string Root=>Path.Combine(AppContext.BaseDirectory,"Assets","Javelin");
    internal static string Profile(string mode)=>mode=="javelinPlover" ? "plover":"lapwing";
    internal static List<StenoDictionarySource> Sources(UserSettings settings,string mode)
    {
        string profile=Profile(mode);settings.JavelinDictionaries ??=new();
        if(settings.JavelinDictionaries.TryGetValue(profile,out var existing))return existing;
        string[] files=profile=="plover" ? ["plover-commands.json","plover-main.json"]:["lapwing-commands.json","lapwing-numbers.json","lapwing-uk-additions.json","lapwing-proper-nouns.json","lapwing-base.json"];
        var values=files.Select(file=>new StenoDictionarySource {Path=file,Bundled=true}).ToList();settings.JavelinDictionaries[profile]=values;return values;
    }
    internal static string Resolve(StenoDictionarySource source)
    {
        if(!source.Bundled)return Path.GetFullPath(source.Path);
        if(Path.GetFileName(source.Path)!=source.Path || !source.Path.EndsWith(".json",StringComparison.OrdinalIgnoreCase))throw new ArgumentException("Invalid bundled dictionary name.");
        return Path.Combine(Root,source.Path);
    }
    internal static Dictionary<string,string> Read(StenoDictionarySource source)
    {
        string path=Resolve(source);if(new FileInfo(path).Length>32*1024*1024)throw new ArgumentException("Dictionary exceeds 32 MB.");
        return JsonSerializer.Deserialize<Dictionary<string,string>>(File.ReadAllText(path)) ?? throw new ArgumentException("Expected a JSON outline-to-text dictionary.");
    }
    internal static WindowsJavelin Load(IEnumerable<StenoDictionarySource> sources,bool plover)
    {var enabled=sources.Where(s=>s.Enabled).Take(33).ToArray();if(enabled.Length>32)throw new ArgumentException("Enable at most 32 dictionaries.");return new(enabled.Select(Read),plover);}
    internal static void Save(StenoDictionarySource source,Dictionary<string,string> entries)
    {
        if(source.Bundled)throw new InvalidOperationException("Save a copy before editing a bundled dictionary.");
        string path=Resolve(source),temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        try{File.WriteAllText(temporary,JsonSerializer.Serialize(entries,new JsonSerializerOptions{WriteIndented=true}),new UTF8Encoding(false));File.Move(temporary,path,true);}finally{if(File.Exists(temporary))File.Delete(temporary);}
    }
}
