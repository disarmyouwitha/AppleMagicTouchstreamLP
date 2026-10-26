namespace GlassToKey;

// Windows' new gesture preferences deliberately do not migrate legacy keyboard gestures.
public enum HandGestureTrigger
{
    TwoFingerMove, TwoFingerTap, ThreeFingerMove, ThreeFingerTap, FourFingerMove, ThumbTwoTap,
    TwoFingerPinch, ThreeFingerPinch, FourFingerPinch, FiveFingerPinch,
    TwoFingerSpread, ThreeFingerSpread, FourFingerSpread, FiveFingerSpread,
    OneFingerForce, TwoFingerForce, ThreeFingerForce, FourFingerForce, FiveFingerForce,
    // Append only: profiles have shipped with numeric enum identities.
    FourFingerTap, FiveFingerTap, FiveFingerMove
}
public enum HandGestureAction { None, Pointer, PrimaryDrag, Scroll, PrimaryClick, DoubleClick, SecondaryClick, Zoom, NotificationCenter, TaskView, StartMenu, ShowDesktop,
    OpenConfig, ScrollUp, ScrollDown, PanLeft, PanRight, Back, Forward, Copy, Paste, Cut, Undo, Redo, SelectAll, Voice, Custom }
public enum HandPointerResponse { AppleReference, ImportedApple, Fixed }
public enum HandGestureScope { Left, Right, Both }
public enum HandMovementDirection { Up, Down, Left, Right }
public enum HandCornerChord { OuterCorners, InnerCorners, TopOuter, BottomOuter, TopInner, BottomInner }
public enum CoordinatedHandChord { ThreeFingers, FourFingers, OuterCorners, InnerCorners, TopOuter, BottomOuter, TopInner, BottomInner }

public sealed class CoordinatedGestureSettings
{
    public Dictionary<CoordinatedHandChord, HandGestureAction> TapActions { get; set; } = new();
    public Dictionary<CoordinatedHandChord, HandGestureAction> HoldActions { get; set; } = new();
    public Dictionary<CoordinatedHandChord, double> HoldThresholds { get; set; } = new();
    public Dictionary<string, string> CustomActions { get; set; } = new();
    public HashSet<string> HeldShortcuts { get; set; } = new();
    public HandGestureAction Action(CoordinatedHandChord chord, bool hold) => ((hold ? HoldActions : TapActions)?.GetValueOrDefault(chord,
        hold && chord==CoordinatedHandChord.OuterCorners ? HandGestureAction.OpenConfig : HandGestureAction.None)
        ?? (hold && chord==CoordinatedHandChord.OuterCorners ? HandGestureAction.OpenConfig : HandGestureAction.None)) is {} action
        && PerHandGestureSettings.IsDiscrete(action) && (hold || chord is CoordinatedHandChord.ThreeFingers or CoordinatedHandChord.FourFingers)
        ? action : HandGestureAction.None;
    public double Milliseconds(CoordinatedHandChord chord) => HoldThresholds?.GetValueOrDefault(chord, 500) is {} value && double.IsFinite(value)
        ? Math.Clamp(value,100,5000) : 500;
    public CoordinatedGestureSettings Clone() => new() { TapActions = new(TapActions ?? new()), HoldActions = new(HoldActions ?? new()), HoldThresholds = new(HoldThresholds ?? new()), CustomActions = new(CustomActions ?? new()), HeldShortcuts = new(HeldShortcuts ?? new()) };
}

public sealed class HandDirectionalSettings
{
    public bool Enabled { get; set; }
    public Dictionary<HandMovementDirection, HandGestureAction> Actions { get; set; } = new();
    public Dictionary<HandMovementDirection, double> RepeatMilliseconds { get; set; } = new();
    public HandGestureAction Get(HandMovementDirection direction) => Actions.TryGetValue(direction, out var value)
        && PerHandGestureSettings.IsDiscrete(value) ? value : HandGestureAction.None;
    public double Repeat(HandMovementDirection direction) => RepeatMilliseconds.TryGetValue(direction, out double value)
        && double.IsFinite(value) && value > 0 ? Math.Clamp(value, 20, 5000) : 0;
    public bool HasActions => Get(HandMovementDirection.Up) != HandGestureAction.None || Get(HandMovementDirection.Down) != HandGestureAction.None
        || Get(HandMovementDirection.Left) != HandGestureAction.None || Get(HandMovementDirection.Right) != HandGestureAction.None;
    public HandDirectionalSettings Clone() => new() { Enabled = Enabled, Actions = new(Actions ?? new()), RepeatMilliseconds = new(RepeatMilliseconds ?? new()) };
}

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
    public Dictionary<string,string>? CustomActions { get; set; }
    public HashSet<string> HeldShortcuts { get; set; } = new();
    public Dictionary<int, HandGestureAction>? HoldActions { get; set; }
    public Dictionary<int, double>? HoldThresholds { get; set; }
    public Dictionary<HandGestureTrigger, HandDirectionalSettings>? DirectionalMovement { get; set; }
    public Dictionary<HandCornerChord, HandGestureAction>? CornerHoldActions { get; set; }
    public Dictionary<HandCornerChord, double>? CornerHoldThresholds { get; set; }
    public HandGestureAction CornerAction(HandCornerChord chord) => (CornerHoldActions?.GetValueOrDefault(chord,
        chord==HandCornerChord.OuterCorners ? HandGestureAction.OpenConfig : HandGestureAction.None)
        ?? (chord==HandCornerChord.OuterCorners ? HandGestureAction.OpenConfig : HandGestureAction.None)) is {} action
        && IsDiscrete(action) ? action : HandGestureAction.None;
    public double CornerMilliseconds(HandCornerChord chord) => CornerHoldThresholds?.GetValueOrDefault(chord,500) is {} value && double.IsFinite(value)
        ? Math.Clamp(value,100,5000) : 500;
    public HandGestureAction Hold(int count) => count is >= 2 and <= 5 && HoldActions?.GetValueOrDefault(count) is {} action
        && IsDiscrete(action) ? action : HandGestureAction.None;
    public double HoldMilliseconds(int count) => HoldThresholds?.GetValueOrDefault(count, 500) is {} value && double.IsFinite(value)
        ? Math.Clamp(value, 100, 5000) : 500;
    public HandDirectionalSettings? Directional(HandGestureTrigger trigger) => IsMovement(trigger)
        && DirectionalMovement?.GetValueOrDefault(trigger) is { Enabled: true } value ? value : null;
    public bool Enabled(HandGestureTrigger trigger) => Directional(trigger) is {} directions ? directions.HasActions : Get(trigger) != HandGestureAction.None;
    public PerHandGestureSettings Clone()
    {
        var clone = (PerHandGestureSettings)MemberwiseClone();
        clone.ImportedPointerProfile = ImportedPointerProfile?.Copy();
        clone.AdditionalActions = AdditionalActions == null ? null : new(AdditionalActions);
        clone.CustomActions = CustomActions == null ? null : new(CustomActions);
        clone.HeldShortcuts = new(HeldShortcuts ?? new());
        clone.HoldActions = HoldActions == null ? null : new(HoldActions);
        clone.HoldThresholds = HoldThresholds == null ? null : new(HoldThresholds);
        clone.DirectionalMovement = DirectionalMovement?.Where(p=>p.Value!=null).ToDictionary(p => p.Key, p => p.Value.Clone());
        clone.CornerHoldActions = CornerHoldActions == null ? null : new(CornerHoldActions);
        clone.CornerHoldThresholds = CornerHoldThresholds == null ? null : new(CornerHoldThresholds);
        return clone;
    }
    public static bool IsPinch(HandGestureTrigger t) => t is >= HandGestureTrigger.TwoFingerPinch and <= HandGestureTrigger.FiveFingerSpread;
    public static HandGestureTrigger? Pinch(int count, bool spread = false) => count is >= 2 and <= 5
        ? (HandGestureTrigger)((int)(spread ? HandGestureTrigger.TwoFingerSpread : HandGestureTrigger.TwoFingerPinch) + count - 2) : null;
    public static HandGestureTrigger? Force(int count) => count is >= 1 and <= 5 ? (HandGestureTrigger)((int)HandGestureTrigger.OneFingerForce+count-1) : null;
    public static bool IsSystemAction(HandGestureAction a) => a is >= HandGestureAction.NotificationCenter and <= HandGestureAction.ShowDesktop;
    public static bool IsForce(HandGestureTrigger t) => t is >= HandGestureTrigger.OneFingerForce and <= HandGestureTrigger.FiveFingerForce;
    public static bool IsDiscrete(HandGestureAction a) => Enum.IsDefined(a) && a is not (HandGestureAction.Pointer or HandGestureAction.PrimaryDrag or HandGestureAction.Scroll or HandGestureAction.Zoom);
    public static bool IsValidCustom(string? label) => !string.IsNullOrWhiteSpace(label) && (AppLaunchActionHelper.TryParse(label,out _)
        || DispatchShortcutHelper.TryReadShortcut(label,out _,out _) || DispatchKeyResolver.TryResolveVirtualKey(label,out _));
    public static bool IsMovement(HandGestureTrigger t) => t is HandGestureTrigger.TwoFingerMove or HandGestureTrigger.ThreeFingerMove or HandGestureTrigger.FourFingerMove or HandGestureTrigger.FiveFingerMove;
    public static HandGestureTrigger? Movement(int count) => count switch { 2 => HandGestureTrigger.TwoFingerMove, 3 => HandGestureTrigger.ThreeFingerMove, 4 => HandGestureTrigger.FourFingerMove, 5 => HandGestureTrigger.FiveFingerMove, _ => null };
    public static bool IsContinuous(HandGestureTrigger t) => IsPinch(t) || IsMovement(t);
    public static bool Allows(HandGestureTrigger t, HandGestureAction a) => Enum.IsDefined(t) && Enum.IsDefined(a) && (a == HandGestureAction.None
        || (IsPinch(t) ? a == HandGestureAction.Zoom || IsDiscrete(a)
        : IsForce(t) ? IsDiscrete(a)
        : IsContinuous(t)
        ? a is HandGestureAction.Pointer or HandGestureAction.PrimaryDrag or HandGestureAction.Scroll
        : IsDiscrete(a)));
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
        HeldShortcuts ??= new();
        foreach (var t in Enum.GetValues<HandGestureTrigger>()) Set(t, Get(t));
        if (!Enum.IsDefined(PointerResponse)) PointerResponse = HandPointerResponse.AppleReference;
        if (PointerResponse == HandPointerResponse.ImportedApple && ImportedPointerProfile == null) PointerResponse = HandPointerResponse.AppleReference;
        PointerSensitivity = Gain(PointerSensitivity); ScrollSensitivity = Gain(ScrollSensitivity); ZoomSensitivity = Gain(ZoomSensitivity);
        if (DirectionalMovement != null) foreach (var pair in DirectionalMovement.ToArray())
        {
            if (pair.Value==null) { DirectionalMovement.Remove(pair.Key); continue; }
            pair.Value.Actions ??= new(); pair.Value.RepeatMilliseconds ??= new();
            foreach (var direction in Enum.GetValues<HandMovementDirection>())
                if (pair.Value.Get(direction)==HandGestureAction.Custom && !IsValidCustom(CustomActions?.GetValueOrDefault(pair.Key+"/"+direction)))
                    pair.Value.Actions[direction]=HandGestureAction.None;
        }
        foreach (var trigger in Enum.GetValues<HandGestureTrigger>())
            if (Get(trigger)==HandGestureAction.Custom && !IsValidCustom(CustomActions?.GetValueOrDefault(trigger.ToString()))) Set(trigger,HandGestureAction.None);
        if (HoldActions!=null) foreach (int count in HoldActions.Keys.ToArray())
            if (HoldActions[count]==HandGestureAction.Custom && !IsValidCustom(CustomActions?.GetValueOrDefault("Hold"+count))) HoldActions[count]=HandGestureAction.None;
        if (CornerAction(HandCornerChord.OuterCorners)==HandGestureAction.Custom && !IsValidCustom(CustomActions?.GetValueOrDefault("CornerHold")))
            (CornerHoldActions ??= new())[HandCornerChord.OuterCorners]=HandGestureAction.None;
    }
    private static double Gain(double x) => double.IsFinite(x) ? Math.Clamp(x, .25, 2) : 1;
}

public sealed class HandGestureSettings
{
    public PerHandGestureSettings Left { get; set; } = new();
    public PerHandGestureSettings Right { get; set; } = new();
    public CoordinatedGestureSettings Coordinated { get; set; } = new();
    public HandGestureSettings Clone() => new() { Left = (Left ?? new()).Clone(), Right = (Right ?? new()).Clone(), Coordinated = (Coordinated ?? new()).Clone() };
    public void Normalize()
    {
        Left ??= new(); Right ??= new(); Left.Normalize(); Right.Normalize();
        Coordinated ??= new(); Coordinated.TapActions ??= new(); Coordinated.HoldActions ??= new(); Coordinated.HoldThresholds ??= new(); Coordinated.CustomActions ??= new();
        Coordinated.HeldShortcuts ??= new();
        foreach (var chord in Enum.GetValues<CoordinatedHandChord>()) foreach (bool hold in new[] {false,true})
            if (Coordinated.Action(chord,hold)==HandGestureAction.Custom
                && !PerHandGestureSettings.IsValidCustom(Coordinated.CustomActions.GetValueOrDefault(chord+"/"+(hold ? "Hold" : "Tap"))))
                (hold ? Coordinated.HoldActions : Coordinated.TapActions)[chord]=HandGestureAction.None;
    }
    public PerHandGestureSettings For(TrackpadSide side, bool sameDevice = false)
    {
        var result = (side == TrackpadSide.Left ? Left : Right).Clone();
        if (sameDevice)
        {
            void copyCustom(string slot)
            { if (Right.CustomActions?.GetValueOrDefault(slot) is {} label) (result.CustomActions ??= new())[slot]=label;
                if (Right.HeldShortcuts?.Contains(slot)==true) result.HeldShortcuts.Add(slot); else result.HeldShortcuts.Remove(slot); }
            foreach (var t in Enum.GetValues<HandGestureTrigger>())
                if (!result.Enabled(t))
                {
                    result.Set(t,Right.Get(t)); copyCustom(t.ToString());
                    if (PerHandGestureSettings.IsMovement(t))
                    {
                        result.DirectionalMovement?.Remove(t);
                        if (Right.Directional(t) is {} directions)
                        {
                            (result.DirectionalMovement ??= new())[t]=directions.Clone();
                            foreach (var direction in Enum.GetValues<HandMovementDirection>()) copyCustom(t+"/"+direction);
                        }
                    }
                }
            for (int count=2;count<=5;count++) if (result.Hold(count)==HandGestureAction.None && Right.Hold(count)!=HandGestureAction.None)
            {
                (result.HoldActions ??= new())[count]=Right.Hold(count);
                (result.HoldThresholds ??= new())[count]=Right.HoldMilliseconds(count); copyCustom("Hold"+count);
            }
            if (result.CornerAction(HandCornerChord.OuterCorners)==HandGestureAction.None && Right.CornerAction(HandCornerChord.OuterCorners)!=HandGestureAction.None)
            {
                (result.CornerHoldActions ??= new())[HandCornerChord.OuterCorners]=Right.CornerAction(HandCornerChord.OuterCorners);
                (result.CornerHoldThresholds ??= new())[HandCornerChord.OuterCorners]=Right.CornerMilliseconds(HandCornerChord.OuterCorners); copyCustom("CornerHold");
            }
            result.Normalize();
        }
        return result;
    }
}
