using System.Buffers.Binary;

namespace AppleMagicTouchstream;

// MagicTrackpad2ForWindows v2.2 PTP_REPORT_MT2, USB and Bluetooth.
// Layout: upstream PR #61, AmtPtpDeviceUsbUm/include/Hid.h.
internal static class ExtendedPtpReportDecoder
{
    internal const int ReportSize = 112;
    private const int ContactSize = 21;

    internal static bool IsExtendedReport(ReadOnlySpan<byte> payload,in RawInputDeviceInfo info)
        => payload.Length == ReportSize
            && info.UsagePage == RawInputInterop.UsagePageDigitizer
            && info.Usage == RawInputInterop.UsageTouchpad;

    internal static bool TryDecode(ReadOnlySpan<byte> payload,in RawInputDeviceInfo info,long timestamp,
        out TrackpadDecodeResult result)
    {
        result=default;
        if (!IsExtendedReport(payload,in info) || payload[0]!=RawInputInterop.ReportIdMultitouch
            || payload[108]>InputFrame.MaxContacts || payload[111]>1) return false;
        InputFrame frame=new()
        {
            ArrivalQpcTicks=timestamp, ReportId=payload[0],
            ScanTime=BinaryPrimitives.ReadUInt16LittleEndian(payload.Slice(106,2)),
            ContactCount=payload[108], IsButtonClicked=payload[111]
        };
        for (int i=0;i<frame.ContactCount;i++)
        {
            int offset=1+i*ContactSize;
            byte flags=payload[offset];
            uint id=BinaryPrimitives.ReadUInt32LittleEndian(payload.Slice(offset+1,4));
            ushort x=BinaryPrimitives.ReadUInt16LittleEndian(payload.Slice(offset+5,2));
            ushort y=BinaryPrimitives.ReadUInt16LittleEndian(payload.Slice(offset+7,2));
            ushort pressure=BinaryPrimitives.ReadUInt16LittleEndian(payload.Slice(offset+13,2));
            if ((flags & ~3)!=0 || x>RuntimeConfigurationFactory.DefaultMaxX
                || y>RuntimeConfigurationFactory.DefaultMaxY || pressure>255) return false;
            for (int previous=0;previous<i;previous++)
                if (frame.GetContact(previous).Id==id) return false;
            // Actual reported pressure; vendor State is not Apple's phase field.
            frame.SetContact(i,new ContactFrame(id,x,y,flags,(byte)pressure,Phase:0,HasForceData:true));
        }
        result=new(TrackpadReportKind.PtpExtended,0,payload[0],TrackpadDecoderProfile.Legacy,frame);
        return true;
    }
}
