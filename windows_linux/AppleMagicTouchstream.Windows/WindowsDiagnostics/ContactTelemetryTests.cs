using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AppleMagicTouchstream;

internal static class ContactTelemetryTests
{
    private static void Check(bool condition,string message) { if(!condition) throw new InvalidOperationException(message); }
    internal static void Run()
    {
        var telemetry=new ContactTelemetry(700,600,42,120,50,3,2,4);
        var state=new TouchState(); state.ConfigurePressureHint(true);
        long start=Stopwatch.GetTimestamp(),step=Stopwatch.Frequency/100;
        InputFrame frame=new() { ArrivalQpcTicks=start,ContactCount=1,
            Contact0=new(7,1000,2000,3,148,Telemetry:telemetry) };
        state.Update(frame);
        Span<TouchContact> contacts=stackalloc TouchContact[5];
        Check(state.Snapshot(contacts,out _,out _,out var pressure)==1
            && pressure==PressureCapability.Supported && contacts[0].Pressure==148
            && contacts[0].Telemetry==telemetry && !contacts[0].HasVelocity,
            "reported shape/pressure was lost or hidden by the Bluetooth pressure hint");
        frame.ArrivalQpcTicks+=step; frame.Contact0=frame.Contact0 with { X=1100,Y=2200 };
        state.Update(frame); state.SnapshotContacts(contacts);
        Check(contacts[0].HasVelocity && Math.Abs(contacts[0].VelocityX-100*Stopwatch.Frequency/(double)step)<.001
            && Math.Abs(contacts[0].VelocityY-200*Stopwatch.Frequency/(double)step)<.001,
            "velocity was not derived from the same contact ID and source timestamps");
        var velocity=ContactVisualMetrics.Velocity(contacts[0],7612,5065,160,114.9);
        Check(velocity.X>200 && velocity.Y>450 && velocity.Speed>490,"velocity units were not converted to mm/s");
        frame.ArrivalQpcTicks+=step; frame.Contact0=frame.Contact0 with { Id=9 };
        state.Update(frame); state.SnapshotContacts(contacts);
        Check(!contacts[0].HasVelocity,"new ID inherited another finger's velocity");
        frame.ContactCount=0; frame.ArrivalQpcTicks+=step; state.Update(frame);
        frame.ContactCount=1; frame.ArrivalQpcTicks+=step; state.Update(frame); state.SnapshotContacts(contacts);
        Check(!contacts[0].HasVelocity,"reused ID connected a velocity across lift");
        frame.ArrivalQpcTicks+=Stopwatch.Frequency; state.Update(frame); state.SnapshotContacts(contacts);
        Check(!contacts[0].HasVelocity,"stale stream retained velocity");
        frame.ArrivalQpcTicks-=step; state.Update(frame); state.SnapshotContacts(contacts);
        Check(!contacts[0].HasVelocity,"replay rewind retained velocity");
        state.Clear(); state.Update(frame); state.SnapshotContacts(contacts);
        Check(!contacts[0].HasVelocity,"device reset retained velocity");
        state.Clear(); frame.Contact0=ContactFrame.FromPtpContact(new PtpContact { Flags=3,ContactId=2,X=3000,Y=1000 });
        state.Update(frame); state.SnapshotContacts(contacts);
        Check(contacts[0].Telemetry is null && !contacts[0].HasForceData
            && ContactVisualMetrics.FingerName(0)=="Unknown"
            && ((SolidColorBrush)TouchView.ContactBrush(0)).Color==Colors.Black,
            "legacy contact ID was treated as anatomical identity or pressure");
        var shape=ContactVisualMetrics.Shape(telemetry);
        Check(Math.Abs(shape.MajorMm-480*160.0/7612)<1e-9
            && Math.Abs(shape.MinorMm-200*160.0/7612)<1e-9 && shape.RotationDegrees==22.5
            && ContactVisualMetrics.Shape(telemetry with { Orientation=4 }).RotationDegrees==0
            && ContactVisualMetrics.Shape(telemetry with { Orientation=0 }).RotationDegrees==90,
            "raw contact axes/orientation do not match the driver convention");
        string[] names=["Unknown","Thumb","Index","Middle","Ring","Pinky","Palm"];
        Color[] palette=[Colors.Black,Color.FromRgb(242,115,13),Color.FromRgb(26,115,242),Color.FromRgb(26,179,77),
            Color.FromRgb(166,64,217),Color.FromRgb(242,51,140),Color.FromRgb(128,128,128)];
        for(byte i=0;i<names.Length;i++)
            Check(ContactVisualMetrics.FingerName(i)==names[i] && TouchView.ContactBrush(i).IsFrozen
                && ((SolidColorBrush)TouchView.ContactBrush(i)).Color==palette[i],
                "Mac finger palette/classification is inconsistent");
        Check(ContactVisualMetrics.FingerName(7)=="Unknown" && TouchView.ContactBrush(7)==TouchView.ContactBrush(0),
            "unrecognized native classification invented a finger label");
        Span<Rect> labels=stackalloc Rect[5];
        Span<Rect> markers=stackalloc Rect[1]; markers[0]=new Rect(185,135,30,30);
        var pad=new Rect(0,0,400,300);
        for(int i=0;i<5;i++)
        {
            labels[i]=ContactVisualMetrics.PlaceLabel(pad,new Point(200,150),new Size(140,38),labels[..i],markers);
            Check(pad.Contains(labels[i]) && !labels[i].IntersectsWith(markers[0]),"contact label left the pad or covered a contact");
            for(int p=0;p<i;p++) Check(!labels[p].IntersectsWith(labels[i]),"clustered contacts produced overlapping telemetry labels");
        }
        if(Environment.GetEnvironmentVariable("APPLEMAGICTOUCHSTREAM_CONTACT_PREVIEW_DIR") is {} directory)
        {
            Directory.CreateDirectory(directory);
            foreach(int width in new[] { 1260,800 }) Render(directory,width);
        }
        Console.WriteLine("Contact telemetry passed: native fields, USB/BT pressure, source-timed velocity/reset, physical ellipse axes and anatomical palette. No native input.");
    }

    private static void Render(string directory,int width)
    {
        var grid=new Grid { Background=Brushes.Black };
        grid.ColumnDefinitions.Add(new()); grid.ColumnDefinitions.Add(new());
        for(int side=0;side<2;side++)
        {
            var state=new TouchState();
            var view=new TouchView { State=state,Side=(TrackpadSide)side,RequestedMaxX=7612,RequestedMaxY=5065,PeakLabel="148" };
            Grid.SetColumn(view,side); grid.Children.Add(view);
            var first=new InputFrame { ArrivalQpcTicks=Stopwatch.GetTimestamp()-Stopwatch.Frequency/50,ContactCount=5 };
            for(int i=0;i<5;i++)
                first.SetContact(i,new((uint)i,(ushort)(650+i*1400),(ushort)(1400+(i%2)*1900),3,(byte)(60+i*35),
                    HasForceData:side==0,Telemetry:side==0 ? new ContactTelemetry(600,400,(byte)(30+i*7),(byte)(80+i*15),(byte)(35+i*5),(byte)(i+2),(byte)(i+1),4) : null));
            state.Update(first);
            first.ArrivalQpcTicks+=Stopwatch.Frequency/50;
            for(int i=0;i<5;i++) first.SetContact(i,first.GetContact(i) with { X=(ushort)(first.GetContact(i).X+180) });
            state.Update(first);
        }
        grid.Measure(new Size(width,430)); grid.Arrange(new Rect(0,0,width,430)); grid.UpdateLayout();
        var bitmap=new RenderTargetBitmap(width,430,96,96,PixelFormats.Pbgra32); bitmap.Render(grid);
        var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream=File.Create(Path.Combine(directory,$"contacts-{width}.png")); encoder.Save(stream);
    }
}
