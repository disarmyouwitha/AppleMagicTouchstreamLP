using System.Net;
using System.Net.Sockets;
using System.Text;
using System.IO;

namespace AppleMagicTouchstream;

// Inert until a live STENO layout is selected. One loopback reader, no driver,
// installation, discovery service or native keyboard output.
internal sealed class WindowsStenoConnection : IDisposable
{
    public const int Port=31572;
    private readonly int _port;
    internal WindowsStenoConnection(int port=Port) { _port=port; }
    internal int BoundPort { get { lock(_gate) return _listener?.LocalEndpoint is IPEndPoint endpoint ? endpoint.Port : 0; } }
    private readonly object _gate=new();
    private TcpListener? _listener;
    private Socket? _reader;
    private CancellationTokenSource? _cancel;
    private StenoOutputState? _output;
    private Func<bool>? _eligible;
    private long _sent,_dropped;
    private string? _error;
    internal readonly record struct Snapshot(bool Enabled,bool Connected,long Sent,long Dropped,string? Error);
    public Snapshot Status { get { lock(_gate) return new(_listener!=null,_reader!=null,_sent,_dropped,_error); } }
    public void Configure(bool enabled,StenoOutputState output,Func<bool> eligible)
    {
        lock(_gate)
        {
            _output=output; _eligible=eligible;
            if(!enabled) { StopLocked(); _error=null; return; }
            if(_listener!=null) return;
            try
            {
                var listener=new TcpListener(IPAddress.Loopback,_port); listener.Server.ExclusiveAddressUse=true;
                _listener=listener; listener.Start(1); _cancel=new(); _error=null;
                _=Serve(listener,_cancel.Token);
            }
            catch(Exception error) when(error is SocketException or InvalidOperationException)
            { StopLocked(); _error="Could not open the Plover connection: "+error.Message; }
        }
    }
    private async Task Serve(TcpListener listener,CancellationToken cancel)
    {
        while(!cancel.IsCancellationRequested)
        {
            Socket? client=null;
            try
            {
                client=await listener.AcceptSocketAsync(cancel).ConfigureAwait(false);
                client.NoDelay=true; client.SendBufferSize=1024;
                using var deadline=CancellationTokenSource.CreateLinkedTokenSource(cancel); deadline.CancelAfter(3000);
                var hello=new byte[15]; int read=0;
                while(read<hello.Length)
                {
                    int n=await client.ReceiveAsync(hello.AsMemory(read),SocketFlags.None,deadline.Token).ConfigureAwait(false);
                    if(n==0) throw new IOException("Plover disconnected during setup."); read+=n;
                }
                if(Encoding.ASCII.GetString(hello)!="AMT-GEMINIPR/1\n") throw new IOException("Unknown Plover client.");
                byte[] ready=Encoding.ASCII.GetBytes("READY\n"); int written=0;
                while(written<ready.Length)
                    written+=await client.SendAsync(ready.AsMemory(written),SocketFlags.None,deadline.Token).ConfigureAwait(false);
                client.Blocking=false;
                lock(_gate)
                {
                    if(_listener!=listener || cancel.IsCancellationRequested) break;
                    _reader=client; _error=null;
                }
                while(!cancel.IsCancellationRequested)
                {
                    await Task.Delay(100,cancel).ConfigureAwait(false);
                    lock(_gate) if(_reader!=client) break;
                    // The client sends no data after the handshake. Readability
                    // indicates EOF or an invalid additional command.
                    if(client.Poll(0,SelectMode.SelectRead)) break;
                }
            }
            catch(OperationCanceledException) { if(cancel.IsCancellationRequested) break; }
            catch(Exception error) when(error is SocketException or IOException or ObjectDisposedException) { }
            finally
            {
                lock(_gate) if(_reader==client) _reader=null;
                client?.Dispose();
            }
        }
    }
    public bool Send(in DispatchEvent stroke)
    {
        var output=_output; if(output==null) return false;
        lock(output.Sync)
        lock(_gate)
        {
            long age=System.Diagnostics.Stopwatch.GetTimestamp()-stroke.TimestampTicks;
            if(!ReferenceEquals(output,_output) || stroke.Kind!=DispatchEventKind.StenoStroke || !output.IsCurrent(stroke.StenoGeneration)
                || stroke.StenoMask==0 || (stroke.StenoMask&~GeminiPRPacket.KeyMask)!=0 || _eligible?.Invoke()!=true
                || age<0 || age>System.Diagnostics.Stopwatch.Frequency*.25
                || _reader==null) { _dropped++; return false; }
            Span<byte> packet=stackalloc byte[6]; GeminiPRPacket.Write(stroke.StenoMask,packet);
            try
            {
                int count=_reader.Send(packet,SocketFlags.None);
                if(count==6) { _sent++; return true; }
                // A partial packet must never be followed by another stroke.
                _reader.Dispose(); _reader=null; _error="Output interrupted; waiting for Plover to reconnect.";
            }
            catch(SocketException error) when(error.SocketErrorCode==SocketError.WouldBlock) { }
            catch(Exception error) when(error is SocketException or ObjectDisposedException)
            { _reader?.Dispose(); _reader=null; }
            _dropped++; return false;
        }
    }
    private void StopLocked()
    {
        _cancel?.Cancel(); _listener?.Stop(); _listener=null;
        _reader?.Dispose(); _reader=null; _cancel?.Dispose(); _cancel=null;
    }
    public void Dispose() { lock(_gate) StopLocked(); }
}
