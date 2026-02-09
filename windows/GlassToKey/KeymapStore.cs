using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace GlassToKey;

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
        string dir = Path.Combine(root, "GlassToKey");
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
            if (TryCreateFromJson(json, allowEmpty: true, out KeymapStore store))
            {
                return store;
            }

            return CreateDefault(includeCustomDefaults: true);
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
            Mappings = BuildDefaultMappingsForLayout(DefaultLayoutKey),
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

            File.WriteAllText(path, Serialize(writeIndented: true));
        }
        catch
        {
            // Best-effort persistence.
        }
    }

    public bool TryExportToFile(string path, out string error)
    {
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(path))
        {
            error = "Export path is empty.";
            return false;
        }

        try
        {
            string? dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(dir))
            {
                Directory.CreateDirectory(dir);
            }

            File.WriteAllText(path, Serialize(writeIndented: true));
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    public bool TryImportFromFile(string path, out string error)
    {
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(path))
        {
            error = "Import path is empty.";
            return false;
        }

        try
        {
            string json = File.ReadAllText(path);
            return TryImportFromJson(json, out error);
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    public bool TryImportFromJson(string json, out string error)
    {
        error = string.Empty;
        if (!TryCreateFromJson(json, allowEmpty: false, out KeymapStore imported))
        {
            error = "Invalid keymap JSON format.";
            return false;
        }

        ApplyFrom(imported);
        return true;
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

    private static Dictionary<int, Dictionary<string, KeyMapping>> CreateEmptyMappings()
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

    private static Dictionary<int, Dictionary<string, KeyMapping>> BuildDefaultMappingsForLayout(string layoutKey)
    {
        Dictionary<int, Dictionary<string, KeyMapping>> mappings = CreateEmptyMappings();
        if (!string.Equals(layoutKey, DefaultLayoutKey, StringComparison.OrdinalIgnoreCase))
        {
            return mappings;
        }

        SeedDefaultSixByThreeMappings(mappings);
        return mappings;
    }

    private static void SeedDefaultSixByThreeMappings(Dictionary<int, Dictionary<string, KeyMapping>> mappings)
    {
        AddDefaultMapping(mappings, 0, "left:0:0", "T", "'");
        AddDefaultMapping(mappings, 0, "left:0:1", "R", "}");
        AddDefaultMapping(mappings, 0, "left:0:2", "E", "{");
        AddDefaultMapping(mappings, 0, "left:0:3", "W", "]");
        AddDefaultMapping(mappings, 0, "left:0:4", "Q", "[");
        AddDefaultMapping(mappings, 0, "left:0:5", "Tab", null);
        AddDefaultMapping(mappings, 0, "left:1:0", "G", "\"");
        AddDefaultMapping(mappings, 0, "left:1:1", "F", ")");
        AddDefaultMapping(mappings, 0, "left:1:2", "D", "(");
        AddDefaultMapping(mappings, 0, "left:1:3", "S", "Ctrl+S");
        AddDefaultMapping(mappings, 0, "left:1:4", "A", "Ctrl+A");
        AddDefaultMapping(mappings, 0, "left:1:5", "Shift", null);
        AddDefaultMapping(mappings, 0, "left:2:0", "B", "`");
        AddDefaultMapping(mappings, 0, "left:2:1", "V", "Ctrl+V");
        AddDefaultMapping(mappings, 0, "left:2:2", "C", "Ctrl+C");
        AddDefaultMapping(mappings, 0, "left:2:3", "X", "Ctrl+X");
        AddDefaultMapping(mappings, 0, "left:2:4", "Z", "Ctrl+Z");
        AddDefaultMapping(mappings, 0, "left:2:5", "Shift", null);
        AddDefaultMapping(mappings, 0, "right:0:0", "Y", "-");
        AddDefaultMapping(mappings, 0, "right:0:1", "U", "&");
        AddDefaultMapping(mappings, 0, "right:0:2", "I", "*");
        AddDefaultMapping(mappings, 0, "right:0:3", "O", "Ctrl+F");
        AddDefaultMapping(mappings, 0, "right:1:0", "H", "_");
        AddDefaultMapping(mappings, 0, "right:1:1", "J", "!");
        AddDefaultMapping(mappings, 0, "right:1:2", "K", "#");
        AddDefaultMapping(mappings, 0, "right:1:3", "L", "~");
        AddDefaultMapping(mappings, 0, "right:2:0", "N", "=");
        AddDefaultMapping(mappings, 0, "right:2:1", "M", "@");
        AddDefaultMapping(mappings, 0, "right:2:2", ",", "$");
        AddDefaultMapping(mappings, 0, "right:2:3", ".", "^");

        AddDefaultMapping(mappings, 1, "left:0:0", "None", null);
        AddDefaultMapping(mappings, 1, "left:0:1", "None", null);
        AddDefaultMapping(mappings, 1, "left:0:2", "None", null);
        AddDefaultMapping(mappings, 1, "left:0:3", "Up", null);
        AddDefaultMapping(mappings, 1, "left:0:4", "None", null);
        AddDefaultMapping(mappings, 1, "left:0:5", "None", null);
        AddDefaultMapping(mappings, 1, "left:1:0", "None", null);
        AddDefaultMapping(mappings, 1, "left:1:1", "None", null);
        AddDefaultMapping(mappings, 1, "left:1:2", "Right", null);
        AddDefaultMapping(mappings, 1, "left:1:3", "Down", null);
        AddDefaultMapping(mappings, 1, "left:1:4", "Left", null);
        AddDefaultMapping(mappings, 1, "left:1:5", "None", null);
        AddDefaultMapping(mappings, 1, "left:2:0", "None", null);
        AddDefaultMapping(mappings, 1, "left:2:1", "None", null);
        AddDefaultMapping(mappings, 1, "left:2:2", "F", null);
        AddDefaultMapping(mappings, 1, "left:2:3", "Space", null);
        AddDefaultMapping(mappings, 1, "left:2:4", "Ret", null);
        AddDefaultMapping(mappings, 1, "left:2:5", "None", null);
        AddDefaultMapping(mappings, 1, "right:0:0", "+", null);
        AddDefaultMapping(mappings, 1, "right:0:1", "7", null);
        AddDefaultMapping(mappings, 1, "right:0:2", "8", null);
        AddDefaultMapping(mappings, 1, "right:0:3", "9", null);
        AddDefaultMapping(mappings, 1, "right:0:4", "None", null);
        AddDefaultMapping(mappings, 1, "right:0:5", "Backspace", null);
        AddDefaultMapping(mappings, 1, "right:1:0", "EmDash", null);
        AddDefaultMapping(mappings, 1, "right:1:1", "4", null);
        AddDefaultMapping(mappings, 1, "right:1:2", "5", null);
        AddDefaultMapping(mappings, 1, "right:1:3", "6", null);
        AddDefaultMapping(mappings, 1, "right:1:4", "None", null);
        AddDefaultMapping(mappings, 1, "right:1:5", "None", null);
        AddDefaultMapping(mappings, 1, "right:2:0", "=", null);
        AddDefaultMapping(mappings, 1, "right:2:1", "1", null);
        AddDefaultMapping(mappings, 1, "right:2:2", "2", null);
        AddDefaultMapping(mappings, 1, "right:2:3", "3", null);
        AddDefaultMapping(mappings, 1, "right:2:4", ".", null);
        AddDefaultMapping(mappings, 1, "right:2:5", "None", null);
    }

    private static void AddDefaultMapping(
        Dictionary<int, Dictionary<string, KeyMapping>> mappings,
        int layer,
        string storageKey,
        string primary,
        string? hold)
    {
        int clampedLayer = Math.Clamp(layer, 0, 7);
        if (!mappings.TryGetValue(clampedLayer, out Dictionary<string, KeyMapping>? layerMap))
        {
            layerMap = new Dictionary<string, KeyMapping>();
            mappings[clampedLayer] = layerMap;
        }

        layerMap[storageKey] = new KeyMapping
        {
            Primary = new KeyAction { Label = primary },
            Hold = hold == null ? null : new KeyAction { Label = hold }
        };
    }

    private static Dictionary<int, Dictionary<string, KeyMapping>> NormalizeMappings(Dictionary<int, Dictionary<string, KeyMapping>>? mappings)
    {
        Dictionary<int, Dictionary<string, KeyMapping>> normalized = CreateEmptyMappings();
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
            Mappings = BuildDefaultMappingsForLayout(layoutKey),
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

        // Default 6x3 starter layout mirrors the current tuned Layer 0/1 configuration.
        List<CustomButton> layer0 = new(3)
        {
            new CustomButton
            {
                Id = "default-right-0",
                Side = TrackpadSide.Right,
                Rect = NormalizeRect(0.0, 75.0, 40.0, 40.0, mirrored: false),
                Primary = new KeyAction { Label = "Space" },
                Hold = null,
                Layer = 0
            },
            new CustomButton
            {
                Id = "default-left-0",
                Side = TrackpadSide.Left,
                Rect = NormalizeRect(0.0, 75.0, 40.0, 40.0, mirrored: true),
                Primary = new KeyAction { Label = "Back" },
                Hold = null,
                Layer = 0
            },
            new CustomButton
            {
                Id = "default-left-1",
                Side = TrackpadSide.Left,
                Rect = NormalizeRect(40.0, 85.0, 40.0, 30.0, mirrored: true),
                Primary = new KeyAction { Label = "MO(1)" },
                Hold = null,
                Layer = 0
            }
        };
        defaults[0] = layer0;

        List<CustomButton> layer1 = new(3)
        {
            new CustomButton
            {
                Id = "default-layer1-right-space",
                Side = TrackpadSide.Right,
                Rect = NormalizeRect(0.0, 75.0, 40.0, 40.0, mirrored: false),
                Primary = new KeyAction { Label = "Space" },
                Hold = null,
                Layer = 1
            },
            new CustomButton
            {
                Id = "default-layer1-left-space",
                Side = TrackpadSide.Left,
                Rect = NormalizeRect(0.0, 75.0, 40.0, 40.0, mirrored: true),
                Primary = new KeyAction { Label = "Space" },
                Hold = null,
                Layer = 1
            },
            new CustomButton
            {
                Id = "default-layer1-right-zero",
                Side = TrackpadSide.Right,
                Rect = ClampCustomButtonRect(new NormalizedRect(0.30, 0.67, 0.27, 0.20)),
                Primary = new KeyAction { Label = "0" },
                Hold = null,
                Layer = 1
            }
        };
        defaults[1] = layer1;
        return defaults;
    }

    private void ApplyFrom(KeymapStore source)
    {
        _layouts.Clear();
        foreach (KeyValuePair<string, LayoutKeymapData> entry in source._layouts)
        {
            _layouts[entry.Key] = entry.Value;
        }

        _activeLayoutKey = source._activeLayoutKey;
        EnsureLayoutData(_activeLayoutKey);
    }

    private string Serialize(bool writeIndented)
    {
        var options = new JsonSerializerOptions { WriteIndented = writeIndented };
        KeymapFileModel file = new()
        {
            Version = 2,
            Layouts = _layouts
        };
        return JsonSerializer.Serialize(file, options);
    }

    private static bool TryCreateFromJson(string json, bool allowEmpty, out KeymapStore store)
    {
        store = CreateDefault(includeCustomDefaults: true);
        if (string.IsNullOrWhiteSpace(json))
        {
            return allowEmpty;
        }

        try
        {
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
                return true;
            }

            Dictionary<int, Dictionary<string, KeyMapping>>? legacyMappings =
                JsonSerializer.Deserialize<Dictionary<int, Dictionary<string, KeyMapping>>>(json);
            if (legacyMappings == null)
            {
                return false;
            }

            store._layouts[DefaultLayoutKey] = new LayoutKeymapData
            {
                Mappings = NormalizeMappings(legacyMappings),
                CustomButtons = BuildDefaultCustomButtons(DefaultLayoutKey)
            };
            store.SetActiveLayout(DefaultLayoutKey);
            return true;
        }
        catch
        {
            store = CreateDefault(includeCustomDefaults: true);
            return false;
        }
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
        public Dictionary<int, Dictionary<string, KeyMapping>> Mappings { get; set; } = CreateEmptyMappings();
        public Dictionary<int, List<CustomButton>> CustomButtons { get; set; } = new();
    }
}
