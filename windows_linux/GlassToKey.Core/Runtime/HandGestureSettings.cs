namespace GlassToKey;

// Windows' new gesture preferences deliberately do not migrate legacy keyboard gestures.
public enum HandGestureTrigger
{
    TwoFingerMove, TwoFingerTap, ThreeFingerMove, ThreeFingerTap, FourFingerMove, ThumbTwoTap,
    TwoFingerPinch, ThreeFingerPinch, FourFingerPinch, FiveFingerPinch,
    TwoFingerSpread, ThreeFingerSpread, FourFingerSpread, FiveFingerSpread,
    OneFingerForce, TwoFingerForce, ThreeFingerForce, FourFingerForce, FiveFingerForce
}
public enum HandGestureAction { None, Pointer, PrimaryDrag, Scroll, PrimaryClick, DoubleClick, SecondaryClick, Zoom, NotificationCenter, TaskView, StartMenu, ShowDesktop }
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
    public double ZoomSensitivity { get; set; } = 1;
    public Dictionary<HandGestureTrigger, HandGestureAction>? AdditionalActions { get; set; }
    public PerHandGestureSettings Clone()
    {
        var clone = (PerHandGestureSettings)MemberwiseClone();
        clone.ImportedPointerProfile = ImportedPointerProfile?.Copy();
        clone.AdditionalActions = AdditionalActions == null ? null : new(AdditionalActions);
        return clone;
    }
    public static bool IsPinch(HandGestureTrigger t) => t is >= HandGestureTrigger.TwoFingerPinch and <= HandGestureTrigger.FiveFingerSpread;
    public static HandGestureTrigger? Pinch(int count, bool spread = false) => count is >= 2 and <= 5
        ? (HandGestureTrigger)((int)(spread ? HandGestureTrigger.TwoFingerSpread : HandGestureTrigger.TwoFingerPinch) + count - 2) : null;
    public static HandGestureTrigger? Force(int count) => count is >= 1 and <= 5 ? (HandGestureTrigger)((int)HandGestureTrigger.OneFingerForce+count-1) : null;
    public static bool IsSystemAction(HandGestureAction a) => a is >= HandGestureAction.NotificationCenter and <= HandGestureAction.ShowDesktop;
    public static bool IsContinuous(HandGestureTrigger t) => IsPinch(t) || t is HandGestureTrigger.TwoFingerMove or HandGestureTrigger.ThreeFingerMove or HandGestureTrigger.FourFingerMove;
    public static bool Allows(HandGestureTrigger t, HandGestureAction a) => Enum.IsDefined(t) && Enum.IsDefined(a) && (a == HandGestureAction.None
        || (IsPinch(t) ? a == HandGestureAction.Zoom || IsSystemAction(a)
        : t >= HandGestureTrigger.OneFingerForce ? a is HandGestureAction.PrimaryClick or HandGestureAction.DoubleClick or HandGestureAction.SecondaryClick || IsSystemAction(a)
        : IsContinuous(t)
        ? a is HandGestureAction.Pointer or HandGestureAction.PrimaryDrag or HandGestureAction.Scroll
        : a is HandGestureAction.PrimaryClick or HandGestureAction.DoubleClick or HandGestureAction.SecondaryClick));
    public HandGestureAction Get(HandGestureTrigger t)
    {
        var a = t switch { HandGestureTrigger.TwoFingerMove => TwoFingerMove, HandGestureTrigger.TwoFingerTap => TwoFingerTap,
            HandGestureTrigger.ThreeFingerMove => ThreeFingerMove, HandGestureTrigger.ThreeFingerTap => ThreeFingerTap,
            HandGestureTrigger.FourFingerMove => FourFingerMove, HandGestureTrigger.ThumbTwoTap => ThumbTwoTap,
            _ => AdditionalActions?.GetValueOrDefault(t, Default(t)) ?? Default(t) };
        return Allows(t, a) ? a : HandGestureAction.None;
    }
    public void Set(HandGestureTrigger t, HandGestureAction a)
    {
        if (!Allows(t, a)) return;
        switch (t) { case HandGestureTrigger.TwoFingerMove: TwoFingerMove = a; break; case HandGestureTrigger.TwoFingerTap: TwoFingerTap = a; break;
            case HandGestureTrigger.ThreeFingerMove: ThreeFingerMove = a; break; case HandGestureTrigger.ThreeFingerTap: ThreeFingerTap = a; break;
            case HandGestureTrigger.FourFingerMove: FourFingerMove = a; break; case HandGestureTrigger.ThumbTwoTap: ThumbTwoTap = a; break;
            default: (AdditionalActions ??= new())[t] = a; break; }
    }
    private static HandGestureAction Default(HandGestureTrigger t) => IsPinch(t) ? HandGestureAction.Zoom
        : t == HandGestureTrigger.OneFingerForce ? HandGestureAction.PrimaryClick : HandGestureAction.None;
    public void Normalize()
    {
        foreach (var t in Enum.GetValues<HandGestureTrigger>()) Set(t, Get(t));
        if (!Enum.IsDefined(PointerResponse)) PointerResponse = HandPointerResponse.AppleReference;
        if (PointerResponse == HandPointerResponse.ImportedApple && ImportedPointerProfile == null) PointerResponse = HandPointerResponse.AppleReference;
        PointerSensitivity = Gain(PointerSensitivity); ScrollSensitivity = Gain(ScrollSensitivity); ZoomSensitivity = Gain(ZoomSensitivity);
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
