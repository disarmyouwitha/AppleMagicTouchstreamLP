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
    private const string DefaultKeymapFileName = "GLASSTOKEY_DEFAULT_KEYMAP.json";
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

    public static string GetDefaultKeymapPath()
    {
        return Path.Combine(AppContext.BaseDirectory, DefaultKeymapFileName);
    }

    public static KeymapStore Load()
    {
        try
        {
            string userPath = GetKeymapPath();
            if (File.Exists(userPath))
            {
                string userJson = File.ReadAllText(userPath);
                if (TryCreateFromJson(userJson, allowEmpty: true, out KeymapStore userStore))
                {
                    return userStore;
                }
            }
        }
        catch
        {
            // Fall through to bundled-default/empty path.
        }

        return LoadBundledDefault();
    }

    public static KeymapStore LoadBundledDefault()
    {
        try
        {
            string defaultPath = GetDefaultKeymapPath();
            if (File.Exists(defaultPath))
            {
                string defaultJson = File.ReadAllText(defaultPath);
                if (TryCreateFromBundledDefaultJson(defaultJson, out KeymapStore defaultStore))
                {
                    return defaultStore;
                }
            }
        }
        catch
        {
            // Fall back to empty keymap.
        }

        return CreateEmptyStore();
    }

    private static KeymapStore CreateEmptyStore()
    {
        KeymapStore store = new();
        store._layouts[DefaultLayoutKey] = new LayoutKeymapData
        {
            Mappings = CreateEmptyMappings(),
            CustomButtons = new Dictionary<int, List<CustomButton>>()
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

    public string SerializeToJson(bool writeIndented = true)
    {
        return Serialize(writeIndented);
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

    public void EnsureLayoutExists(string? layoutKey)
    {
        if (string.IsNullOrWhiteSpace(layoutKey))
        {
            return;
        }

        EnsureLayoutData(layoutKey.Trim());
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
            Mappings = CreateEmptyMappings(),
            CustomButtons = new Dictionary<int, List<CustomButton>>()
        };
        _layouts[layoutKey] = created;
        return created;
    }

    private static LayoutKeymapData NormalizeLayoutData(LayoutKeymapData source)
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
        store = CreateEmptyStore();
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

                        store._layouts[entry.Key] = NormalizeLayoutData(entry.Value);
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
                CustomButtons = new Dictionary<int, List<CustomButton>>()
            };
            store.SetActiveLayout(DefaultLayoutKey);
            return true;
        }
        catch
        {
            store = CreateEmptyStore();
            return false;
        }
    }

    private static bool TryCreateFromBundledDefaultJson(string json, out KeymapStore store)
    {
        if (TryCreateFromJson(json, allowEmpty: false, out store))
        {
            return true;
        }

        try
        {
            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !TryGetPropertyIgnoreCase(root, "KeymapJson", out JsonElement keymapJsonElement) ||
                keymapJsonElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            string? keymapJson = keymapJsonElement.GetString();
            if (string.IsNullOrWhiteSpace(keymapJson))
            {
                return false;
            }

            return TryCreateFromJson(keymapJson, allowEmpty: false, out store);
        }
        catch
        {
            store = CreateEmptyStore();
            return false;
        }
    }

    private static double ClampRange(double value, double min, double max)
    {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    private static bool HasPropertyIgnoreCase(JsonElement element, string propertyName)
    {
        return TryGetPropertyIgnoreCase(element, propertyName, out _);
    }

    private static bool TryGetPropertyIgnoreCase(JsonElement element, string propertyName, out JsonElement value)
    {
        foreach (JsonProperty property in element.EnumerateObject())
        {
            if (string.Equals(property.Name, propertyName, StringComparison.OrdinalIgnoreCase))
            {
                value = property.Value;
                return true;
            }
        }

        value = default;
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

