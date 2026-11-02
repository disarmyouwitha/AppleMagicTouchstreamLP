namespace AppleMagicTouchstream;

// Value-only UI feedback, independent of output injection and user assignments.
// Production records only enums/timestamps on the frame path; titles are built
// when the UI reads a recent result. No settings/capture or secret text payload.
public enum HandRecognitionKind { Gesture, Hold, CornerHold, CoordinatedTap, CoordinatedHold, CoordinatedForce,
    StenoPointer, StenoDrag, StenoPrimaryClick, StenoSecondaryClick, StenoScroll }
public readonly record struct HandGestureRecognition(HandRecognitionKind Kind,double Time,HandGestureTrigger Trigger=default,
    int Count=0,HandMovementDirection? Direction=null,CoordinatedHandChord Chord=default)
{
    public bool Visible(double now)=>double.IsFinite(now) && now>=Time && now-Time<2;
    public string Title
    {
        get
        {
            if(Kind==HandRecognitionKind.Hold) return $"{Count}-finger hold";
            if(Kind==HandRecognitionKind.CornerHold) return "Outer Corners Hold";
            if(Kind is HandRecognitionKind.CoordinatedTap or HandRecognitionKind.CoordinatedHold or HandRecognitionKind.CoordinatedForce)
            {
                string chord=Chord switch { CoordinatedHandChord.ThreeFingers=>"3 fingers per hand",CoordinatedHandChord.FourFingers=>"4 fingers per hand",
                    CoordinatedHandChord.OuterCorners=>"Outer Corners",CoordinatedHandChord.InnerCorners=>"Inner Corners",CoordinatedHandChord.TopOuter=>"Top Outer Corners",
                    CoordinatedHandChord.BottomOuter=>"Bottom Outer Corners",CoordinatedHandChord.TopInner=>"Top Inner Corners",_=>"Bottom Inner Corners" };
                return $"Both · {chord} {(Kind==HandRecognitionKind.CoordinatedTap ? "Tap" : Kind==HandRecognitionKind.CoordinatedHold ? "Hold" : "Force Click")}";
            }
            string title=Kind switch { HandRecognitionKind.StenoPointer=>"2F mouse",HandRecognitionKind.StenoDrag=>"1F drag/select",
                HandRecognitionKind.StenoPrimaryClick=>"2F left-click",HandRecognitionKind.StenoSecondaryClick=>"3F right-click",HandRecognitionKind.StenoScroll=>"4F force scroll",_=>TriggerTitle(Trigger) };
            return Direction is {} direction ? title+" "+(direction switch { HandMovementDirection.Up=>"↑",HandMovementDirection.Down=>"↓",HandMovementDirection.Left=>"←",_=>"→" }) : title;
        }
    }
    private static string TriggerTitle(HandGestureTrigger trigger)
    {
        for(int count=2;count<=5;count++)
        {
            if(PerHandGestureSettings.Movement(count)==trigger) return $"{count}-finger movement";
            if(PerHandGestureSettings.Pinch(count)==trigger) return $"{count}-finger pinch";
            if(PerHandGestureSettings.Pinch(count,true)==trigger) return $"{count}-finger spread";
            if(PerHandGestureSettings.Rotation(count)==trigger) return $"{count}-finger rotate left";
            if(PerHandGestureSettings.Rotation(count,true)==trigger) return $"{count}-finger rotate right";
        }
        for(int count=1;count<=5;count++) if(PerHandGestureSettings.Force(count)==trigger) return $"{count}-finger force click";
        return trigger switch { HandGestureTrigger.TwoFingerTap=>"2-finger tap",HandGestureTrigger.ThreeFingerTap=>"3-finger tap",
            HandGestureTrigger.FourFingerTap=>"4-finger tap",HandGestureTrigger.FiveFingerTap=>"5-finger tap",HandGestureTrigger.ThumbTwoTap=>"Thumb + 2 fingertips tap",_=>"Gesture" };
    }
}
