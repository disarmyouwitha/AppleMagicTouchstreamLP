using System.Text.Json;
using System.Text.Json.Serialization;

namespace AppleMagicTouchstream;

// Numerical port of Mac Runtime/PointerAcceleration.swift. This profile is data;
// importing it never reads or changes Windows mouse/driver settings.
public sealed record ApplePointerCurve
{
    [JsonPropertyName("index")] public double Index { get; init; }
    [JsonPropertyName("HIDAccelGainLinear")] public double Linear { get; init; }
    [JsonPropertyName("HIDAccelGainParabolic")] public double Parabolic { get; init; }
    [JsonPropertyName("HIDAccelGainCubic")] public double Cubic { get; init; }
    [JsonPropertyName("HIDAccelGainQuartic")] public double Quartic { get; init; }
    [JsonPropertyName("HIDAccelTangentSpeedLinear")] public double TangentLinear { get; init; }
    [JsonPropertyName("HIDAccelTangentSpeedParabolicRoot")] public double TangentRoot { get; init; }
    internal double Polynomial(double x) => Linear*x+Math.Pow(Parabolic*x,2)+Math.Pow(Cubic*x,3)+Math.Pow(Quartic*x,4);
    internal double Derivative(double x) => Linear+2*x*Parabolic*Parabolic+3*x*x*Math.Pow(Cubic,3)+4*x*x*x*Math.Pow(Quartic,4);
}

public sealed record ApplePointerProfile
{
    [JsonPropertyName("device_id")] public string DeviceId { get; init; } = "";
    [JsonPropertyName("resolution")] public double Resolution { get; init; }
    [JsonPropertyName("algorithm_rate")] public double AlgorithmRate { get; init; } = 67;
    [JsonPropertyName("acceleration")] public double Acceleration { get; init; }
    [JsonPropertyName("report_rate")] public double ReportRate { get; init; }
    [JsonPropertyName("fixed_multiplier")] public double FixedMultiplier { get; init; } = 1;
    [JsonPropertyName("curves")] public ApplePointerCurve[] Curves { get; init; } = [];
    // Mac ApplePointerAccelerationTests.installedExample(): observed coefficients,
    // offered as a reference preset, not the current Windows/Mac user's settings.
    public static ApplePointerProfile Reference => new() { DeviceId = "Mac reference", Resolution = 400,
        FixedMultiplier = 48545.0/65536, Acceleration = 3,
        Curves = [new() { Index = 3, Linear = 1, Parabolic = 123208.0/65536, Cubic = 23593.0/65536, TangentLinear = 7, TangentRoot = 12 }] };
    public ApplePointerProfile Copy() => this with { Curves = Curves?.ToArray() ?? [] };
    public static ApplePointerProfile[] ReadSnapshot(string json)
    {
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("schema", out var schema) || schema.GetString() != "gesturepad.pointer-settings.v1")
            throw new ArgumentException("Expected a gesturepad.pointer-settings.v1 snapshot.");
        var devices = document.RootElement.GetProperty("devices").Deserialize<ApplePointerProfile[]>() ?? [];
        if (devices.Length == 0) throw new ArgumentException("No pointer profiles in this snapshot.");
        foreach (var profile in devices) _ = new ApplePointerAccelerator(profile);
        return devices;
    }
}

public sealed class ApplePointerAccelerator
{
    private readonly ApplePointerProfile _profile;
    private readonly ApplePointerCurve _curve;
    private readonly double _t0 = double.PositiveInfinity, _t1 = double.PositiveInfinity, _m0, _b0, _m1, _b1;
    private double? _lastTime;
    public ApplePointerAccelerator(ApplePointerProfile profile)
    {
        _profile = profile.Copy();
        if (!double.IsFinite(profile.Resolution) || profile.Resolution <= 0 || !double.IsFinite(profile.AlgorithmRate) || profile.AlgorithmRate <= 0
            || !double.IsFinite(profile.Acceleration) || !double.IsFinite(profile.ReportRate) || profile.ReportRate < 0
            || !double.IsFinite(profile.FixedMultiplier) || profile.FixedMultiplier <= 0 || profile.Curves is not { Length: > 0 and <= 256 })
            throw new ArgumentException("Invalid Apple pointer profile.");
        double previous = double.NegativeInfinity;
        foreach (var c in profile.Curves)
        {
            if (c == null) throw new ArgumentException("Missing Apple curve.");
            double[] values = [c.Index,c.Linear,c.Parabolic,c.Cubic,c.Quartic,c.TangentLinear,c.TangentRoot];
            if (values.Any(v => !double.IsFinite(v) || v < 0) || c.Index <= previous || c.Linear+c.Parabolic+c.Cubic+c.Quartic <= 0
                || (c.TangentLinear != 0 && c.TangentRoot != 0 && c.TangentRoot < c.TangentLinear)) throw new ArgumentException("Invalid Apple curve coefficients/order.");
            previous = c.Index;
        }
        int lo = 0;
        for (int i = 0; i < profile.Curves.Length; i++) if (profile.Curves[i].Index <= profile.Acceleration) lo = i;
        var a = profile.Curves[lo]; _curve = a;
        if (lo+1 < profile.Curves.Length && profile.Acceleration > a.Index)
        {
            var b = profile.Curves[lo+1]; double ratio = (profile.Acceleration-a.Index)/(b.Index-a.Index);
            double lerp(double x,double y) => x+ratio*(y-x);
            _curve = new() { Index = profile.Acceleration, Linear = lerp(a.Linear,b.Linear), Parabolic = lerp(a.Parabolic,b.Parabolic),
                Cubic = lerp(a.Cubic,b.Cubic), Quartic = lerp(a.Quartic,b.Quartic), TangentLinear = lerp(a.TangentLinear,b.TangentLinear), TangentRoot = lerp(a.TangentRoot,b.TangentRoot) };
        }
        if (_curve.TangentLinear != 0)
        {
            _t0 = _curve.TangentLinear; _m0 = _curve.Derivative(_t0); _b0 = _curve.Polynomial(_t0)-_m0*_t0;
            if (_curve.TangentRoot != 0) { _t1 = _curve.TangentRoot; double y = _m0*_t1+_b0; _m1 = 2*y*_m0; _b1 = y*y-_m1*_t1; }
        }
        else if (_curve.TangentRoot != 0) { _t0 = _curve.TangentRoot; double y = _curve.Polynomial(_t0); _m1 = _curve.Derivative(_t0); _b1 = y*y-_m1*_t0; }
    }
    public void Reset() => _lastTime = null;
    public double AcceleratedVelocity(double velocity)
    {
        double x = velocity/(_profile.Resolution/_profile.AlgorithmRate);
        double result = x <= _t0 ? _curve.Polynomial(x) : x <= _t1 && _t0 == _curve.TangentLinear ? _m0*x+_b0 : Math.Sqrt(Math.Max(0,_m1*x+_b1));
        return result*96/67;
    }
    public (double X,double Y)? Counts(double time,double x,double y)
    {
        if (!double.IsFinite(time) || !double.IsFinite(x) || !double.IsFinite(y) || (_lastTime.HasValue && time <= _lastTime.Value)) { Reset(); return null; }
        double? dt = _lastTime.HasValue ? time-_lastTime.Value : null; _lastTime = time;
        if (_profile.Acceleration < 0) return (x,y);
        double rateGain = _profile.ReportRate > 0 && dt.HasValue ? (1/_profile.ReportRate)/Math.Max(1/_profile.ReportRate,dt.Value) : 1;
        double velocity = Math.Max(1.0/65536, Math.Floor(Math.Sqrt(x*x+y*y))*(_profile.FixedMultiplier == 1 ? rateGain : _profile.FixedMultiplier));
        double gain = AcceleratedVelocity(velocity)/velocity;
        return double.IsFinite(x*gain) && double.IsFinite(y*gain) ? (x*gain,y*gain) : null;
    }
    public (double X,double Y)? Millimetres(double time,double x,double y,double sensitivity)
    {
        double scale = _profile.Resolution/25.4*Math.Clamp(sensitivity,.25,2);
        var result = Counts(time,x*scale,y*scale);
        // A large finite accelerated step is legitimate motion, not lost contact
        // continuity. Ownership is independent of its screen-space magnitude.
        if (result is not {} delta) { Reset(); return null; }
        return delta;
    }
}

internal static class PointerMotionLimits
{
    // Bound pathological imported gains without dropping frames or releasing a
    // valid gesture. This is an output limit, not a recognition threshold.
    internal const double MaximumPixelsPerFrame = 4096;
    internal static (double X,double Y) Constrain(double x,double y)
    {
        if (!double.IsFinite(x) || !double.IsFinite(y)) throw new ArgumentException("Non-finite pointer motion.");
        double largest = Math.Max(Math.Abs(x),Math.Abs(y));
        if (largest <= MaximumPixelsPerFrame) return (x,y);
        double scale = MaximumPixelsPerFrame/largest;
        return (Math.Clamp(x*scale,-MaximumPixelsPerFrame,MaximumPixelsPerFrame),
            Math.Clamp(y*scale,-MaximumPixelsPerFrame,MaximumPixelsPerFrame));
    }
}
