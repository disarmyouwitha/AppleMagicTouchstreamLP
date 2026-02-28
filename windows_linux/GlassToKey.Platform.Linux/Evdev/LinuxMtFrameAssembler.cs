using System.Diagnostics;
using GlassToKey;

namespace GlassToKey.Platform.Linux.Evdev;

public sealed class LinuxMtFrameAssembler
{
    public const byte SyntheticReportId = 0xEE;
    private const byte ActiveContactFlags = 0x03;

    private readonly LinuxMtSlotState[] _slots;
    private readonly long _openTimestampTicks;
    private int _currentSlot;
    private bool _buttonPressed;

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
        FrameSequence = 0;
        LastOverflowContactCount = 0;
        TotalOverflowContactCount = 0;
    }

    public void SelectSlot(int slot)
    {
        if ((uint)slot >= (uint)_slots.Length)
        {
            throw new ArgumentOutOfRangeException(nameof(slot));
        }

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

        frame.ContactCount = (byte)Math.Min(active, InputFrame.MaxContacts);
        LastOverflowContactCount = Math.Max(0, active - InputFrame.MaxContacts);
        TotalOverflowContactCount += LastOverflowContactCount;
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

    private struct LinuxMtSlotState
    {
        public int TrackingId;
        public bool IsActive;
        public int XRaw;
        public int YRaw;
        public int PressureRaw;
        public int OrientationRaw;
    }
}
