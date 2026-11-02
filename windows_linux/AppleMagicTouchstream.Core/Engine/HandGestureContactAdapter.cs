namespace AppleMagicTouchstream;

// Pure PTP coordinate/pressure projection, shared by production and offline tests.
public static class HandGestureContactAdapter
{
    public static int ReadContacts(in InputFrame frame, ushort maxX, ushort maxY, Span<HandGestureContact> contacts, out bool fourthContactPending)
    {
        int count = 0;
        bool pendingContact = false;
        for (int i = 0; i < frame.GetClampedContactCount(); i++)
        {
            var c = frame.GetContact(i);
            if (!c.TipSwitch)
            {
                // PTP has no Mac anatomical labels or native hover phase.
                // An in-range confident non-tip slot is the available landing
                // evidence; it never counts as a touching finger or movement.
                pendingContact |= c.Confidence && maxX > 0 && maxY > 0 && c.X <= maxX && c.Y <= maxY;
                continue;
            }
            contacts[count++] = new(c.Id, maxX == 0 ? double.NaN : c.X * 160.0 / maxX,
                maxY == 0 ? double.NaN : c.Y * 114.9 / maxY, Pressure:c.Pressure8, HasPressure:c.HasForceData);
        }
        fourthContactPending = count == 3 && pendingContact;
        return count;
    }
}
