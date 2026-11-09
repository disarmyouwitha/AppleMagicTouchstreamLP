using System.Buffers.Binary;
using System.IO;

namespace AppleMagicTouchstream;

internal static class AppleBluetoothDecoderTests
{
    private static void Check(bool pass,string message)
    { if (!pass) throw new InvalidOperationException(message); }

    public static void Run()
    {
        var assembly=typeof(AppleBluetoothDecoderTests).Assembly;
        using var source=assembly.GetManifestResourceStream("AppleMagicTouchstream.AppleBluetoothPacked.atpcap")!;
        string path=Path.Combine(Path.GetTempPath(),"amt-bt-decoder-"+Guid.NewGuid().ToString("N")+".atpcap");
        try
        {
            using (var file=File.Create(path)) source.CopyTo(file);
            // Historical profile metadata deliberately says Legacy. Re-run live
            // Auto against the original bytes and verify every field independently.
            using var reader=new InputCaptureReader(path);
            var session=new TrackpadDecoderSession();
            var overrides=new Dictionary<string,TrackpadDecoderProfile>();
            int frames=0,contacts=0; ushort minY=ushort.MaxValue,maxY=0;
            while (reader.TryReadNext(out var record))
            {
                var payload=record.Payload.Span;
                var info=new RawInputDeviceInfo(record.VendorId,record.ProductId,record.UsagePage,record.Usage);
                Check(info.VendorId==0x004c && info.UsagePage==0x0d && info.Usage==5 && payload.Length==50,
                    "Bluetooth regression fixture identity changed");
                var device=new RawInputDeviceSnapshot("recorded-bluetooth-col02",info,new(1,record.DeviceHash));
                Check(session.TryDecode(1,in device,payload,record.ArrivalQpcTicks,overrides,out var profile,out var decoded)
                    && profile==TrackpadDecoderProfile.Official && decoded.UsesApplePackedFields,
                    $"Bluetooth frame {frames} selected old PTP fields");
                Check(decoded.Frame.ContactCount==payload[48],"Bluetooth contact count changed");
                for (int i=0;i<payload[48];i++)
                {
                    int offset=1+i*9;
                    ushort rawX=BinaryPrimitives.ReadUInt16LittleEndian(payload.Slice(offset+2,2));
                    ushort rawY=BinaryPrimitives.ReadUInt16LittleEndian(payload.Slice(offset+4,2));
                    var contact=decoded.Frame.GetContact(i);
                    ushort expectedX=(ushort)Math.Clamp((int)Math.Floor(rawX*7612.0/14720+0.5),0,7612);
                    ushort expectedY=(ushort)Math.Clamp((int)Math.Floor(rawY*5065.0/10240+0.5),0,5065);
                    Check(contact.Id==payload[offset] && contact.X==expectedX && contact.Y==expectedY
                        && contact.Pressure8==payload[offset+6] && contact.Phase8==payload[offset+7]
                        && contact.Flags==payload[offset+8] && contact.HasForceData,
                        $"Bluetooth frame {frames} contact {i} has incorrect coordinates, identity or force");
                    minY=Math.Min(minY,contact.Y); maxY=Math.Max(maxY,contact.Y); contacts++;
                }
                frames++;
            }
            Check(frames==338 && contacts>500 && maxY-minY>2000,"Bluetooth capture lost vertical motion or contacts");
            // Once acquired, an out-of-normalization-range move must not cause
            // packed fields to be reinterpreted as native PTP within Official.
            byte[] move=new byte[50]; move[0]=5; move[1]=11; move[9]=3; move[48]=1;
            BinaryPrimitives.WriteUInt16LittleEndian(move.AsSpan(3),17000);
            BinaryPrimitives.WriteUInt16LittleEndian(move.AsSpan(5),6000);
            var nativeInfo=new RawInputDeviceInfo(0x004c,0x0324,0x0d,5);
            var sameDevice=new RawInputDeviceSnapshot("recorded-bluetooth-col02",nativeInfo,new(1,1133575511));
            Check(session.TryDecode(1,in sameDevice,move,1,overrides,out _,out var moved)
                && moved.UsesApplePackedFields && moved.Frame.Contact0.Id==11 && moved.Frame.Contact0.X==7612,
                "Bluetooth move changed the locked packed-field layout");
            byte[] empty=new byte[50]; empty[0]=5;
            Check(session.TryDecode(1,in sameDevice,empty,2,overrides,out _,out var lifted)
                && lifted.UsesApplePackedFields && lifted.Frame.ContactCount==0,"Bluetooth lift lost its layout");
            session.Reset(); overrides[sameDevice.DeviceName]=TrackpadDecoderProfile.Official;
            move[3]=0; move[4]=20;
            Check(session.TryDecode(1,in sameDevice,move,3,overrides,out _,out var forced)
                && forced.UsesApplePackedFields && forced.Frame.Contact0.Id==11,"explicit Official ignored Bluetooth packing");
            Console.WriteLine($"Bluetooth packed replay: {frames} frames, {contacts} contacts, Y={minY}..{maxY}.");
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
