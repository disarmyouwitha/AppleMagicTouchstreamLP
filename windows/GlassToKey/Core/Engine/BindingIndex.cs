using System;
using System.Collections.Generic;
using System.Globalization;

namespace GlassToKey;

internal sealed class BindingIndex
{
    private readonly int[][] _buckets;

    public BindingIndex(
        EngineKeyBinding[] bindings,
        int bucketRows,
        int bucketColumns,
        int[][] buckets,
        int[] snapBindingIndices,
        float[] snapCentersX,
        float[] snapCentersY,
        float[] snapRadiusSq)
    {
        Bindings = bindings;
        BucketRows = bucketRows;
        BucketColumns = bucketColumns;
        _buckets = buckets;
        SnapBindingIndices = snapBindingIndices;
        SnapCentersX = snapCentersX;
        SnapCentersY = snapCentersY;
        SnapRadiusSq = snapRadiusSq;
    }

    public EngineKeyBinding[] Bindings { get; }
    public int BucketRows { get; }
    public int BucketColumns { get; }
    public int[] SnapBindingIndices { get; }
    public float[] SnapCentersX { get; }
    public float[] SnapCentersY { get; }
    public float[] SnapRadiusSq { get; }

    public EngineBindingHit HitTest(double normalizedX, double normalizedY)
    {
        int row = BucketIndex(normalizedY, BucketRows);
        int col = BucketIndex(normalizedX, BucketColumns);
        int bucket = row * BucketColumns + col;
        int[] candidates = _buckets[bucket];
        int best = -1;
        double bestScore = double.NegativeInfinity;
        double bestArea = double.PositiveInfinity;
        for (int i = 0; i < candidates.Length; i++)
        {
            int index = candidates[i];
            NormalizedRect rect = Bindings[index].Rect;
            if (!rect.Contains(normalizedX, normalizedY))
            {
                continue;
            }

            double dx = Math.Min(normalizedX - rect.X, rect.X + rect.Width - normalizedX);
            double dy = Math.Min(normalizedY - rect.Y, rect.Y + rect.Height - normalizedY);
            double score = Math.Min(dx, dy);
            double area = rect.Width * rect.Height;
            if (score > bestScore || (Math.Abs(score - bestScore) < 1e-9 && area < bestArea))
            {
                best = index;
                bestScore = score;
                bestArea = area;
            }
        }

        return best >= 0 ? new EngineBindingHit(true, best) : EngineBindingHit.Miss;
    }

    public static BindingIndex Build(
        KeyLayout layout,
        TrackpadSide side,
        int layer,
        KeymapStore keymap,
        int bucketRows = 10,
        int bucketColumns = 12,
        double snapRadiusFraction = 0.35)
    {
        double snapFraction = Math.Clamp(snapRadiusFraction, 0.0, 2.0);
        int rows = layout.Rects.Length;
        IReadOnlyList<CustomButton> customButtons = keymap.ResolveCustomButtons(layer, side);
        int estimated = (rows == 0 ? 0 : rows * layout.Rects[0].Length) + customButtons.Count;
        EngineKeyBinding[] bindings = new EngineKeyBinding[estimated];
        int[] snapBindingIndices = new int[estimated];
        float[] snapCentersX = new float[estimated];
        float[] snapCentersY = new float[estimated];
        float[] snapRadiusSq = new float[estimated];
        int cursor = 0;
        int snapCursor = 0;

        for (int row = 0; row < layout.Rects.Length; row++)
        {
            NormalizedRect[] rowRects = layout.Rects[row];
            string[] rowLabels = layout.Labels[row];
            for (int col = 0; col < rowRects.Length; col++)
            {
                string storageKey = GridKeyPosition.StorageKey(side, row, col);
                KeyMapping mapping = keymap.ResolveMapping(layer, storageKey, rowLabels[col]);
                EngineKeyMapping engineMapping = EngineActionResolver.Resolve(mapping, rowLabels[col]);
                NormalizedRect rect = rowRects[col];
                bindings[cursor] = new EngineKeyBinding(
                    side,
                    row,
                    col,
                    storageKey,
                    rowLabels[col],
                    rect,
                    engineMapping);

                if (IsSnappable(engineMapping.Primary))
                {
                    float centerX = (float)(rect.X + (rect.Width * 0.5));
                    float centerY = (float)(rect.Y + (rect.Height * 0.5));
                    float radius = (float)(Math.Min(rect.Width, rect.Height) * 0.5 * snapFraction);
                    snapBindingIndices[snapCursor] = cursor;
                    snapCentersX[snapCursor] = centerX;
                    snapCentersY[snapCursor] = centerY;
                    snapRadiusSq[snapCursor] = radius * radius;
                    snapCursor++;
                }

                cursor++;
            }
        }

        for (int i = 0; i < customButtons.Count; i++)
        {
            CustomButton custom = customButtons[i];
            KeyMapping mapping = new()
            {
                Primary = custom.Primary ?? new KeyAction { Label = "None" },
                Hold = custom.Hold
            };
            string fallbackLabel = string.IsNullOrWhiteSpace(custom.Primary?.Label) ? "None" : custom.Primary.Label;
            EngineKeyMapping engineMapping = EngineActionResolver.Resolve(mapping, fallbackLabel);
            NormalizedRect rect = custom.Rect;
            string storageKey = $"custom:{custom.Id}";
            bindings[cursor] = new EngineKeyBinding(
                side,
                -1,
                -1,
                storageKey,
                fallbackLabel,
                rect,
                engineMapping);

            if (IsSnappable(engineMapping.Primary))
            {
                float centerX = (float)(rect.X + (rect.Width * 0.5));
                float centerY = (float)(rect.Y + (rect.Height * 0.5));
                float radius = (float)(Math.Min(rect.Width, rect.Height) * 0.5 * snapFraction);
                snapBindingIndices[snapCursor] = cursor;
                snapCentersX[snapCursor] = centerX;
                snapCentersY[snapCursor] = centerY;
                snapRadiusSq[snapCursor] = radius * radius;
                snapCursor++;
            }

            cursor++;
        }

        if (cursor != estimated)
        {
            Array.Resize(ref bindings, cursor);
            Array.Resize(ref snapCentersX, cursor);
            Array.Resize(ref snapCentersY, cursor);
            Array.Resize(ref snapRadiusSq, cursor);
        }
        if (snapCursor != snapBindingIndices.Length)
        {
            Array.Resize(ref snapBindingIndices, snapCursor);
            Array.Resize(ref snapCentersX, snapCursor);
            Array.Resize(ref snapCentersY, snapCursor);
            Array.Resize(ref snapRadiusSq, snapCursor);
        }

        List<int>[] bucketLists = new List<int>[bucketRows * bucketColumns];
        for (int i = 0; i < bucketLists.Length; i++)
        {
            bucketLists[i] = new List<int>(4);
        }

        for (int i = 0; i < bindings.Length; i++)
        {
            NormalizedRect rect = bindings[i].Rect;
            int minRow = BucketIndex(rect.Y, bucketRows);
            int maxRow = BucketIndex(rect.Y + rect.Height, bucketRows);
            int minCol = BucketIndex(rect.X, bucketColumns);
            int maxCol = BucketIndex(rect.X + rect.Width, bucketColumns);
            for (int row = minRow; row <= maxRow; row++)
            {
                for (int col = minCol; col <= maxCol; col++)
                {
                    bucketLists[(row * bucketColumns) + col].Add(i);
                }
            }
        }

        int[][] buckets = new int[bucketLists.Length][];
        for (int i = 0; i < bucketLists.Length; i++)
        {
            buckets[i] = bucketLists[i].ToArray();
        }

        return new BindingIndex(bindings, bucketRows, bucketColumns, buckets, snapBindingIndices, snapCentersX, snapCentersY, snapRadiusSq);
    }

    private static bool IsSnappable(EngineKeyAction action)
    {
        return action.Kind is EngineActionKind.Key
            or EngineActionKind.Continuous
            or EngineActionKind.Modifier
            or EngineActionKind.KeyChord;
    }

    private static int BucketIndex(double value, int bucketCount)
    {
        double clamped = value;
        if (clamped < 0) clamped = 0;
        if (clamped > 0.999999) clamped = 0.999999;
        int index = (int)(clamped * bucketCount);
        if (index < 0) return 0;
        if (index >= bucketCount) return bucketCount - 1;
        return index;
    }
}

internal static class EngineActionResolver
{
    public static EngineKeyMapping Resolve(KeyMapping mapping, string defaultLabel)
    {
        EngineKeyAction primary = ResolveActionLabel(mapping.Primary.Label, defaultLabel);
        EngineKeyAction hold = mapping.Hold == null ? EngineKeyAction.None : ResolveActionLabel(mapping.Hold.Label, defaultLabel);
        return new EngineKeyMapping(primary, hold, mapping.Hold != null);
    }

    public static EngineKeyAction ResolveActionLabel(string? label, string fallbackLabel = "None")
    {
        string resolved = string.IsNullOrWhiteSpace(label) ? fallbackLabel : label.Trim();
        if (DispatchKeyResolver.TryResolveMouseButton(resolved, out DispatchMouseButton mouseButton))
        {
            return new EngineKeyAction(EngineActionKind.MouseButton, resolved, LayerTarget: 0, VirtualKey: 0, MouseButton: mouseButton);
        }

        if (TryParseLayerAction(resolved, "MO(", EngineActionKind.MomentaryLayer, out EngineKeyAction momentary))
        {
            return momentary;
        }

        if (TryParseLayerAction(resolved, "TO(", EngineActionKind.LayerSet, out EngineKeyAction layerSet))
        {
            return layerSet;
        }

        if (TryParseLayerAction(resolved, "TG(", EngineActionKind.LayerToggle, out EngineKeyAction layerToggle))
        {
            return layerToggle;
        }

        if (resolved.Equals("TT", StringComparison.OrdinalIgnoreCase) ||
            resolved.Equals("TYPE", StringComparison.OrdinalIgnoreCase) ||
            resolved.Equals("TypingToggle", StringComparison.OrdinalIgnoreCase) ||
            resolved.Equals("Typing Toggle", StringComparison.OrdinalIgnoreCase) ||
            resolved.Equals("Typing Toggle (Dispatch)", StringComparison.OrdinalIgnoreCase))
        {
            return new EngineKeyAction(EngineActionKind.TypingToggle, resolved, 0);
        }

        if (resolved.Equals("Chordal Shift", StringComparison.OrdinalIgnoreCase) ||
            resolved.Equals("Chord Shift", StringComparison.OrdinalIgnoreCase) ||
            resolved.Equals("ChordShift", StringComparison.OrdinalIgnoreCase))
        {
            return new EngineKeyAction(EngineActionKind.Modifier, resolved, 0, 0x10);
        }

        if (TryParseModifierChord(resolved, "Ctrl+", 0x11, out EngineKeyAction chord))
        {
            return chord;
        }

        if (TryParseModifierChord(resolved, "Win+", 0x5B, out EngineKeyAction winChord))
        {
            return winChord;
        }

        if (resolved.Equals("EMOJI", StringComparison.OrdinalIgnoreCase))
        {
            return new EngineKeyAction(
                EngineActionKind.KeyChord,
                resolved,
                LayerTarget: 0,
                VirtualKey: 0xBE, // .
                MouseButton: DispatchMouseButton.None,
                ModifierVirtualKey: 0x5B); // LWin
        }

        if (TryParseShiftChord(resolved, out EngineKeyAction shiftChord))
        {
            return shiftChord;
        }

        if (DispatchKeyResolver.TryResolveModifierVirtualKey(resolved, out ushort modifierKey))
        {
            return new EngineKeyAction(EngineActionKind.Modifier, resolved, 0, modifierKey);
        }

        if (IsContinuousActionLabel(resolved))
        {
            if (DispatchKeyResolver.TryResolveVirtualKey(resolved, out ushort continuousVk))
            {
                return new EngineKeyAction(EngineActionKind.Continuous, resolved, 0, continuousVk);
            }

            return new EngineKeyAction(EngineActionKind.Continuous, resolved, 0);
        }

        if (resolved.Equals("None", StringComparison.OrdinalIgnoreCase))
        {
            return EngineKeyAction.None;
        }

        if (resolved.Equals("EmDash", StringComparison.OrdinalIgnoreCase) ||
            resolved.Equals("—", StringComparison.Ordinal))
        {
            // Best-effort alias: emit OEM minus key.
            return new EngineKeyAction(EngineActionKind.Key, resolved, 0, 0xBD);
        }

        if (DispatchKeyResolver.TryResolveVirtualKey(resolved, out ushort virtualKey))
        {
            return new EngineKeyAction(EngineActionKind.Key, resolved, 0, virtualKey);
        }

        return new EngineKeyAction(EngineActionKind.Key, resolved, 0);
    }

    private static bool IsContinuousActionLabel(string label)
    {
        return label.Equals("Space", StringComparison.OrdinalIgnoreCase) ||
               label.Equals("Back", StringComparison.OrdinalIgnoreCase) ||
               label.Equals("Backspace", StringComparison.OrdinalIgnoreCase) ||
               label.Equals("Left", StringComparison.OrdinalIgnoreCase) ||
               label.Equals("Right", StringComparison.OrdinalIgnoreCase) ||
               label.Equals("Up", StringComparison.OrdinalIgnoreCase) ||
               label.Equals("Down", StringComparison.OrdinalIgnoreCase);
    }

    private static bool TryParseModifierChord(string text, string prefix, ushort modifierVirtualKey, out EngineKeyAction action)
    {
        action = EngineKeyAction.None;
        if (!text.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        string token = text.Substring(prefix.Length).Trim();
        if (!DispatchKeyResolver.TryResolveVirtualKey(token, out ushort keyVk))
        {
            return false;
        }

        action = new EngineKeyAction(
            EngineActionKind.KeyChord,
            text,
            LayerTarget: 0,
            VirtualKey: keyVk,
            MouseButton: DispatchMouseButton.None,
            ModifierVirtualKey: modifierVirtualKey);
        return true;
    }

    private static bool TryParseShiftChord(string text, out EngineKeyAction action)
    {
        action = EngineKeyAction.None;
        ushort vk = text switch
        {
            "!" => 0x31,
            "@" => 0x32,
            "#" => 0x33,
            "$" => 0x34,
            "%" => 0x35,
            "^" => 0x36,
            "&" => 0x37,
            "*" => 0x38,
            "(" => 0x39,
            ")" => 0x30,
            "~" => 0xC0,
            "_" => 0xBD,
            "+" => 0xBB,
            "{" => 0xDB,
            "}" => 0xDD,
            "|" => 0xDC,
            ":" => 0xBA,
            "\"" => 0xDE,
            "<" => 0xBC,
            ">" => 0xBE,
            "?" => 0xBF,
            _ => 0
        };

        if (vk == 0)
        {
            return false;
        }

        action = new EngineKeyAction(
            EngineActionKind.KeyChord,
            text,
            LayerTarget: 0,
            VirtualKey: vk,
            MouseButton: DispatchMouseButton.None,
            ModifierVirtualKey: 0x10);
        return true;
    }

    private static bool TryParseLayerAction(
        string text,
        string prefix,
        EngineActionKind kind,
        out EngineKeyAction action)
    {
        action = EngineKeyAction.None;
        if (!text.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || !text.EndsWith(")", StringComparison.Ordinal))
        {
            return false;
        }

        int start = prefix.Length;
        int length = text.Length - start - 1;
        if (length <= 0)
        {
            return false;
        }

        string token = text.Substring(start, length);
        if (!int.TryParse(token, NumberStyles.Integer, CultureInfo.InvariantCulture, out int layer))
        {
            return false;
        }

        action = new EngineKeyAction(kind, text, Math.Clamp(layer, 0, 7));
        return true;
    }
}
