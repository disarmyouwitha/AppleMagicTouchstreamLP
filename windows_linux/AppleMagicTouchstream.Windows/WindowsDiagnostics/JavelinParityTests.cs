using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
namespace AppleMagicTouchstream;

internal static class JavelinParityTests
{
    private static void Check(bool value,string reason){if(!value)throw new InvalidOperationException(reason);}
    private static ulong Mask(params StenoKey[] keys)=>keys.Aggregate(0UL,(m,k)=>m|(1UL<<(int)k));
    internal static void Run()
    {
        Check(WindowsJavelin.Stroke(Mask(StenoKey.S1))==WindowsJavelin.Stroke(Mask(StenoKey.S2)),"S aliases differ");
        Check(WindowsJavelin.Stroke(Mask(StenoKey.ST1,StenoKey.ST2,StenoKey.ST3,StenoKey.ST4))==1u<<10,"star aliases differ");
        using(var t=new WindowsJavelin([new(){{"KAT","cat"},{"-S","{^s}"},{"KAT/-S","cats"},{"TP","{.}"},{"H-L","hello"}}]))
        {
            Check(t.Translate(Mask(StenoKey.KL,StenoKey.A,StenoKey.TR))==new JavelinEdit(0,"cat"),"native cat differs from Mac");
            Check(t.Translate(Mask(StenoKey.SR))==new JavelinEdit(0,"s"),"native multistroke differs from Mac");
            Check(t.Translate(Mask(StenoKey.ST1))==new JavelinEdit(1,""),"native undo differs from Mac");
            Check(t.Translate(Mask(StenoKey.TL,StenoKey.PL))==new JavelinEdit(0,"."),"native punctuation differs");
            Check(t.Translate(Mask(StenoKey.HL,StenoKey.LR))==new JavelinEdit(0," Hello"),"native spacing/capitalization differs");
            t.Reset();Check(t.Translate(Mask(StenoKey.ST1))==new JavelinEdit(0,""),"reset posted an undo");
        }
        using(var t=new WindowsJavelin([new(){{"KAT","cat"},{"-S","{^s}"},{"KAT/-S","felines"}}]))
        {t.Translate(Mask(StenoKey.KL,StenoKey.A,StenoKey.TR));Check(t.Translate(Mask(StenoKey.SR))==new JavelinEdit(3,"felines"),"longer outline did not replace word");Check(t.Translate(Mask(StenoKey.ST1))==new JavelinEdit(7,"cat"),"multistroke undo failed");}
        using(var t=new WindowsJavelin([new(){{"KAT","kitten"},{"H-L","{#super(a)}"}},new(){{"KAT","cat"},{"H-L","unsafe lower fallback"}}]))
        {Check(t.Translate(Mask(StenoKey.KL,StenoKey.A,StenoKey.TR)).Text=="kitten","dictionary priority inverted");t.Reset();Check(t.Translate(Mask(StenoKey.HL,StenoKey.LR)).Text=="","unsupported command fell through");}
        Check(WindowsJavelin.Canonical("KAT/-S")=="KAT/-S","canonical outline differs");
        Check(WindowsJavelin.Format(Mask(StenoKey.KL,StenoKey.A,StenoKey.TR))=="KAT","Record Stroke outline differs");
        foreach(string manifest in new[]{"manifest.json","plover-manifest.json"})
        {
            using var json=JsonDocument.Parse(File.ReadAllText(Path.Combine(WindowsJavelinDictionaries.Root,manifest)));
            foreach(var hash in json.RootElement.GetProperty("sha256").EnumerateObject())
                Check(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(WindowsJavelinDictionaries.Root,hash.Name)))).Equals(hash.Value.GetString(),StringComparison.OrdinalIgnoreCase),"bundled dictionary checksum differs: "+hash.Name);
        }
        var settings=new UserSettings();
        using(var lapwing=WindowsJavelinDictionaries.Load(WindowsJavelinDictionaries.Sources(settings,"javelin"),false))
        {Check(lapwing.Entries>140000,"Lapwing is incomplete");Check(lapwing.Translate(Mask(StenoKey.KL,StenoKey.A,StenoKey.TR)).Text=="cat","bundled Lapwing cannot translate KAT");}
        using(var plover=WindowsJavelinDictionaries.Load(WindowsJavelinDictionaries.Sources(settings,"javelinPlover"),true))
        {Check(plover.Entries>100000,"Plover dictionary is incomplete");Check(plover.Translate(Mask(StenoKey.KL,StenoKey.A,StenoKey.TR)).Text=="cat","bundled Plover cannot translate KAT");}
        Console.WriteLine("Native Javelin parity passed: formatting, multistroke replacement, undo, aliases, priority, unsupported commands, Lapwing/Plover and bundled checksums. No native input.");
    }
}
