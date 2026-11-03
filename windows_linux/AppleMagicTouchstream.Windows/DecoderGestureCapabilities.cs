using System.Threading;

namespace AppleMagicTouchstream;

// Connection-local observation, never a saved preference. Both old and extended
// open-source reports use the Legacy profile, so inspect the decoded format.
internal sealed class DecoderGestureCapabilities
{
    private int _left,_right;
    internal bool? FingerClassification(TrackpadSide side) => Volatile.Read(ref SideField(side)) switch {1=>false,2=>true,_=>null};
    private ref int SideField(TrackpadSide side)
    { if(side==TrackpadSide.Left) return ref _left; return ref _right; }
    internal void Observe(TrackpadSide side,TrackpadReportKind kind)
        =>Volatile.Write(ref SideField(side),kind==TrackpadReportKind.Unknown ? 0:kind==TrackpadReportKind.PtpExtended ? 2:1);
    internal void Reset(TrackpadSide? side=null)
    {
        if(side is {} selected) Volatile.Write(ref SideField(selected),0);
        else { Volatile.Write(ref _left,0); Volatile.Write(ref _right,0); }
    }
}
