using System.Windows;
using System.Windows.Media;
namespace GlassToKey;

// Two physical pad diagrams, matching the coordinated corner masks.
internal sealed class CoordinatedGestureDemonstration(CoordinatedHandChord chord) : FrameworkElement
{
    protected override Size MeasureOverride(Size availableSize)=>new(170,120);
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        for(int side=0;side<2;side++)
        {
            var pad=new Rect(3+side*85,26,78,65); dc.DrawRoundedRectangle(null,new Pen(Brushes.SlateGray,1.5),pad,8,8);
            if(chord is CoordinatedHandChord.ThreeFingers or CoordinatedHandChord.FourFingers)
            {
                int count=chord==CoordinatedHandChord.ThreeFingers ? 3 : 4;
                for(int i=0;i<count;i++) dc.DrawEllipse(i==0 ? Brushes.DodgerBlue : i==1 ? Brushes.MediumSeaGreen : i==2 ? Brushes.MediumPurple : Brushes.DeepPink,null,new(pad.Left+16+i*15,pad.Top+32),4,4);
            }
            else
            {
                bool outer=chord is CoordinatedHandChord.OuterCorners or CoordinatedHandChord.TopOuter or CoordinatedHandChord.BottomOuter;
                double x=(side==0)==outer ? pad.Left+12 : pad.Right-12;
                if(chord is CoordinatedHandChord.OuterCorners or CoordinatedHandChord.InnerCorners)
                { dc.DrawEllipse(Brushes.DodgerBlue,null,new(x,pad.Top+12),4,4); dc.DrawEllipse(Brushes.MediumSeaGreen,null,new(x,pad.Bottom-12),4,4); }
                else dc.DrawEllipse(Brushes.DodgerBlue,null,new(x,chord is CoordinatedHandChord.TopOuter or CoordinatedHandChord.TopInner ? pad.Top+12 : pad.Bottom-12),4,4);
            }
        }
    }
}
