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

public sealed class KeymapStore
{
    public Dictionary<int, Dictionary<string, KeyMapping>> Mappings { get; private set; } = new();

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
                return new KeymapStore { Mappings = DefaultMappings() };
            }

            string json = File.ReadAllText(path);
            Dictionary<int, Dictionary<string, KeyMapping>>? mappings = JsonSerializer.Deserialize<Dictionary<int, Dictionary<string, KeyMapping>>>(json);
            return new KeymapStore { Mappings = mappings ?? DefaultMappings() };
        }
        catch
        {
            return new KeymapStore { Mappings = DefaultMappings() };
        }
    }

    public static KeymapStore CreateDefault()
    {
        return new KeymapStore { Mappings = DefaultMappings() };
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
            string json = JsonSerializer.Serialize(Mappings, options);
            File.WriteAllText(path, json);
        }
        catch
        {
            // Best-effort persistence.
        }
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

    private static Dictionary<int, Dictionary<string, KeyMapping>> DefaultMappings()
    {
        return new Dictionary<int, Dictionary<string, KeyMapping>>
        {
            [0] = new Dictionary<string, KeyMapping>(),
            [1] = new Dictionary<string, KeyMapping>()
        };
    }
}
