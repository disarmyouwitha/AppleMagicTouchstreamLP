using System.IO;
using System.Text.Json;

namespace AppleMagicTouchstream;

// Local machine/user opt-in, separate from portable profiles and executable paths.
internal sealed class MouseTakeoverPreference
{
    private readonly object _gate=new();
    private readonly string _path;
    private bool _enabled;
    public string? LastSaveError { get; private set; }
    public bool Enabled { get { lock(_gate) return _enabled; } }
    public MouseTakeoverPreference(string? path=null)
    {
        _path=path ?? ApplicationDataPaths.UserFile("mouse-takeover.json");
        try { _enabled=JsonSerializer.Deserialize<bool>(File.ReadAllText(_path)); }
        catch { _enabled=false; }
    }
    public void SetEnabled(bool enabled)
    {
        lock(_gate)
        {
            if(_enabled==enabled && LastSaveError==null) return;
            _enabled=enabled;
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                File.WriteAllText(_path+".tmp",JsonSerializer.Serialize(enabled));
                File.Move(_path+".tmp",_path,overwrite:true);
                LastSaveError=null;
            }
            catch(Exception error) { LastSaveError=error.Message; }
        }
    }
}
