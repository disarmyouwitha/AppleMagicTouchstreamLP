using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace AmtPtpVisualizer;

public sealed class KeyAction
{
    public string Label { get; set; } = string.Empty;
}

public sealed class KeyMapping
{
    public KeyAction Primary { get; set; } = new();
    public KeyAction? Hold { get; set; }
}

public sealed class CustomButton
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public TrackpadSide Side { get; set; }
    public NormalizedRect Rect { get; set; } = new(0.41, 0.43, 0.18, 0.14);
    public KeyAction Primary { get; set; } = new() { Label = "Space" };
    public KeyAction? Hold { get; set; }
    public int Layer { get; set; }
}

public sealed class KeymapStore
{
    private const string DefaultLayoutKey = "6x3";
    private const double TrackpadWidthMm = 160.0;
    private const double TrackpadHeightMm = 114.9;
    private const double MinCustomButtonSize = 0.05;

    private readonly Dictionary<string, LayoutKeymapData> _layouts = new(StringComparer.OrdinalIgnoreCase);
    private string _activeLayoutKey = DefaultLayoutKey;

    public Dictionary<int, Dictionary<string, KeyMapping>> Mappings => EnsureLayoutData(_activeLayoutKey).Mappings;
    public Dictionary<int, List<CustomButton>> CustomButtons => EnsureLayoutData(_activeLayoutKey).CustomButtons;
    public string ActiveLayoutKey => _activeLayoutKey;

    public static string GetKeymapPath()
    {
        string root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string dir = Path.Combine(root, "AmtPtpVisualizer");
        return Path.Combine(dir, "keymap.json");
    }

    public static KeymapStore Load()
    {
        try
        {
            string path = GetKeymapPath();
            if (!File.Exists(path))
            {
                return CreateDefault(includeCustomDefaults: true);
            }

            string json = File.ReadAllText(path);
            KeymapStore store = CreateDefault(includeCustomDefaults: true);
            if (string.IsNullOrWhiteSpace(json))
            {
                return store;
            }

            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement root = document.RootElement;
            if (root.ValueKind == JsonValueKind.Object && HasPropertyIgnoreCase(root, "Layouts"))
            {
                KeymapFileModel? model = JsonSerializer.Deserialize<KeymapFileModel>(
                    json,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                if (model?.Layouts != null && model.Layouts.Count > 0)
                {
                    store._layouts.Clear();
                    foreach (KeyValuePair<string, LayoutKeymapData> entry in model.Layouts)
                    {
                        if (string.IsNullOrWhiteSpace(entry.Key) || entry.Value == null)
                        {
                            continue;
                        }

                        store._layouts[entry.Key] = NormalizeLayoutData(entry.Key, entry.Value);
                    }
                }
                store.SetActiveLayout(DefaultLayoutKey);
                return store;
            }

            Dictionary<int, Dictionary<string, KeyMapping>>? legacyMappings = JsonSerializer.Deserialize<Dictionary<int, Dictionary<string, KeyMapping>>>(json);
            if (legacyMappings != null)
            {
                store._layouts[DefaultLayoutKey] = new LayoutKeymapData
                {
                    Mappings = NormalizeMappings(legacyMappings),
                    CustomButtons = BuildDefaultCustomButtons(DefaultLayoutKey)
                };
            }
            store.SetActiveLayout(DefaultLayoutKey);
            return store;
        }
        catch
        {
            return CreateDefault(includeCustomDefaults: true);
        }
    }

    public static KeymapStore CreateDefault(bool includeCustomDefaults = false)
    {
        KeymapStore store = new();
        store._layouts[DefaultLayoutKey] = new LayoutKeymapData
        {
            Mappings = DefaultMappings(),
            CustomButtons = includeCustomDefaults
                ? BuildDefaultCustomButtons(DefaultLayoutKey)
                : new Dictionary<int, List<CustomButton>>()
        };
        store.SetActiveLayout(DefaultLayoutKey);
        return store;
    }

    public void Save()
    {
        try
        {
            string path = GetKeymapPath();
            string? dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(dir))
            {
                Directory.CreateDirectory(dir);
            }

            var options = new JsonSerializerOptions { WriteIndented = true };
            KeymapFileModel file = new()
            {
                Version = 2,
                Layouts = _layouts
            };
            string json = JsonSerializer.Serialize(file, options);
            File.WriteAllText(path, json);
        }
        catch
        {
            // Best-effort persistence.
        }
    }

    public void SetActiveLayout(string? layoutKey)
    {
        string resolved = string.IsNullOrWhiteSpace(layoutKey) ? DefaultLayoutKey : layoutKey.Trim();
        _activeLayoutKey = resolved;
        EnsureLayoutData(_activeLayoutKey);
    }

    public string ResolveLabel(int layer, string storageKey, string defaultLabel)
    {
        if (Mappings.TryGetValue(layer, out Dictionary<string, KeyMapping>? layerMap))
        {
            if (layerMap.TryGetValue(storageKey, out KeyMapping? mapping) && !string.IsNullOrWhiteSpace(mapping.Primary.Label))
            {
                return mapping.Primary.Label;
            }
        }
        return defaultLabel;
    }

    public KeyMapping ResolveMapping(int layer, string storageKey, string defaultLabel)
    {
        if (Mappings.TryGetValue(layer, out Dictionary<string, KeyMapping>? layerMap) &&
            layerMap.TryGetValue(storageKey, out KeyMapping? mapping))
        {
            if (mapping.Primary == null)
            {
                mapping.Primary = new KeyAction { Label = defaultLabel };
            }
            else if (string.IsNullOrWhiteSpace(mapping.Primary.Label))
            {
                mapping.Primary.Label = defaultLabel;
            }
            return mapping;
        }

        return new KeyMapping
        {
            Primary = new KeyAction { Label = defaultLabel },
            Hold = null
        };
    }

    public List<CustomButton> GetOrCreateCustomButtons(int layer)
    {
        int clampedLayer = Math.Clamp(layer, 0, 7);
        Dictionary<int, List<CustomButton>> byLayer = CustomButtons;
        if (!byLayer.TryGetValue(clampedLayer, out List<CustomButton>? buttons))
        {
            buttons = new List<CustomButton>();
            byLayer[clampedLayer] = buttons;
        }

        return buttons;
    }

    public IReadOnlyList<CustomButton> ResolveCustomButtons(int layer, TrackpadSide side)
    {
        int clampedLayer = Math.Clamp(layer, 0, 7);
        if (!CustomButtons.TryGetValue(clampedLayer, out List<CustomButton>? buttons) || buttons.Count == 0)
        {
            return Array.Empty<CustomButton>();
        }

        List<CustomButton> resolved = new(buttons.Count);
        for (int i = 0; i < buttons.Count; i++)
        {
            CustomButton button = SanitizeButton(buttons[i], clampedLayer);
            if (button.Side != side)
            {
                continue;
            }

            resolved.Add(button);
        }

        return resolved;
    }

    public CustomButton? FindCustomButton(int layer, string id)
    {
        if (string.IsNullOrWhiteSpace(id))
        {
            return null;
        }

        int clampedLayer = Math.Clamp(layer, 0, 7);
        if (!CustomButtons.TryGetValue(clampedLayer, out List<CustomButton>? buttons) || buttons.Count == 0)
        {
            return null;
        }

        for (int i = 0; i < buttons.Count; i++)
        {
            if (string.Equals(buttons[i].Id, id, StringComparison.Ordinal))
            {
                return buttons[i];
            }
        }

        return null;
    }

    public bool RemoveCustomButton(int layer, string id)
    {
        if (string.IsNullOrWhiteSpace(id))
        {
            return false;
        }

        int clampedLayer = Math.Clamp(layer, 0, 7);
        if (!CustomButtons.TryGetValue(clampedLayer, out List<CustomButton>? buttons) || buttons.Count == 0)
        {
            return false;
        }

        int removed = buttons.RemoveAll(button => string.Equals(button.Id, id, StringComparison.Ordinal));
        return removed > 0;
    }

    public static NormalizedRect ClampCustomButtonRect(NormalizedRect rect)
    {
        double width = ClampRange(rect.Width, MinCustomButtonSize, 1.0);
        double height = ClampRange(rect.Height, MinCustomButtonSize, 1.0);
        double x = ClampRange(rect.X, 0.0, 1.0 - width);
        double y = ClampRange(rect.Y, 0.0, 1.0 - height);
        return new NormalizedRect(x, y, width, height);
    }

    private static Dictionary<int, Dictionary<string, KeyMapping>> DefaultMappings()
    {
        return new Dictionary<int, Dictionary<string, KeyMapping>>
        {
            [0] = new Dictionary<string, KeyMapping>(),
            [1] = new Dictionary<string, KeyMapping>(),
            [2] = new Dictionary<string, KeyMapping>(),
            [3] = new Dictionary<string, KeyMapping>(),
            [4] = new Dictionary<string, KeyMapping>(),
            [5] = new Dictionary<string, KeyMapping>(),
            [6] = new Dictionary<string, KeyMapping>(),
            [7] = new Dictionary<string, KeyMapping>()
        };
    }

    private static Dictionary<int, Dictionary<string, KeyMapping>> NormalizeMappings(Dictionary<int, Dictionary<string, KeyMapping>>? mappings)
    {
        Dictionary<int, Dictionary<string, KeyMapping>> normalized = DefaultMappings();
        if (mappings == null)
        {
            return normalized;
        }

        foreach (KeyValuePair<int, Dictionary<string, KeyMapping>> entry in mappings)
        {
            int layer = Math.Clamp(entry.Key, 0, 7);
            Dictionary<string, KeyMapping> target = normalized[layer];
            if (entry.Value == null)
            {
                continue;
            }

            foreach (KeyValuePair<string, KeyMapping> mappingEntry in entry.Value)
            {
                if (string.IsNullOrWhiteSpace(mappingEntry.Key))
                {
                    continue;
                }

                KeyMapping mapping = mappingEntry.Value ?? new KeyMapping();
                mapping.Primary ??= new KeyAction();
                if (string.IsNullOrWhiteSpace(mapping.Primary.Label))
                {
                    mapping.Primary.Label = "None";
                }
                target[mappingEntry.Key] = mapping;
            }
        }

        return normalized;
    }

    private LayoutKeymapData EnsureLayoutData(string layoutKey)
    {
        if (_layouts.TryGetValue(layoutKey, out LayoutKeymapData? data) && data != null)
        {
            return data;
        }

        LayoutKeymapData created = new()
        {
            Mappings = DefaultMappings(),
            CustomButtons = BuildDefaultCustomButtons(layoutKey)
        };
        _layouts[layoutKey] = created;
        return created;
    }

    private static LayoutKeymapData NormalizeLayoutData(string layoutKey, LayoutKeymapData source)
    {
        LayoutKeymapData normalized = new()
        {
            Mappings = NormalizeMappings(source.Mappings),
            CustomButtons = new Dictionary<int, List<CustomButton>>()
        };

        if (source.CustomButtons != null)
        {
            foreach (KeyValuePair<int, List<CustomButton>> entry in source.CustomButtons)
            {
                int layer = Math.Clamp(entry.Key, 0, 7);
                List<CustomButton> list = new();
                if (entry.Value != null)
                {
                    for (int i = 0; i < entry.Value.Count; i++)
                    {
                        list.Add(SanitizeButton(entry.Value[i], layer));
                    }
                }

                normalized.CustomButtons[layer] = list;
            }
        }

        if (normalized.CustomButtons.Count == 0)
        {
            normalized.CustomButtons = BuildDefaultCustomButtons(layoutKey);
        }

        return normalized;
    }

    private static CustomButton SanitizeButton(CustomButton source, int layer)
    {
        CustomButton input = source ?? new CustomButton();
        KeyAction primary = input.Primary ?? new KeyAction();
        if (string.IsNullOrWhiteSpace(primary.Label))
        {
            primary.Label = "Space";
        }

        return new CustomButton
        {
            Id = string.IsNullOrWhiteSpace(input.Id) ? Guid.NewGuid().ToString("N") : input.Id.Trim(),
            Side = input.Side,
            Rect = ClampCustomButtonRect(input.Rect),
            Primary = primary,
            Hold = input.Hold,
            Layer = Math.Clamp(layer, 0, 7)
        };
    }

    private static Dictionary<int, List<CustomButton>> BuildDefaultCustomButtons(string layoutKey)
    {
        Dictionary<int, List<CustomButton>> defaults = new();
        if (!string.Equals(layoutKey, DefaultLayoutKey, StringComparison.OrdinalIgnoreCase))
        {
            return defaults;
        }

        // Mirrors the mac defaults for 6x3 thumb anchors/actions.
        (double X, double Y, double Width, double Height)[] anchors =
        {
            (0.0, 75.0, 40.0, 40.0),
            (40.0, 85.0, 40.0, 30.0),
            (80.0, 85.0, 40.0, 30.0),
            (120.0, 85.0, 40.0, 30.0)
        };

        List<CustomButton> layer0 = new(6);
        string[] rightActions = { "Space", "Space", "Space", "Ret" };
        string[] leftActions = { "Back", "Space" };

        for (int i = 0; i < anchors.Length; i++)
        {
            NormalizedRect rightRect = NormalizeRect(anchors[i].X, anchors[i].Y, anchors[i].Width, anchors[i].Height, mirrored: false);
            layer0.Add(new CustomButton
            {
                Id = $"default-right-{i}",
                Side = TrackpadSide.Right,
                Rect = rightRect,
                Primary = new KeyAction { Label = rightActions[i] },
                Hold = null,
                Layer = 0
            });

            if (i < leftActions.Length)
            {
                NormalizedRect leftRect = NormalizeRect(anchors[i].X, anchors[i].Y, anchors[i].Width, anchors[i].Height, mirrored: true);
                layer0.Add(new CustomButton
                {
                    Id = $"default-left-{i}",
                    Side = TrackpadSide.Left,
                    Rect = leftRect,
                    Primary = new KeyAction { Label = leftActions[i] },
                    Hold = null,
                    Layer = 0
                });
            }
        }

        defaults[0] = layer0;
        return defaults;
    }

    private static NormalizedRect NormalizeRect(double xMm, double yMm, double widthMm, double heightMm, bool mirrored)
    {
        double width = widthMm / TrackpadWidthMm;
        double height = heightMm / TrackpadHeightMm;
        double x = xMm / TrackpadWidthMm;
        if (mirrored)
        {
            x = 1.0 - x - width;
        }
        double y = yMm / TrackpadHeightMm;
        return ClampCustomButtonRect(new NormalizedRect(x, y, width, height));
    }

    private static double ClampRange(double value, double min, double max)
    {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    private static bool HasPropertyIgnoreCase(JsonElement element, string propertyName)
    {
        foreach (JsonProperty property in element.EnumerateObject())
        {
            if (string.Equals(property.Name, propertyName, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    public sealed class KeymapFileModel
    {
        public int Version { get; set; } = 2;
        public Dictionary<string, LayoutKeymapData> Layouts { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }

    public sealed class LayoutKeymapData
    {
        public Dictionary<int, Dictionary<string, KeyMapping>> Mappings { get; set; } = DefaultMappings();
        public Dictionary<int, List<CustomButton>> CustomButtons { get; set; } = new();
    }
}
