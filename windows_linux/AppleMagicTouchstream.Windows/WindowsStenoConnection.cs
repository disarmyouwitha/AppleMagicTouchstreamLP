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
    private UserSettings? _settings;
    private long _retryAt;
    internal void RefreshConnection(bool force=false)
    {
        lock(_gate)
        {
            if(!_enabled || _output==null || _eligible==null)return;
            if(!force && (_mode!="plugin" || _listener!=null || System.Diagnostics.Stopwatch.GetTimestamp()<_retryAt))return;
            if(force && _mode!="plugin")_dictionarySignature="";
            Configure(true,_output,_eligible,_settings);
        }
    }
    private string _mode="plugin",_dictionarySignature="";
    private bool _enabled,_loading;
    private int _loadGeneration,_resetTranslation;
    private WindowsJavelin? _translator;
    private JavelinEdit? _pendingEdit;
    private Action<ulong>? _recordStroke;
    internal bool CanOutput(long generation)
    {var output=_output;if(output==null)return false;lock(output.Sync)lock(_gate)return ReferenceEquals(output,_output) && _enabled && output.IsCurrent(generation) && _eligible?.Invoke()==true;}
    internal void ReportOutputError(){lock(_gate){ResetTranslation();_error="Windows blocked translated text output; translation history was reset.";}}
    internal bool IsBuiltIn {get{lock(_gate)return _mode!="plugin";}}
    internal void ResetTranslation()=>Interlocked.Exchange(ref _resetTranslation,1);
    internal JavelinEdit? TakeEdit(){lock(_gate){var value=_pendingEdit;_pendingEdit=null;return value;}}
    internal void SetRecorder(Action<ulong>? recorder){lock(_gate){_recordStroke=recorder;ResetTranslation();}}

    internal readonly record struct Snapshot(bool Enabled,bool Connected,long Sent,long Dropped,string? Error);
    public Snapshot Status { get { lock(_gate) return new(_enabled,_mode=="plugin" ? _reader!=null:_translator!=null && !_loading,_sent,_dropped,_error ?? (_loading ? "Loading dictionaries…":null)); } }
    public void Configure(bool enabled,StenoOutputState output,Func<bool> eligible,UserSettings? settings=null)
    {
        lock(_gate)
        {
            _output=output; _eligible=eligible;_enabled=enabled;_settings=settings;ResetTranslation();
            _retryAt=System.Diagnostics.Stopwatch.GetTimestamp()+2*System.Diagnostics.Stopwatch.Frequency;
            string mode=settings?.StenoConnectionMode ?? "plugin";
            if(mode is not ("javelin" or "javelinPlover" or "plugin"))mode="javelin";
            if(!enabled){_loadGeneration++;_loading=false;StopLocked();_translator?.Dispose();_translator=null;_dictionarySignature="";_error=null;return;}
            if(mode!="plugin")
            {
                StopLocked();_mode=mode;
                var sources=WindowsJavelinDictionaries.Sources(settings!,mode).Select(s=>s.Copy()).ToArray();
                string signature=mode+System.Text.Json.JsonSerializer.Serialize(sources);
                if(signature!=_dictionarySignature || _translator==null && !_loading)
                {
                    _translator?.Dispose();_translator=null;_dictionarySignature=signature;_loading=true;_error=null;int generation=++_loadGeneration;
                    _=Task.Run(()=>
                    {
                        WindowsJavelin? engine=null;
                        try{engine=WindowsJavelinDictionaries.Load(sources,mode=="javelinPlover");lock(_gate){if(generation!=_loadGeneration){engine.Dispose();return;}_translator?.Dispose();_translator=engine;engine=null;_loading=false;_error=null;}}
                        catch{engine?.Dispose();lock(_gate){if(generation==_loadGeneration){_loading=false;_error="Built-in Javelin unavailable. Check the native library/dictionaries, or choose Plover Plugin.";}}}
                    });
                }
                return;
            }
            if(_mode!="plugin"){_loadGeneration++;_translator?.Dispose();_translator=null;_dictionarySignature="";_loading=false;}
            _mode="plugin";
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
    internal bool TryFeedback(in DispatchEvent feedback,Action<TrackpadSide> vibrate)
    {
        var output=_output; if(output==null) return false;
        lock(output.Sync)
        lock(_gate)
        {
            long age=System.Diagnostics.Stopwatch.GetTimestamp()-feedback.TimestampTicks;
            if(!ReferenceEquals(output,_output) || feedback.Kind!=DispatchEventKind.StenoHaptic
                || !output.IsCurrent(feedback.StenoGeneration) || _eligible?.Invoke()!=true
                || age<0 || age>System.Diagnostics.Stopwatch.Frequency*.25) return false;
            vibrate(feedback.Side); return true;
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
                ) { _dropped++; return false; }
            if(_recordStroke is {} recorder){recorder(stroke.StenoMask);return true;}
            if(_mode!="plugin")
            {
                if(_translator==null || _loading){_dropped++;return false;}
                try{if(Interlocked.Exchange(ref _resetTranslation,0)!=0)_translator.Reset();_pendingEdit=_translator.Translate(stroke.StenoMask);_sent++;return true;}
                catch{_translator.Reset();_error="Translation cancelled; lift all fingers and try again.";_dropped++;return false;}
            }
            if(_reader==null){_dropped++;return false;}
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
    internal void Reload(){lock(_gate){_dictionarySignature="";}}
    public void Dispose() {lock(_gate){_loadGeneration++;_enabled=false;StopLocked();_translator?.Dispose();_translator=null;_recordStroke=null;}}
}
