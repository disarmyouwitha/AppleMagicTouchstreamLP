namespace AppleMagicTouchstream;
// Name-only adapter for existing tests; production calls this same Core method.
internal static class WindowsHandGestures
{
    internal static int ReadContacts(in InputFrame frame,ushort x,ushort y,Span<HandGestureContact> contacts,out bool pending)
        =>HandGestureContactAdapter.ReadContacts(in frame,x,y,contacts,out pending);
}
