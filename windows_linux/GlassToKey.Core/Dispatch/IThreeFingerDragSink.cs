namespace GlassToKey;

public interface IThreeFingerDragSink
{
    void MovePointerBy(int deltaX, int deltaY);
    void NotifyPointerActivity();
    void SetLeftButtonState(bool pressed);
}
