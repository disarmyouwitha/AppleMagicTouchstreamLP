namespace AppleMagicTouchstream;

// Owned by the input window's thread. Learned formats are connection-local,
// never preferences, and never change merely because fingers move or lift.
internal sealed class TrackpadDecoderSession
{
    private sealed record Selection(string Path,RawInputDeviceInfo Info,TrackpadDecoderProfile? Override,
        TrackpadDecodeResult Format,int ReportLength);
    private readonly Dictionary<IntPtr,Selection> _selected=new();
    public void Reset() => _selected.Clear();
    public void Remove(IntPtr handle) => _selected.Remove(handle);

    public bool TryDecode(IntPtr handle,in RawInputDeviceSnapshot device,ReadOnlySpan<byte> payload,long timestamp,
        Dictionary<string,TrackpadDecoderProfile> overrides,out TrackpadDecoderProfile profile,out TrackpadDecodeResult decoded)
    {
        var info=device.Info;
        TrackpadDecoderProfile? configured=TrackpadDecoderProfileResolver.TryGetConfiguredOverride(overrides,device.DeviceName,out var explicitProfile)
            ? explicitProfile : null;
        if (_selected.TryGetValue(handle,out var selected))
        {
            if (selected.Info==device.Info && selected.Override==configured
                && string.Equals(selected.Path,device.DeviceName,StringComparison.OrdinalIgnoreCase))
            {
                profile=selected.Format.Profile; decoded=default;
                return payload.Length==selected.ReportLength
                    && TrackpadReportDecoder.TryDecodeLocked(payload,in info,timestamp,selected.Format,out decoded);
            }
            _selected.Remove(handle);
        }

        bool identified;
        if (configured.HasValue) { profile=configured.Value; identified=true; }
        else identified=TrackpadDecoderProfileResolver.TryResolveAuto(payload,in info,out profile);
        if (!TrackpadReportDecoder.TryDecode(payload,in info,timestamp,profile,out decoded) || decoded.Profile!=profile) return false;
        identified |= decoded.Kind==TrackpadReportKind.AppleNineByte;
        if (!identified && decoded.Frame.ContactCount>0) return false;
        // Empty/hover-only packets cannot establish an ambiguous startup choice.
        if (identified)
            for (int i=0;i<decoded.Frame.GetClampedContactCount();i++)
                if (decoded.Frame.GetContact(i).TipSwitch)
                {
                    _selected[handle]=new(device.DeviceName,device.Info,configured,decoded,payload.Length);
                    break;
                }
        return true;
    }
}
