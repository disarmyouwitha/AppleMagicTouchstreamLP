namespace AppleMagicTouchstream;

internal static class SavedDeviceSelection
{
    public static HidDeviceInfo Resolve(ICollection<HidDeviceInfo> devices,string? path)
    {
        if(string.IsNullOrWhiteSpace(path)) return devices.First(d=>d.IsNone);
        var found=devices.FirstOrDefault(d=>string.Equals(d.Path,path,StringComparison.OrdinalIgnoreCase));
        if(found!=null) return found;
        var disconnected=new HidDeviceInfo("Saved trackpad (disconnected)",path);
        devices.Add(disconnected);
        return disconnected;
    }
}
