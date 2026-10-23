namespace GlassToKey;

// Windows' new gesture preferences deliberately do not migrate legacy keyboard gestures.
public enum HandGestureTrigger { TwoFingerMove, TwoFingerTap, ThreeFingerMove, ThreeFingerTap, FourFingerMove, ThumbTwoTap }
public enum HandGestureAction { None, Pointer, PrimaryDrag, Scroll, PrimaryClick, DoubleClick, SecondaryClick }
public enum HandPointerResponse { AppleReference, ImportedApple, Fixed }
public enum HandGestureScope { Left, Right, Both }

public sealed class PerHandGestureSettings
{
    public HandGestureAction TwoFingerMove { get; set; } = HandGestureAction.Pointer;
    public HandGestureAction TwoFingerTap { get; set; } = HandGestureAction.PrimaryClick;
    public HandGestureAction ThreeFingerMove { get; set; } = HandGestureAction.PrimaryDrag;
    public HandGestureAction ThreeFingerTap { get; set; } = HandGestureAction.DoubleClick;
    public HandGestureAction FourFingerMove { get; set; } = HandGestureAction.Scroll;
    public HandGestureAction ThumbTwoTap { get; set; } = HandGestureAction.SecondaryClick;
    public HandPointerResponse PointerResponse { get; set; } = HandPointerResponse.AppleReference;
    public ApplePointerProfile? ImportedPointerProfile { get; set; }
    public bool NaturalScrolling { get; set; } = true;
    public double PointerSensitivity { get; set; } = 1;
    public double ScrollSensitivity { get; set; } = 1;
    public PerHandGestureSettings Clone()
    {
        var clone = (PerHandGestureSettings)MemberwiseClone();
        clone.ImportedPointerProfile = ImportedPointerProfile?.Copy();
        return clone;
    }
    public static bool IsContinuous(HandGestureTrigger t) => t is HandGestureTrigger.TwoFingerMove or HandGestureTrigger.ThreeFingerMove or HandGestureTrigger.FourFingerMove;
    public static bool Allows(HandGestureTrigger t, HandGestureAction a) => a == HandGestureAction.None || (IsContinuous(t)
        ? a is HandGestureAction.Pointer or HandGestureAction.PrimaryDrag or HandGestureAction.Scroll
        : a is HandGestureAction.PrimaryClick or HandGestureAction.DoubleClick or HandGestureAction.SecondaryClick);
    public HandGestureAction Get(HandGestureTrigger t)
    {
        var a = t switch { HandGestureTrigger.TwoFingerMove => TwoFingerMove, HandGestureTrigger.TwoFingerTap => TwoFingerTap,
            HandGestureTrigger.ThreeFingerMove => ThreeFingerMove, HandGestureTrigger.ThreeFingerTap => ThreeFingerTap,
            HandGestureTrigger.FourFingerMove => FourFingerMove, _ => ThumbTwoTap };
        return Allows(t, a) ? a : HandGestureAction.None;
    }
    public void Set(HandGestureTrigger t, HandGestureAction a)
    {
        if (!Allows(t, a)) return;
        switch (t) { case HandGestureTrigger.TwoFingerMove: TwoFingerMove = a; break; case HandGestureTrigger.TwoFingerTap: TwoFingerTap = a; break;
            case HandGestureTrigger.ThreeFingerMove: ThreeFingerMove = a; break; case HandGestureTrigger.ThreeFingerTap: ThreeFingerTap = a; break;
            case HandGestureTrigger.FourFingerMove: FourFingerMove = a; break; case HandGestureTrigger.ThumbTwoTap: ThumbTwoTap = a; break; }
    }
    public void Normalize()
    {
        foreach (var t in Enum.GetValues<HandGestureTrigger>()) Set(t, Get(t));
        if (!Enum.IsDefined(PointerResponse)) PointerResponse = HandPointerResponse.AppleReference;
        if (PointerResponse == HandPointerResponse.ImportedApple && ImportedPointerProfile == null) PointerResponse = HandPointerResponse.AppleReference;
        PointerSensitivity = Gain(PointerSensitivity); ScrollSensitivity = Gain(ScrollSensitivity);
    }
    private static double Gain(double x) => double.IsFinite(x) ? Math.Clamp(x, .25, 2) : 1;
}

public sealed class HandGestureSettings
{
    public PerHandGestureSettings Left { get; set; } = new();
    public PerHandGestureSettings Right { get; set; } = new();
    public HandGestureSettings Clone() => new() { Left = (Left ?? new()).Clone(), Right = (Right ?? new()).Clone() };
    public void Normalize() { Left ??= new(); Right ??= new(); Left.Normalize(); Right.Normalize(); }
    public PerHandGestureSettings For(TrackpadSide side, bool sameDevice = false)
    {
        var result = (side == TrackpadSide.Left ? Left : Right).Clone();
        if (sameDevice) foreach (var t in Enum.GetValues<HandGestureTrigger>())
            if (result.Get(t) == HandGestureAction.None) result.Set(t, Right.Get(t));
        return result;
    }
}
