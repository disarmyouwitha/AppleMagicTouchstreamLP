using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
namespace AppleMagicTouchstream;

internal static class StenoTransportParityTests
{
    private static void Check(bool ok,string reason){if(!ok)throw new InvalidOperationException(reason);}
    internal static void Run()
    {
        string folder=Path.Combine(Path.GetTempPath(),"amt-steno-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        try
        {
            string file=Path.Combine(folder,"test.json");File.WriteAllText(file,"{\"KAT\":\"cat\"}");
            var settings=new UserSettings {StenoConnectionMode="javelin",JavelinDictionaries=new(){{"lapwing",new(){new(){Path=file}}}}};
            var state=new StenoOutputState();state.Configure(true);bool eligible=true;
            using var transport=new WindowsStenoConnection(0);transport.Configure(true,state,()=>eligible,settings);
            Check(SpinWait.SpinUntil(()=>transport.Status.Connected || transport.Status.Error?.Contains("unavailable")==true,10000) && transport.Status.Connected,"built-in backend failed to load");
            ulong mask=(1UL<<(int)StenoKey.KL)|(1UL<<(int)StenoKey.A)|(1UL<<(int)StenoKey.TR);
            DispatchEvent Stroke(long generation)=>new(Stopwatch.GetTimestamp(),DispatchEventKind.StenoStroke,0,DispatchMouseButton.None,0,DispatchEventFlags.None,TrackpadSide.Left,"GeminiPR",StenoMask:mask,StenoGeneration:generation);
            Check(!transport.Send(Stroke(state.Generation-1)) && transport.TakeEdit()==null,"stale stroke produced edit");
            Check(transport.Send(Stroke(state.Generation)) && transport.TakeEdit()==new JavelinEdit(0,"cat"),"live built-in stroke failed");
            ulong recorded=0;transport.SetRecorder(value=>recorded=value);Check(transport.Send(Stroke(state.Generation)) && recorded==mask && transport.TakeEdit()==null,"Record Stroke leaked translated output");transport.SetRecorder(null);
            Check(transport.Send(Stroke(state.Generation)) && transport.TakeEdit()==new JavelinEdit(0,"cat"),"record exit retained translation history");
            eligible=false;Check(!transport.Send(Stroke(state.Generation)),"takeover gate bypassed");eligible=true;
            transport.Configure(true,state,()=>eligible); // no settings = retained explicit plugin API
            using var client=new Socket(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp) {ReceiveTimeout=3000,SendTimeout=3000};client.Connect(IPAddress.Loopback,transport.BoundPort);
            client.Send(Encoding.ASCII.GetBytes("AMT-GEMINIPR/1\n"));var ready=new byte[6];for(int offset=0;offset<ready.Length;){int n=client.Receive(ready.AsSpan(offset),SocketFlags.None);if(n==0)throw new Exception("plugin handshake closed");offset+=n;}Check(Encoding.ASCII.GetString(ready)=="READY\n","plugin handshake failed");
            Check(SpinWait.SpinUntil(()=>transport.Status.Connected,3000),"plugin reader not ready");Check(transport.Send(Stroke(state.Generation)),"plugin stroke rejected");
            var packet=new byte[6];int read=0;while(read<6)read+=client.Receive(packet.AsSpan(read),SocketFlags.None);var expected=new byte[6];GeminiPRPacket.Write(mask,expected);Check(packet.SequenceEqual(expected),"plugin wire changed");
            transport.Configure(false,state,()=>eligible);Check(!transport.Status.Enabled,"disabled backend remained live");
            Console.WriteLine("STENO transports passed: built-in edits, record interception, generation/takeover gates, private ephemeral plugin handshake and wire packet. No native input/live Plover port.");
        }
        finally{Directory.Delete(folder,true);}
    }
}
