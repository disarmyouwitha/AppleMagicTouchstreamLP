namespace AppleMagicTouchstream;

internal static class WindowsForceSettings
{
    internal const int PressureMaximum=255;
    internal static double StenoThreshold(double value)=>double.IsFinite(value) ? Math.Clamp(value,1,PressureMaximum):130;
    internal static string SupportText(int? maximum,double threshold)=>maximum switch
    {
        0=>"This decoder does not report pressure. Force Instead of Hold is unavailable; timed Hold is used.",
        255=>"Reported pressure: 0–255. Threshold 0 keeps timed Hold; a positive threshold waits for pressure."
            +(threshold>255 ? " The saved threshold exceeds 255 and cannot trigger with this decoder.":""),
        >0=>"This decoder uses Apple's pressure/phase force scale. 0 keeps timed Hold; a positive threshold waits for force.",
        _=>"Touch the selected trackpad to check pressure support. 0 keeps timed Hold."
    };
}
