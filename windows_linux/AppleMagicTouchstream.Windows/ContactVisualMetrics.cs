namespace AppleMagicTouchstream;

internal static class ContactVisualMetrics
{
    internal static string FingerName(byte finger) => finger switch
    {
        1=>"Thumb",2=>"Index",3=>"Middle",4=>"Ring",5=>"Pinky",6=>"Palm",_=>"Unknown"
    };

    // Upstream v2.2: raw touch axes << 2 are logical X-axis units.
    // Orientation 4 means the major axis points up; decreasing values turn
    // clockwise. This describes the ellipse, not a calibrated finger heading.
    internal static (double MajorMm,double MinorMm,double RotationDegrees) Shape(ContactTelemetry telemetry)
        => (telemetry.TouchMajor*4*160.0/RuntimeConfigurationFactory.DefaultMaxX,
            telemetry.TouchMinor*4*160.0/RuntimeConfigurationFactory.DefaultMaxX,
            (4-(telemetry.Orientation & 7))*22.5);

    internal static (double X,double Y,double Speed) Velocity(TouchContact contact,ushort maxX,ushort maxY,
        double widthMm,double heightMm)
    {
        if(!contact.HasVelocity || maxX==0 || maxY==0) return (0,0,0);
        double x=contact.VelocityX*widthMm/maxX,y=contact.VelocityY*heightMm/maxY;
        if(!double.IsFinite(x) || !double.IsFinite(y)) return (0,0,0);
        return (x,y,Math.Sqrt(x*x+y*y));
    }

    internal static System.Windows.Rect PlaceLabel(System.Windows.Rect pad,System.Windows.Point anchor,
        System.Windows.Size size,ReadOnlySpan<System.Windows.Rect> labels,ReadOnlySpan<System.Windows.Rect> markers)
    {
        double left=pad.Left+4,top=pad.Top+4;
        double right=Math.Max(left,pad.Right-size.Width-4),bottom=Math.Max(top,pad.Bottom-size.Height-4);
        System.Windows.Rect best=default; double bestScore=double.PositiveInfinity;
        // Bounded UI-only search. Prefer nearby positions without covering
        // another label or any contact, including tightly clustered fingers.
        for(double y=top;y<=bottom+16;y+=16)
            for(double x=left;x<=right+16;x+=16)
            {
                var candidate=new System.Windows.Rect(Math.Min(x,right),Math.Min(y,bottom),size.Width,size.Height);
                double dx=candidate.Left+size.Width/2-anchor.X,dy=candidate.Top+size.Height/2-anchor.Y;
                double score=dx*dx+dy*dy;
                foreach(var label in labels) { var hit=System.Windows.Rect.Intersect(candidate,label); if(!hit.IsEmpty) score+=hit.Width*hit.Height*1e6; }
                foreach(var marker in markers) { var hit=System.Windows.Rect.Intersect(candidate,marker); if(!hit.IsEmpty) score+=hit.Width*hit.Height*1e6; }
                if(score<bestScore) { best=candidate; bestScore=score; }
            }
        return best;
    }
}
