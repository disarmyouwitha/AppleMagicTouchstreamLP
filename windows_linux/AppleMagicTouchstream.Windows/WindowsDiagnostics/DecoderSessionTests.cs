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
    }
}
