using System.Buffers.Binary;

namespace AppleMagicTouchstream;

internal static class DecoderSessionTests
{
    private static void Check(bool pass,string message) { if (!pass) throw new InvalidOperationException(message); }
    private static byte[] Official(int x=3500,byte lifecycle=3)
    {
        var bytes=new byte[PtpReport.ExpectedSize]; bytes[0]=5; bytes[1]=4;
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(3),(ushort)x);
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(5),2000);
        bytes[7]=24; bytes[9]=lifecycle; bytes[48]=1; return bytes;
    }
    private static byte[] Legacy()
    {
        var bytes=new byte[PtpReport.ExpectedSize]; bytes[0]=5; bytes[1]=3;
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(2),12);
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(6),1600);
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(8),1200);
        bytes[48]=1; return bytes;
    }
    public static void Run()
    {
        var nativeInfo=typeof(RawInputInterop).GetNestedType("RID_DEVICE_INFO",System.Reflection.BindingFlags.NonPublic)!;
        Check(System.Runtime.InteropServices.Marshal.SizeOf(nativeInfo)==32
            && System.Runtime.InteropServices.Marshal.OffsetOf(nativeInfo,"hid").ToInt32()==8,
            "RID_DEVICE_INFO no longer matches the Windows union ABI; device usage discovery would fail");
        var session=new TrackpadDecoderSession();
        var info=new RawInputDeviceInfo(0x05ac,RawInputInterop.ProductIdMt2UsbC,0,0);
        var device=new RawInputDeviceSnapshot("pad-a",info,new(0,1));
        var overrides=new Dictionary<string,TrackpadDecoderProfile>(StringComparer.OrdinalIgnoreCase);
        bool decode(IntPtr handle,byte[] bytes,out TrackpadDecodeResult result)
            =>session.TryDecode(handle,in device,bytes,100,overrides,out _,out result);
        var empty=new byte[50]; empty[0]=5;
        Check(decode(1,empty,out _),"initial all-up failed");
        Check(decode(1,Legacy(),out var result) && result.Profile==TrackpadDecoderProfile.Legacy,
            "empty startup packet locked the default official decoder");
        session.Reset();
        Check(decode(1,Official(lifecycle:1),out _),"startup hover failed");
        Check(decode(1,Legacy(),out result) && result.Profile==TrackpadDecoderProfile.Legacy,
            "hover-only startup packet locked a format");
        session.Reset();
        Check(decode(1,Official(),out result) && result.Profile==TrackpadDecoderProfile.Official,"official acquisition failed");
        // Deliberately ambiguous packet: stateless Auto would choose Legacy.
        // The selected official layout must still own this connection.
        var outside=Official(17000);
        outside[1]=6;
        Check(TrackpadDecoderProfileResolver.ResolveAuto(outside,in info)==TrackpadDecoderProfile.Legacy,"test packet does not exercise a competing layout");
        Check(decode(1,outside,out result) && result.Profile==TrackpadDecoderProfile.Official && result.Frame.GetContact(0).Id==6,
            "movement changed the locked decoder/identity");
        Check(decode(1,empty,out _),"locked all-up failed");
        Check(decode(1,outside,out result) && result.Profile==TrackpadDecoderProfile.Official,"all-up unlocked the device format");
        var corrupt=Official(); corrupt[48]=6;
        Check(!decode(1,corrupt,out _),"corrupt locked packet was accepted through a fallback");
        Check(decode(1,Official(),out result) && result.Profile==TrackpadDecoderProfile.Official,"corrupt packet discarded the format lock");
        Check(!decode(1,new byte[49],out _),"locked report size changed");
        Check(decode(2,Legacy(),out result) && result.Profile==TrackpadDecoderProfile.Legacy,"another device inherited the format lock");
        session.Remove(1);
        Check(decode(1,Legacy(),out result) && result.Profile==TrackpadDecoderProfile.Legacy,"reconnect did not relearn the format");
        device=device with { DeviceName="pad-b" };
        Check(decode(1,Official(),out result) && result.Profile==TrackpadDecoderProfile.Official,"reused handle retained the previous device's decoder");
        overrides[device.DeviceName]=TrackpadDecoderProfile.Legacy;
        Check(decode(1,Legacy(),out result) && result.Profile==TrackpadDecoderProfile.Legacy,"explicit override did not invalidate learned Auto");
        overrides.Clear();
        Check(decode(1,Official(),out result) && result.Profile==TrackpadDecoderProfile.Official,"return to Auto did not reacquire");
        session.Reset();
        Check(decode(1,Legacy(),out result) && result.Profile==TrackpadDecoderProfile.Legacy,"selection refresh retained the old lock");
        RunExtendedPtpTests();
    }

    private static void RunExtendedPtpTests()
    {
        // Upstream PTP_REPORT_MT2: five packed 21-byte contacts, then the
        // scan time, contact count, mechanical force and button at the tail.
        byte[] packet=new byte[112]; packet[0]=5; packet[108]=5; packet[111]=1;
        BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(106),1234);
        for (int i=0;i<5;i++)
        {
            int offset=1+i*21; packet[offset]=3;
            BinaryPrimitives.WriteUInt32LittleEndian(packet.AsSpan(offset+1),(uint)(i+10));
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+5),(ushort)(1000+i*1500));
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+7),(ushort)(500+i*1000));
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+9),400);
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+11),500);
            BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(offset+13),(ushort)(100+i));
            packet[offset+15]=40; packet[offset+16]=60; packet[offset+17]=30;
            packet[offset+18]=4; packet[offset+19]=2; packet[offset+20]=4;
        }
        var info=new RawInputDeviceInfo(0x05ac,RawInputInterop.ProductIdMt2UsbC,0x0d,5);
        var device=new RawInputDeviceSnapshot("extended-pad",info,new(0,2));
        var session=new TrackpadDecoderSession();
        var overrides=new Dictionary<string,TrackpadDecoderProfile>();
        bool decode(byte[] bytes,out TrackpadDecodeResult result)
            => session.TryDecode(3,in device,bytes,100,overrides,out _,out result);
        Check(decode(packet,out var decoded) && decoded.Kind==TrackpadReportKind.PtpExtended,
            "112-byte PTP report was decoded using the old layout");
        Check(decoded.Frame.ScanTime==1234 && decoded.Frame.ContactCount==5 && decoded.Frame.IsButtonPressed,
            "extended PTP tail offsets are wrong");
        for (int i=0;i<5;i++)
        {
            var contact=decoded.Frame.GetContact(i);
            Check(contact.Id==i+10 && contact.X==1000+i*1500 && contact.Y==500+i*1000
                && contact.TipSwitch && contact.Confidence && contact.HasForceData
                && contact.Pressure8==100+i && contact.Phase8==0
                && contact.Telemetry==new ContactTelemetry(400,500,40,60,30,4,2,4),
                "extended PTP contact fields/stride are wrong");
        }
        packet[108]=1;
        BinaryPrimitives.WriteUInt16LittleEndian(packet.AsSpan(6),7400);
        Check(decode(packet,out decoded) && decoded.Frame.Contact0.X==7400 && decoded.Frame.Contact0.Id==10,
            "extended movement changed identity or coordinates");
        packet[108]=0; packet[111]=0;
        Check(decode(packet,out decoded) && decoded.Frame.ContactCount==0 && !decoded.Frame.IsButtonPressed,
            "extended all-up failed");
        packet[108]=6;
        Check(!decode(packet,out _),"invalid extended count fell back to legacy parsing");
        session.Reset();
        Check(!decode(packet,out _),"invalid initial extended packet fell back to legacy parsing");
        packet[108]=1;
        Check(decode(packet,out _),"extended stream could not reacquire");
        Check(!decode(packet[..111],out _),"locked extended report accepted a truncated layout");
        packet[0]=6;
        Check(!decode(packet,out _),"extended stream accepted a different report ID");
        session.Reset();
        Check(decode(Legacy(),out decoded) && decoded.Kind==TrackpadReportKind.PtpNative,
            "old PTP layout stopped working");
    }
}
