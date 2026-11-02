using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
namespace AppleMagicTouchstream;

// DPAPI CurrentUser; no UI and no plaintext fallback. Other processes running as
// this user are not excluded by DPAPI. Exports contain references, not vault data.
internal sealed class WindowsTextShortcutStore
{
    internal static readonly WindowsTextShortcutStore Shared=new();
    private static string PathFor(Guid id)=>ApplicationDataPaths.UserFile(System.IO.Path.Combine("text-vault",id.ToString("D")+".bin"));
    [StructLayout(LayoutKind.Sequential)] private struct Blob { public int Length; public IntPtr Data; }
    [DllImport("crypt32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool CryptProtectData(ref Blob input,string description,IntPtr entropy,IntPtr reserved,IntPtr prompt,uint flags,out Blob output);
    [DllImport("crypt32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool CryptUnprotectData(ref Blob input,IntPtr description,IntPtr entropy,IntPtr reserved,IntPtr prompt,uint flags,out Blob output);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
    private static byte[] Transform(byte[] bytes,bool protect)
    {
        if(!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Saved text requires Windows DPAPI.");
        var input=new Blob { Length=bytes.Length,Data=Marshal.AllocHGlobal(bytes.Length) }; Blob output=default;
        try
        {
            Marshal.Copy(bytes,0,input.Data,bytes.Length);
            bool ok=protect ? CryptProtectData(ref input,"AppleMagicTouchstream saved text",IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,1,out output)
                : CryptUnprotectData(ref input,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,1,out output);
            if(!ok) throw new InvalidOperationException("Saved text is unavailable for this Windows account.");
            if(output.Length<1 || output.Length>1024*1024) throw new InvalidOperationException("Invalid saved text record.");
            var result=new byte[output.Length]; Marshal.Copy(output.Data,result,0,result.Length); return result;
        }
        finally
        {
            for(int i=0;i<input.Length;i++) Marshal.WriteByte(input.Data,i,0);
            Marshal.FreeHGlobal(input.Data);
            if(output.Data!=IntPtr.Zero) { for(int i=0;i<output.Length;i++) Marshal.WriteByte(output.Data,i,0); LocalFree(output.Data); }
        }
    }
    public Guid Save(string text,Guid? existing=null)
    {
        if(!TextShortcutReference.Valid(text)) throw new ArgumentException("Enter text up to 64 KB.");
        byte[] bytes=Encoding.UTF8.GetBytes(text);
        try
        {
            byte[] encrypted=Transform(bytes,true); Guid id=existing ?? Guid.NewGuid(); string path=PathFor(id);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
            string temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";
            try { File.WriteAllBytes(temporary,encrypted); File.Move(temporary,path,true); } finally { if(File.Exists(temporary)) File.Delete(temporary); }
            return id;
        }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }
    public string Load(Guid id)
    {
        string path=PathFor(id);
        if(!File.Exists(path) || new FileInfo(path).Length>1024*1024) throw new InvalidOperationException("Saved text is missing. Re-enter it on this Windows account.");
        byte[] bytes=Transform(File.ReadAllBytes(path),false);
        try { string text=new UTF8Encoding(false,true).GetString(bytes); if(!TextShortcutReference.Valid(text)) throw new InvalidOperationException("Invalid saved text record."); return text; }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }
}
