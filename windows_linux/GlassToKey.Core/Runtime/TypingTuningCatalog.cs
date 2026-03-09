using System;
using System.Collections.Generic;

namespace GlassToKey;

public sealed record TypingTuningTextFieldDefinition(
    string Id,
    string Label,
    double DefaultValue,
    double Minimum,
    double Maximum);

public sealed record TypingTuningSliderFieldDefinition(
    string Id,
    string Label,
    int DefaultValue,
    int Minimum,
    int Maximum);

public static class TypingTuningCatalog
{
    public const int ForceMinimum = 0;
    public const int ForceMaximum = ForceNormalizer.Max;
    public const int HapticsAmplitudeMaximum = 70;
    private const uint HapticsStrengthBase = 0x00026C00u;

    public static IReadOnlyList<TypingTuningTextFieldDefinition> TextFields { get; } =
    [
        new TypingTuningTextFieldDefinition("hold_duration_ms", "Hold Duration (ms)", 220.0, 10.0, 2000.0),
        new TypingTuningTextFieldDefinition("typing_grace_ms", "Typing Grace (ms)", 600.0, 0.0, 5000.0),
        new TypingTuningTextFieldDefinition("drag_cancel_mm", "Drag Cancel (mm)", 3.0, 0.0, 50.0),
        new TypingTuningTextFieldDefinition("intent_move_mm", "Intent Move (mm)", 3.0, 0.0, 50.0),
        new TypingTuningTextFieldDefinition("intent_velocity_mm_per_sec", "Intent Velocity (mm/s)", 30.0, 0.0, 1000.0)
    ];

    public static IReadOnlyList<TypingTuningSliderFieldDefinition> SliderFields { get; } =
    [
        new TypingTuningSliderFieldDefinition("force_min", "Force Min", 0, ForceMinimum, ForceMaximum),
        new TypingTuningSliderFieldDefinition("force_cap", "Force Max", 255, ForceMinimum, ForceMaximum)
    ];

    public const string HapticsPlatformNote =
        "Currently only USB trackpads support haptics on Linux.";

    public static double GetTextValue(UserSettings settings, TypingTuningTextFieldDefinition field)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(field);

        return field.Id switch
        {
            "hold_duration_ms" => settings.HoldDurationMs,
            "typing_grace_ms" => settings.TypingGraceMs,
            "drag_cancel_mm" => settings.DragCancelMm,
            "intent_move_mm" => settings.IntentMoveMm,
            "intent_velocity_mm_per_sec" => settings.IntentVelocityMmPerSec,
            _ => throw new ArgumentOutOfRangeException(nameof(field), field.Id, "Unknown typing tuning field id.")
        };
    }

    public static void SetTextValue(UserSettings settings, TypingTuningTextFieldDefinition field, double value)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(field);

        double clamped = Math.Clamp(value, field.Minimum, field.Maximum);
        switch (field.Id)
        {
            case "hold_duration_ms":
                settings.HoldDurationMs = clamped;
                return;
            case "typing_grace_ms":
                settings.TypingGraceMs = clamped;
                return;
            case "drag_cancel_mm":
                settings.DragCancelMm = clamped;
                return;
            case "intent_move_mm":
                settings.IntentMoveMm = clamped;
                return;
            case "intent_velocity_mm_per_sec":
                settings.IntentVelocityMmPerSec = clamped;
                return;
            default:
                throw new ArgumentOutOfRangeException(nameof(field), field.Id, "Unknown typing tuning field id.");
        }
    }

    public static int GetSliderValue(UserSettings settings, TypingTuningSliderFieldDefinition field)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(field);

        return field.Id switch
        {
            "force_min" => settings.ForceMin,
            "force_cap" => settings.ForceCap,
            _ => throw new ArgumentOutOfRangeException(nameof(field), field.Id, "Unknown typing tuning slider id.")
        };
    }

    public static void SetSliderValue(UserSettings settings, TypingTuningSliderFieldDefinition field, int value)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(field);

        int clamped = Math.Clamp(value, field.Minimum, field.Maximum);
        switch (field.Id)
        {
            case "force_min":
                settings.ForceMin = clamped;
                return;
            case "force_cap":
                settings.ForceCap = clamped;
                return;
            default:
                throw new ArgumentOutOfRangeException(nameof(field), field.Id, "Unknown typing tuning slider id.");
        }
    }

    public static int GetHapticsAmplitude(UserSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        if (!settings.HapticsEnabled)
        {
            return 0;
        }

        int rawAmplitude = (int)(settings.HapticsStrength & 0xFFu);
        return Math.Clamp(rawAmplitude, 0, HapticsAmplitudeMaximum);
    }

    public static void SetHapticsAmplitude(UserSettings settings, int amplitude)
    {
        ArgumentNullException.ThrowIfNull(settings);

        int clamped = Math.Clamp(amplitude, 0, HapticsAmplitudeMaximum);
        settings.HapticsEnabled = clamped != 0;
        settings.HapticsStrength = HapticsStrengthBase | (uint)clamped;
    }

    public static bool NormalizeSettings(UserSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        bool changed = false;
        foreach (TypingTuningTextFieldDefinition field in TextFields)
        {
            double current = GetTextValue(settings, field);
            double clamped = Math.Clamp(current, field.Minimum, field.Maximum);
            if (!AreClose(current, clamped))
            {
                SetTextValue(settings, field, clamped);
                changed = true;
            }
        }

        foreach (TypingTuningSliderFieldDefinition field in SliderFields)
        {
            int current = GetSliderValue(settings, field);
            int clamped = Math.Clamp(current, field.Minimum, field.Maximum);
            if (current != clamped)
            {
                SetSliderValue(settings, field, clamped);
                changed = true;
            }
        }

        if (settings.ForceCap < settings.ForceMin)
        {
            settings.ForceCap = settings.ForceMin;
            changed = true;
        }

        int amplitude = GetHapticsAmplitude(settings);
        bool enabled = amplitude != 0;
        uint normalizedStrength = HapticsStrengthBase | (uint)amplitude;
        if (settings.HapticsEnabled != enabled)
        {
            settings.HapticsEnabled = enabled;
            changed = true;
        }

        if (settings.HapticsStrength != normalizedStrength)
        {
            settings.HapticsStrength = normalizedStrength;
            changed = true;
        }

        return changed;
    }

    private static bool AreClose(double left, double right)
    {
        return Math.Abs(left - right) <= 0.0001;
    }
}
