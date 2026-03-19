using System;
using System.Collections.Generic;

namespace GlassToKey;

public sealed record GestureSectionDefinition(string Id, string Title, bool IsExpandedByDefault);

public sealed record GestureBindingDefinition(
    string Id,
    string SectionId,
    string Label,
    string DefaultAction);

public static class GestureBindingCatalog
{
    public const int MaxRepeatCadenceMs = 5000;

    public static IReadOnlyList<GestureSectionDefinition> Sections { get; } =
    [
        new GestureSectionDefinition("holds", "Holds", true),
        new GestureSectionDefinition("edges", "Edges", false),
        new GestureSectionDefinition("swipes", "Swipes", false),
        new GestureSectionDefinition("triangles", "Triangles", false),
        new GestureSectionDefinition("clicks", "Clicks", false),
        new GestureSectionDefinition("force_clicks", "Force Clicks", false)
    ];

    public static IReadOnlyList<GestureBindingDefinition> All { get; } =
    [
        new GestureBindingDefinition("two_finger_hold", "holds", "2-finger hold", "None"),
        new GestureBindingDefinition("three_finger_hold", "holds", "3-finger hold", "None"),
        new GestureBindingDefinition("four_finger_hold", "holds", "4-finger hold", "Chordal Shift"),
        new GestureBindingDefinition("inner_corners", "holds", "Inner corners", "None"),
        new GestureBindingDefinition("outer_corners", "holds", "Outer corners", "None"),

        new GestureBindingDefinition("left_edge_up", "edges", "Left Edge Up", "None"),
        new GestureBindingDefinition("left_edge_down", "edges", "Left Edge Down", "None"),
        new GestureBindingDefinition("right_edge_up", "edges", "Right Edge Up", "None"),
        new GestureBindingDefinition("right_edge_down", "edges", "Right Edge Down", "None"),
        new GestureBindingDefinition("top_edge_left", "edges", "Top Edge Left", "None"),
        new GestureBindingDefinition("top_edge_right", "edges", "Top Edge Right", "None"),
        new GestureBindingDefinition("bottom_edge_left", "edges", "Bottom Edge Left", "None"),
        new GestureBindingDefinition("bottom_edge_right", "edges", "Bottom Edge Right", "None"),

        new GestureBindingDefinition("three_finger_swipe_left", "swipes", "3-finger left", "None"),
        new GestureBindingDefinition("three_finger_swipe_right", "swipes", "3-finger right", "None"),
        new GestureBindingDefinition("three_finger_swipe_up", "swipes", "3-finger up", "None"),
        new GestureBindingDefinition("three_finger_swipe_down", "swipes", "3-finger down", "None"),
        new GestureBindingDefinition("four_finger_swipe_left", "swipes", "4-finger left", "None"),
        new GestureBindingDefinition("four_finger_swipe_right", "swipes", "4-finger right", "None"),
        new GestureBindingDefinition("four_finger_swipe_up", "swipes", "4-finger up", "None"),
        new GestureBindingDefinition("four_finger_swipe_down", "swipes", "4-finger down", "None"),
        new GestureBindingDefinition("five_finger_swipe_left", "swipes", "5-finger left", "Typing Toggle"),
        new GestureBindingDefinition("five_finger_swipe_right", "swipes", "5-finger right", "Typing Toggle"),
        new GestureBindingDefinition("five_finger_swipe_up", "swipes", "5-finger up", "None"),
        new GestureBindingDefinition("five_finger_swipe_down", "swipes", "5-finger down", "None"),

        new GestureBindingDefinition("top_left_triangle", "triangles", "Top Left", "None"),
        new GestureBindingDefinition("top_right_triangle", "triangles", "Top Right", "None"),
        new GestureBindingDefinition("bottom_left_triangle", "triangles", "Bottom Left", "None"),
        new GestureBindingDefinition("bottom_right_triangle", "triangles", "Bottom Right", "None"),

        new GestureBindingDefinition("three_finger_click", "clicks", "3-Finger Click", "None"),
        new GestureBindingDefinition("four_finger_click", "clicks", "4-Finger Click", "None"),
        new GestureBindingDefinition("upper_left_corner_click", "clicks", "Top Left", "None"),
        new GestureBindingDefinition("upper_right_corner_click", "clicks", "Top Right", "None"),
        new GestureBindingDefinition("lower_left_corner_click", "clicks", "Bottom Left", "None"),
        new GestureBindingDefinition("lower_right_corner_click", "clicks", "Bottom Right", "None"),

        new GestureBindingDefinition("force_click_1", "force_clicks", "Force Click1", "None"),
        new GestureBindingDefinition("force_click_2", "force_clicks", "Force Click2", "None"),
        new GestureBindingDefinition("force_click_3", "force_clicks", "Force Click3", "None")
    ];

    private static readonly Dictionary<string, int> BindingIndexById = BuildBindingIndexById();

    public static IEnumerable<GestureBindingDefinition> EnumerateSectionBindings(string sectionId)
    {
        for (int index = 0; index < All.Count; index++)
        {
            GestureBindingDefinition binding = All[index];
            if (string.Equals(binding.SectionId, sectionId, StringComparison.Ordinal))
            {
                yield return binding;
            }
        }
    }

    public static IEnumerable<string> EnumerateConfiguredActions(UserSettings settings)
    {
        if (settings == null)
        {
            throw new ArgumentNullException(nameof(settings));
        }

        for (int index = 0; index < All.Count; index++)
        {
            yield return GetAction(settings, All[index]);
        }
    }

    public static string GetAction(UserSettings settings, GestureBindingDefinition binding)
    {
        if (settings == null)
        {
            throw new ArgumentNullException(nameof(settings));
        }

        if (binding == null)
        {
            throw new ArgumentNullException(nameof(binding));
        }

        return NormalizeAction(GetStoredAction(settings, binding.Id), binding.DefaultAction);
    }

    public static void SetAction(UserSettings settings, GestureBindingDefinition binding, string? action)
    {
        if (settings == null)
        {
            throw new ArgumentNullException(nameof(settings));
        }

        if (binding == null)
        {
            throw new ArgumentNullException(nameof(binding));
        }

        SetStoredAction(settings, binding.Id, NormalizeAction(action, binding.DefaultAction));
    }

    public static int GetRepeatCadenceMs(UserSettings settings, GestureBindingDefinition binding)
    {
        if (settings == null)
        {
            throw new ArgumentNullException(nameof(settings));
        }

        if (binding == null)
        {
            throw new ArgumentNullException(nameof(binding));
        }

        return NormalizeRepeatCadenceMs(GetStoredRepeatCadenceMs(settings, binding.Id));
    }

    public static void SetRepeatCadenceMs(UserSettings settings, GestureBindingDefinition binding, int cadenceMs)
    {
        if (settings == null)
        {
            throw new ArgumentNullException(nameof(settings));
        }

        if (binding == null)
        {
            throw new ArgumentNullException(nameof(binding));
        }

        SetStoredRepeatCadenceMs(settings, binding.Id, NormalizeRepeatCadenceMs(cadenceMs));
    }

    public static bool NormalizeSettings(UserSettings settings)
    {
        if (settings == null)
        {
            throw new ArgumentNullException(nameof(settings));
        }

        bool changed = false;
        for (int index = 0; index < All.Count; index++)
        {
            GestureBindingDefinition binding = All[index];
            string normalized = NormalizeAction(GetStoredAction(settings, binding.Id), binding.DefaultAction);
            if (!string.Equals(GetStoredAction(settings, binding.Id), normalized, StringComparison.Ordinal))
            {
                SetStoredAction(settings, binding.Id, normalized);
                changed = true;
            }

            int normalizedCadenceMs = NormalizeRepeatCadenceMs(GetStoredRepeatCadenceMs(settings, binding.Id));
            if (GetStoredRepeatCadenceMs(settings, binding.Id) != normalizedCadenceMs)
            {
                SetStoredRepeatCadenceMs(settings, binding.Id, normalizedCadenceMs);
                changed = true;
            }
        }

        bool chordShiftEnabled = UsesChordShift(settings);
        if (settings.ChordShiftEnabled != chordShiftEnabled)
        {
            settings.ChordShiftEnabled = chordShiftEnabled;
            changed = true;
        }

        return changed;
    }

    public static bool UsesChordShift(UserSettings settings)
    {
        if (settings == null)
        {
            throw new ArgumentNullException(nameof(settings));
        }

        return IsChordShiftGestureAction(settings.FourFingerHoldAction);
    }

    public static bool IsChordShiftGestureAction(string? action)
    {
        return string.Equals(action?.Trim(), "Chordal Shift", StringComparison.OrdinalIgnoreCase);
    }

    public static string NormalizeAction(string? action, string fallback)
    {
        return string.IsNullOrWhiteSpace(action) ? fallback : action.Trim();
    }

    public static int NormalizeRepeatCadenceMs(int cadenceMs)
    {
        return Math.Clamp(cadenceMs, 0, MaxRepeatCadenceMs);
    }

    public static Dictionary<string, int>? BuildRepeatCadenceMap(UserSettings settings)
    {
        if (settings == null)
        {
            throw new ArgumentNullException(nameof(settings));
        }

        Dictionary<string, int>? map = null;
        for (int index = 0; index < All.Count; index++)
        {
            GestureBindingDefinition binding = All[index];
            int cadenceMs = GetRepeatCadenceMs(settings, binding);
            if (cadenceMs <= 0)
            {
                continue;
            }

            map ??= new Dictionary<string, int>(StringComparer.Ordinal);
            map[binding.Id] = cadenceMs;
        }

        return map;
    }

    public static int GetBindingIndex(string bindingId)
    {
        if (bindingId == null)
        {
            throw new ArgumentNullException(nameof(bindingId));
        }

        if (BindingIndexById.TryGetValue(bindingId, out int index))
        {
            return index;
        }

        throw new ArgumentOutOfRangeException(nameof(bindingId), bindingId, "Unknown gesture binding id.");
    }

    private static string GetStoredAction(UserSettings settings, string bindingId)
    {
        return bindingId switch
        {
            "two_finger_hold" => settings.TwoFingerHoldAction,
            "three_finger_hold" => settings.ThreeFingerHoldAction,
            "four_finger_hold" => settings.FourFingerHoldAction,
            "inner_corners" => settings.InnerCornersAction,
            "outer_corners" => settings.OuterCornersAction,
            "left_edge_up" => settings.LeftEdgeUpAction,
            "left_edge_down" => settings.LeftEdgeDownAction,
            "right_edge_up" => settings.RightEdgeUpAction,
            "right_edge_down" => settings.RightEdgeDownAction,
            "top_edge_left" => settings.TopEdgeLeftAction,
            "top_edge_right" => settings.TopEdgeRightAction,
            "bottom_edge_left" => settings.BottomEdgeLeftAction,
            "bottom_edge_right" => settings.BottomEdgeRightAction,
            "three_finger_swipe_left" => settings.ThreeFingerSwipeLeftAction,
            "three_finger_swipe_right" => settings.ThreeFingerSwipeRightAction,
            "three_finger_swipe_up" => settings.ThreeFingerSwipeUpAction,
            "three_finger_swipe_down" => settings.ThreeFingerSwipeDownAction,
            "four_finger_swipe_left" => settings.FourFingerSwipeLeftAction,
            "four_finger_swipe_right" => settings.FourFingerSwipeRightAction,
            "four_finger_swipe_up" => settings.FourFingerSwipeUpAction,
            "four_finger_swipe_down" => settings.FourFingerSwipeDownAction,
            "five_finger_swipe_left" => settings.FiveFingerSwipeLeftAction,
            "five_finger_swipe_right" => settings.FiveFingerSwipeRightAction,
            "five_finger_swipe_up" => settings.FiveFingerSwipeUpAction,
            "five_finger_swipe_down" => settings.FiveFingerSwipeDownAction,
            "top_left_triangle" => settings.TopLeftTriangleAction,
            "top_right_triangle" => settings.TopRightTriangleAction,
            "bottom_left_triangle" => settings.BottomLeftTriangleAction,
            "bottom_right_triangle" => settings.BottomRightTriangleAction,
            "three_finger_click" => settings.ThreeFingerClickAction,
            "four_finger_click" => settings.FourFingerClickAction,
            "upper_left_corner_click" => settings.UpperLeftCornerClickAction,
            "upper_right_corner_click" => settings.UpperRightCornerClickAction,
            "lower_left_corner_click" => settings.LowerLeftCornerClickAction,
            "lower_right_corner_click" => settings.LowerRightCornerClickAction,
            "force_click_1" => settings.ForceClick1Action,
            "force_click_2" => settings.ForceClick2Action,
            "force_click_3" => settings.ForceClick3Action,
            _ => throw new ArgumentOutOfRangeException(nameof(bindingId), bindingId, "Unknown gesture binding id.")
        };
    }

    private static int GetStoredRepeatCadenceMs(UserSettings settings, string bindingId)
    {
        if (settings.GestureRepeatCadenceMsById != null &&
            settings.GestureRepeatCadenceMsById.TryGetValue(bindingId, out int cadenceMs))
        {
            return cadenceMs;
        }

        return 0;
    }

    private static void SetStoredAction(UserSettings settings, string bindingId, string action)
    {
        switch (bindingId)
        {
            case "two_finger_hold":
                settings.TwoFingerHoldAction = action;
                return;
            case "three_finger_hold":
                settings.ThreeFingerHoldAction = action;
                return;
            case "four_finger_hold":
                settings.FourFingerHoldAction = action;
                return;
            case "inner_corners":
                settings.InnerCornersAction = action;
                return;
            case "outer_corners":
                settings.OuterCornersAction = action;
                return;
            case "left_edge_up":
                settings.LeftEdgeUpAction = action;
                return;
            case "left_edge_down":
                settings.LeftEdgeDownAction = action;
                return;
            case "right_edge_up":
                settings.RightEdgeUpAction = action;
                return;
            case "right_edge_down":
                settings.RightEdgeDownAction = action;
                return;
            case "top_edge_left":
                settings.TopEdgeLeftAction = action;
                return;
            case "top_edge_right":
                settings.TopEdgeRightAction = action;
                return;
            case "bottom_edge_left":
                settings.BottomEdgeLeftAction = action;
                return;
            case "bottom_edge_right":
                settings.BottomEdgeRightAction = action;
                return;
            case "three_finger_swipe_left":
                settings.ThreeFingerSwipeLeftAction = action;
                return;
            case "three_finger_swipe_right":
                settings.ThreeFingerSwipeRightAction = action;
                return;
            case "three_finger_swipe_up":
                settings.ThreeFingerSwipeUpAction = action;
                return;
            case "three_finger_swipe_down":
                settings.ThreeFingerSwipeDownAction = action;
                return;
            case "four_finger_swipe_left":
                settings.FourFingerSwipeLeftAction = action;
                return;
            case "four_finger_swipe_right":
                settings.FourFingerSwipeRightAction = action;
                return;
            case "four_finger_swipe_up":
                settings.FourFingerSwipeUpAction = action;
                return;
            case "four_finger_swipe_down":
                settings.FourFingerSwipeDownAction = action;
                return;
            case "five_finger_swipe_left":
                settings.FiveFingerSwipeLeftAction = action;
                return;
            case "five_finger_swipe_right":
                settings.FiveFingerSwipeRightAction = action;
                return;
            case "five_finger_swipe_up":
                settings.FiveFingerSwipeUpAction = action;
                return;
            case "five_finger_swipe_down":
                settings.FiveFingerSwipeDownAction = action;
                return;
            case "top_left_triangle":
                settings.TopLeftTriangleAction = action;
                return;
            case "top_right_triangle":
                settings.TopRightTriangleAction = action;
                return;
            case "bottom_left_triangle":
                settings.BottomLeftTriangleAction = action;
                return;
            case "bottom_right_triangle":
                settings.BottomRightTriangleAction = action;
                return;
            case "three_finger_click":
                settings.ThreeFingerClickAction = action;
                return;
            case "four_finger_click":
                settings.FourFingerClickAction = action;
                return;
            case "upper_left_corner_click":
                settings.UpperLeftCornerClickAction = action;
                return;
            case "upper_right_corner_click":
                settings.UpperRightCornerClickAction = action;
                return;
            case "lower_left_corner_click":
                settings.LowerLeftCornerClickAction = action;
                return;
            case "lower_right_corner_click":
                settings.LowerRightCornerClickAction = action;
                return;
            case "force_click_1":
                settings.ForceClick1Action = action;
                return;
            case "force_click_2":
                settings.ForceClick2Action = action;
                return;
            case "force_click_3":
                settings.ForceClick3Action = action;
                return;
            default:
                throw new ArgumentOutOfRangeException(nameof(bindingId), bindingId, "Unknown gesture binding id.");
        }
    }

    private static void SetStoredRepeatCadenceMs(UserSettings settings, string bindingId, int cadenceMs)
    {
        if (cadenceMs <= 0)
        {
            settings.GestureRepeatCadenceMsById?.Remove(bindingId);
            return;
        }

        settings.GestureRepeatCadenceMsById ??= new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        settings.GestureRepeatCadenceMsById[bindingId] = cadenceMs;
    }

    private static Dictionary<string, int> BuildBindingIndexById()
    {
        Dictionary<string, int> indexById = new(StringComparer.Ordinal);
        for (int index = 0; index < All.Count; index++)
        {
            indexById[All[index].Id] = index;
        }

        return indexById;
    }
}
