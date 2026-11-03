namespace AppleMagicTouchstream;

// Pure PTP coordinate/pressure projection, shared by production and offline tests.
public static class HandGestureContactAdapter
{
    public static int ReadContacts(in InputFrame frame, ushort maxX, ushort maxY, Span<HandGestureContact> contacts, out bool fourthContactPending)
        => ReadContacts(in frame,maxX,maxY,contacts,out fourthContactPending,out _);

    public static int ReadContacts(in InputFrame frame, ushort maxX, ushort maxY, Span<HandGestureContact> contacts,
        out bool fourthContactPending,out bool thirdContactPending)
    {
        int count = 0;
        bool pendingContact = false,nativePendingContact=false;
        for (int i = 0; i < frame.GetClampedContactCount(); i++)
        {
            var c = frame.GetContact(i);
            if (!c.TipSwitch)
            {
                // Hover is landing evidence, never an additional touching finger.
                bool pending=c.Confidence && c.Telemetry?.FingerType!=6 && maxX>0 && maxY>0 && c.X<=maxX && c.Y<=maxY;
                pendingContact |= pending;
                nativePendingContact |= pending && c.Telemetry.HasValue;
                continue;
            }
            int finger=c.Telemetry?.FingerType is >=1 and <=6 ? c.Telemetry.Value.FingerType : 0;
            contacts[count++] = new(c.Id, maxX == 0 ? double.NaN : c.X * 160.0 / maxX,
                maxY == 0 ? double.NaN : c.Y * 114.9 / maxY, Finger:finger,Pressure:c.Pressure8, HasPressure:c.HasForceData);
        }
        fourthContactPending = count == 3 && pendingContact;
        thirdContactPending = count == 2 && nativePendingContact;
        return count;
    }
}
