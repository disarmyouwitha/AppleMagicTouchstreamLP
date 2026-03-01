using System.Diagnostics;
using GlassToKey;

namespace GlassToKey.Platform.Linux.Evdev;

public sealed class LinuxMtFrameAssembler
{
    public const byte SyntheticReportId = 0xEE;
    private const byte ActiveContactFlags = 0x03;
    private const int LegacyContactId = 1;

    private LinuxMtSlotState[] _slots;
    private readonly long _openTimestampTicks;
    private int _currentSlot;
    private bool _buttonPressed;
    private LegacyContactState _legacyContact;

    public LinuxMtFrameAssembler(int slotCount, ushort maxX, ushort maxY)
    {
        if (slotCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(slotCount));
        }

        _slots = new LinuxMtSlotState[slotCount];
        MaxX = maxX;
        MaxY = maxY;
        _openTimestampTicks = Stopwatch.GetTimestamp();
    }

    public ushort MaxX { get; }

    public ushort MaxY { get; }

    public int SlotCount => _slots.Length;

    public int FrameSequence { get; private set; }

    public int LastOverflowContactCount { get; private set; }

    public long TotalOverflowContactCount { get; private set; }

    public void Reset()
    {
        Array.Clear(_slots, 0, _slots.Length);
        _currentSlot = 0;
        _buttonPressed = false;
        _legacyContact = default;
        FrameSequence = 0;
        LastOverflowContactCount = 0;
        TotalOverflowContactCount = 0;
    }

    public void SelectSlot(int slot)
    {
        if (slot < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(slot));
        }

        EnsureSlotCapacity(slot);
        _currentSlot = slot;
    }

    public void SetTrackingId(int trackingId)
    {
        ref LinuxMtSlotState slot = ref _slots[_currentSlot];
        slot.TrackingId = trackingId;
        if (trackingId < 0)
        {
            slot = default;
            return;
        }

        slot.IsActive = true;
    }

    public void SetPositionX(int xRaw)
    {
        ref LinuxMtSlotState slot = ref _slots[_currentSlot];
        slot.XRaw = xRaw;
    }

    public void SetPositionY(int yRaw)
    {
        ref LinuxMtSlotState slot = ref _slots[_currentSlot];
        slot.YRaw = yRaw;
    }

    public void SetPressure(int pressureRaw)
    {
        ref LinuxMtSlotState slot = ref _slots[_currentSlot];
        slot.PressureRaw = pressureRaw;
    }

    public void SetOrientation(int orientationRaw)
    {
        ref LinuxMtSlotState slot = ref _slots[_currentSlot];
        slot.OrientationRaw = orientationRaw;
    }

    public void SetButtonPressed(bool isPressed)
    {
        _buttonPressed = isPressed;
    }

    public void SetLegacyPositionX(int xRaw)
    {
        _legacyContact.XRaw = xRaw;
        _legacyContact.SeenThisFrame = true;
    }

    public void SetLegacyPositionY(int yRaw)
    {
        _legacyContact.YRaw = yRaw;
        _legacyContact.SeenThisFrame = true;
    }

    public void SetLegacyPressure(int pressureRaw)
    {
        _legacyContact.PressureRaw = pressureRaw;
        if (pressureRaw > 0)
        {
            _legacyContact.IsActive = true;
        }

        _legacyContact.SeenThisFrame = true;
    }

    public void SetLegacyTouchMajor(int touchMajorRaw)
    {
        _legacyContact.TouchMajorRaw = touchMajorRaw;
        if (touchMajorRaw > 0)
        {
            _legacyContact.IsActive = true;
        }

        _legacyContact.SeenThisFrame = true;
    }

    public void SetLegacyTouchMinor(int touchMinorRaw)
    {
        _legacyContact.TouchMinorRaw = touchMinorRaw;
        if (touchMinorRaw > 0)
        {
            _legacyContact.IsActive = true;
        }

        _legacyContact.SeenThisFrame = true;
    }

    public void SetLegacyTouchActive(bool isActive)
    {
        _legacyContact.IsActive = isActive;
        if (!isActive)
        {
            _legacyContact.TouchMajorRaw = 0;
            _legacyContact.TouchMinorRaw = 0;
            _legacyContact.PressureRaw = 0;
        }
    }

    public InputFrame CommitFrame()
    {
        long nowTicks = Stopwatch.GetTimestamp();
        return CommitFrame(nowTicks);
    }

    public InputFrame CommitFrame(long timestampTicks)
    {
        InputFrame frame = new()
        {
            ArrivalQpcTicks = timestampTicks,
            ReportId = SyntheticReportId,
            ScanTime = ComputeScanTime(timestampTicks),
            IsButtonClicked = _buttonPressed ? (byte)1 : (byte)0
        };

        int emitted = 0;
        int active = 0;
        for (int slotIndex = 0; slotIndex < _slots.Length; slotIndex++)
        {
            ref LinuxMtSlotState slot = ref _slots[slotIndex];
            if (!slot.IsActive)
            {
                continue;
            }

            active++;
            if (emitted >= InputFrame.MaxContacts)
            {
                continue;
            }

            frame.SetContact(emitted, CreateContact(slotIndex, in slot));
            emitted++;
        }

        if (active == 0 && TryCreateLegacyContact(out ContactFrame legacyContact))
        {
            frame.SetContact(0, legacyContact);
            emitted = 1;
            active = 1;
        }

        frame.ContactCount = (byte)Math.Min(active, InputFrame.MaxContacts);
        LastOverflowContactCount = Math.Max(0, active - InputFrame.MaxContacts);
        TotalOverflowContactCount += LastOverflowContactCount;
        FinalizeLegacyFrameState();
        FrameSequence++;
        return frame;
    }

    private ContactFrame CreateContact(int slotIndex, in LinuxMtSlotState slot)
    {
        uint id = slot.TrackingId >= 0 ? (uint)slot.TrackingId : (uint)slotIndex;
        byte pressure = (byte)Math.Clamp(slot.PressureRaw, byte.MinValue, byte.MaxValue);
        return new ContactFrame(
            Id: id,
            X: (ushort)Math.Clamp(slot.XRaw, 0, MaxX),
            Y: (ushort)Math.Clamp(slot.YRaw, 0, MaxY),
            Flags: ActiveContactFlags,
            Pressure: pressure,
            Phase: 0,
            HasForceData: false);
    }

    private ushort ComputeScanTime(long timestampTicks)
    {
        long elapsedTicks = Math.Max(0, timestampTicks - _openTimestampTicks);
        long elapsedMilliseconds = (elapsedTicks * 1000L) / Stopwatch.Frequency;
        return unchecked((ushort)elapsedMilliseconds);
    }

    private bool TryCreateLegacyContact(out ContactFrame contact)
    {
        bool isActive =
            _legacyContact.IsActive ||
            _legacyContact.PressureRaw > 0 ||
            _legacyContact.TouchMajorRaw > 0 ||
            _legacyContact.TouchMinorRaw > 0 ||
            _legacyContact.SeenThisFrame;
        if (!isActive)
        {
            contact = default;
            return false;
        }

        byte pressure = (byte)Math.Clamp(_legacyContact.PressureRaw, byte.MinValue, byte.MaxValue);
        contact = new ContactFrame(
            Id: LegacyContactId,
            X: (ushort)Math.Clamp(_legacyContact.XRaw, 0, MaxX),
            Y: (ushort)Math.Clamp(_legacyContact.YRaw, 0, MaxY),
            Flags: ActiveContactFlags,
            Pressure: pressure,
            Phase: 0,
            HasForceData: false);
        return true;
    }

    private void FinalizeLegacyFrameState()
    {
        if (!_legacyContact.SeenThisFrame &&
            !_legacyContact.IsActive &&
            _legacyContact.PressureRaw <= 0 &&
            _legacyContact.TouchMajorRaw <= 0 &&
            _legacyContact.TouchMinorRaw <= 0)
        {
            _legacyContact = default;
            return;
        }

        if (!_legacyContact.IsActive &&
            _legacyContact.PressureRaw <= 0 &&
            _legacyContact.TouchMajorRaw <= 0 &&
            _legacyContact.TouchMinorRaw <= 0)
        {
            _legacyContact = default;
            return;
        }

        _legacyContact.SeenThisFrame = false;
    }

    private void EnsureSlotCapacity(int slot)
    {
        if ((uint)slot < (uint)_slots.Length)
        {
            return;
        }

        int newLength = _slots.Length;
        while (newLength <= slot)
        {
            newLength *= 2;
        }

        Array.Resize(ref _slots, newLength);
    }

    private struct LinuxMtSlotState
    {
        public int TrackingId;
        public bool IsActive;
        public int XRaw;
        public int YRaw;
        public int PressureRaw;
        public int OrientationRaw;
    }

    private struct LegacyContactState
    {
        public bool IsActive;
        public bool SeenThisFrame;
        public int XRaw;
        public int YRaw;
        public int PressureRaw;
        public int TouchMajorRaw;
        public int TouchMinorRaw;
    }
}
