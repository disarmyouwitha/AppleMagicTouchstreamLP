using System.Diagnostics;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;

namespace GlassToKey;

// Presentation only: no runtime, device handles or output adapters.
internal sealed class GestureDemonstration : FrameworkElement
{
    private readonly int _count;
    private readonly bool _shape, _corners;
    private readonly Stopwatch _elapsed = new();
    private readonly DispatcherTimer _timer = new() { Interval=TimeSpan.FromMilliseconds(33) };
    private static readonly Brush[] Palette = [Brushes.DarkOrange,Brushes.DodgerBlue,Brushes.MediumSeaGreen,Brushes.MediumPurple,Brushes.DeepPink];
    public GestureDemonstration(int count,bool shape,bool corners)
    {
        _count=count; _shape=shape; _corners=corners;
        Height=125; MaxWidth=210; HorizontalAlignment=HorizontalAlignment.Center; Margin=new(0,12,0,10);
        System.Windows.Automation.AutomationProperties.SetName(this,$"{count}-finger {(corners ? "corner hold" : shape ? "pinch and spread" : "touch and movement")} demonstration");
        _timer.Tick += (_,_)=>InvalidateVisual();
        Loaded += (_,_)=>UpdatePlayback(); Unloaded += (_,_)=> { _timer.Stop(); _elapsed.Stop(); };
        IsVisibleChanged += (_,_)=>UpdatePlayback();
    }
    private void UpdatePlayback()
    {
        if (IsLoaded && IsVisible && SystemParameters.ClientAreaAnimation) { _elapsed.Restart(); _timer.Start(); }
        else { _timer.Stop(); _elapsed.Stop(); }
        InvalidateVisual();
    }
    protected override Size MeasureOverride(Size availableSize) => new(Math.Min(210,availableSize.Width),125);
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        double width=Math.Max(80,ActualWidth), center=width/2;
        var pad=new Rect(5,5,width-10,110);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(18,24,29)),new Pen(Brushes.SlateGray,1.5),pad,12,12);
        double phase=SystemParameters.ClientAreaAnimation && IsLoaded ? (_elapsed.Elapsed.TotalSeconds%2.8)/2.8 : .5;
        double motion=Math.Clamp((phase-.18)/.5,0,1); motion=motion*motion*(3-2*motion);
        double opacity=_corners ? 1 : phase<.15 ? phase/.15 : phase>.8 ? Math.Max(0,(1-phase)/.2) : 1;
        dc.PushOpacity(opacity);
        for (int i=0;i<_count;i++)
        {
            double x,y;
            if (_corners) { x=i<2 ? 23 : width-23; y=i%2==0 ? 25 : 95; }
            else
            {
                double spacing=Math.Min(24,(width-50)/Math.Max(1,_count-1));
                double offset=(i-(_count-1)/2.0)*spacing;
                x=center+offset*(_shape ? .65+motion*.8 : 1)+(_shape ? 0 : -14+28*motion);
                y=60+(_shape && i==0 ? 12 : 0);
            }
            int color=_shape || _count==5 ? i : Math.Min(4,i+1);
            if (_shape && phase>.18 && phase<.8)
                dc.DrawLine(new Pen(Palette[color],1),new Point(center+(i-(_count-1)/2.0)*18,60),new Point(x,y));
            dc.DrawEllipse(Palette[color],null,new(x,y),5.5,5.5);
            if (_corners) dc.DrawEllipse(null,new Pen(Palette[color],1),new(x,y),8+motion*3,8+motion*3);
        }
        dc.Pop();
    }
}
