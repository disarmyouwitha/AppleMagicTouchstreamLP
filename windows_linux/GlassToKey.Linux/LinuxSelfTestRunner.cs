using System.Text.Json;
using GlassToKey.Platform.Linux.Uinput;

namespace GlassToKey.Linux;

internal readonly record struct LinuxSelfTestResult(bool Success, string Message);

internal static class LinuxSelfTestRunner
{
    private static readonly string[] ForbiddenBundledLabels =
    [
        "EMOJI",
        "VOICE",
        "LWin",
        "RWin",
        "Win+H"
    ];

    public static LinuxSelfTestResult Run()
    {
        if (!TryLoadBundledKeymap(out KeymapStore.KeymapFileModel keymap, out string failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateBundledTranslations(keymap, out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateResolvedMappings(keymap, out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        if (!ValidateSemanticAliases(out failure))
        {
            return new LinuxSelfTestResult(false, failure);
        }

        return new LinuxSelfTestResult(true, "Linux self-tests passed.");
    }

    private static bool TryLoadBundledKeymap(out KeymapStore.KeymapFileModel keymap, out string failure)
    {
        keymap = new KeymapStore.KeymapFileModel();
        failure = string.Empty;

        string path = Path.Combine(AppContext.BaseDirectory, "GLASSTOKEY_DEFAULT_KEYMAP.json");
        if (!File.Exists(path))
        {
            failure = $"Bundled Linux keymap is missing: {path}";
            return false;
        }

        try
        {
            using JsonDocument document = JsonDocument.Parse(File.ReadAllText(path));
            if (!document.RootElement.TryGetProperty("KeymapJson", out JsonElement keymapJsonElement) ||
                keymapJsonElement.ValueKind != JsonValueKind.String)
            {
                failure = "Bundled Linux keymap is missing KeymapJson.";
                return false;
            }

            string? keymapJson = keymapJsonElement.GetString();
            if (string.IsNullOrWhiteSpace(keymapJson))
            {
                failure = "Bundled Linux keymap KeymapJson is empty.";
                return false;
            }

            KeymapStore store = new();
            if (!store.TryImportFromJson(keymapJson, out string importFailure))
            {
                failure = $"Bundled Linux keymap did not import: {importFailure}";
                return false;
            }

            KeymapStore.KeymapFileModel? model = JsonSerializer.Deserialize<KeymapStore.KeymapFileModel>(
                keymapJson,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (model?.Layouts == null || model.Layouts.Count == 0)
            {
                failure = "Bundled Linux keymap contains no layouts.";
                return false;
            }

            keymap = model;
            return true;
        }
        catch (Exception ex)
        {
            failure = $"Bundled Linux keymap parse failed: {ex.Message}";
            return false;
        }
    }

    private static bool ValidateBundledTranslations(KeymapStore.KeymapFileModel keymap, out string failure)
    {
        foreach (string label in EnumerateActionLabels(keymap))
        {
            for (int index = 0; index < ForbiddenBundledLabels.Length; index++)
            {
                if (string.Equals(label, ForbiddenBundledLabels[index], StringComparison.OrdinalIgnoreCase))
                {
                    failure = $"Bundled Linux keymap still contains Windows-specific label '{label}'.";
                    return false;
                }
            }
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateResolvedMappings(KeymapStore.KeymapFileModel keymap, out string failure)
    {
        foreach (string label in EnumerateActionLabels(keymap))
        {
            EngineKeyAction action = EngineActionResolver.ResolveActionLabel(label, "None");
            if (!ValidateResolvedAction(label, action, out failure))
            {
                return false;
            }
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateSemanticAliases(out string failure)
    {
        if (!ValidateSemanticAlias("VOL_UP", DispatchSemanticCode.VolumeUp, LinuxEvdevCodes.KeyVolumeUp, out failure) ||
            !ValidateSemanticAlias("VOL_DOWN", DispatchSemanticCode.VolumeDown, LinuxEvdevCodes.KeyVolumeDown, out failure) ||
            !ValidateSemanticAlias("BRIGHT_UP", DispatchSemanticCode.BrightnessUp, LinuxEvdevCodes.KeyBrightnessUp, out failure) ||
            !ValidateSemanticAlias("BRIGHT_DOWN", DispatchSemanticCode.BrightnessDown, LinuxEvdevCodes.KeyBrightnessDown, out failure))
        {
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateSemanticAlias(
        string label,
        DispatchSemanticCode expectedCode,
        ushort expectedLinuxCode,
        out string failure)
    {
        if (!DispatchSemanticResolver.TryResolveKeyCode(label, out DispatchSemanticCode resolvedCode) ||
            resolvedCode != expectedCode)
        {
            failure = $"Label '{label}' did not resolve semantic code '{expectedCode}'.";
            return false;
        }

        EngineKeyAction action = EngineActionResolver.ResolveActionLabel(label, "None");
        if (action.SemanticAction.PrimaryCode != expectedCode)
        {
            failure = $"Label '{label}' did not flow semantic code '{expectedCode}' through action resolution.";
            return false;
        }

        if (!LinuxKeyCodeMapper.TryMapSemanticCode(expectedCode, out ushort linuxCode) ||
            linuxCode != expectedLinuxCode)
        {
            failure = $"Semantic code '{expectedCode}' did not map to Linux code '{expectedLinuxCode}'.";
            return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool ValidateResolvedAction(string label, EngineKeyAction action, out string failure)
    {
        if (action.Kind == EngineActionKind.None)
        {
            if (!string.Equals(label, "None", StringComparison.OrdinalIgnoreCase))
            {
                failure = $"Label '{label}' resolved to None.";
                return false;
            }

            failure = string.Empty;
            return true;
        }

        switch (action.Kind)
        {
            case EngineActionKind.Key:
            case EngineActionKind.Continuous:
            case EngineActionKind.Modifier:
                if (!CanResolveLinuxKey(action.SemanticAction.PrimaryCode, action.VirtualKey))
                {
                    failure = $"Label '{label}' did not resolve to a Linux key code.";
                    return false;
                }

                break;
            case EngineActionKind.KeyChord:
                if (!CanResolveLinuxKey(action.SemanticAction.PrimaryCode, action.VirtualKey))
                {
                    failure = $"Chord '{label}' did not resolve its primary Linux key code.";
                    return false;
                }

                if (!CanResolveLinuxKey(action.SemanticAction.SecondaryCode, action.ModifierVirtualKey))
                {
                    failure = $"Chord '{label}' did not resolve its modifier Linux key code.";
                    return false;
                }

                break;
            case EngineActionKind.MouseButton:
                if (!LinuxKeyCodeMapper.TryMapMouseButton(action.MouseButton, out _))
                {
                    failure = $"Mouse label '{label}' did not resolve to a Linux button.";
                    return false;
                }

                break;
            case EngineActionKind.MomentaryLayer:
            case EngineActionKind.LayerSet:
            case EngineActionKind.LayerToggle:
            case EngineActionKind.TypingToggle:
                break;
            default:
                failure = $"Label '{label}' resolved unexpected action kind '{action.Kind}'.";
                return false;
        }

        failure = string.Empty;
        return true;
    }

    private static bool CanResolveLinuxKey(DispatchSemanticCode semanticCode, ushort virtualKey)
    {
        return (semanticCode != DispatchSemanticCode.None && LinuxKeyCodeMapper.TryMapSemanticCode(semanticCode, out _)) ||
               (virtualKey != 0 && LinuxKeyCodeMapper.TryMapKey(virtualKey, out _));
    }

    private static IEnumerable<string> EnumerateActionLabels(KeymapStore.KeymapFileModel keymap)
    {
        foreach (KeyValuePair<string, KeymapStore.LayoutKeymapData> layoutEntry in keymap.Layouts)
        {
            KeymapStore.LayoutKeymapData layout = layoutEntry.Value;
            if (layout.Mappings != null)
            {
                foreach (KeyValuePair<int, Dictionary<string, KeyMapping>> layerEntry in layout.Mappings)
                {
                    foreach (KeyValuePair<string, KeyMapping> mappingEntry in layerEntry.Value)
                    {
                        KeyMapping mapping = mappingEntry.Value;
                        if (!string.IsNullOrWhiteSpace(mapping.Primary?.Label))
                        {
                            yield return mapping.Primary.Label;
                        }

                        if (!string.IsNullOrWhiteSpace(mapping.Hold?.Label))
                        {
                            yield return mapping.Hold.Label;
                        }
                    }
                }
            }

            if (layout.CustomButtons == null)
            {
                continue;
            }

            foreach (KeyValuePair<int, List<CustomButton>> layerEntry in layout.CustomButtons)
            {
                List<CustomButton> buttons = layerEntry.Value;
                for (int index = 0; index < buttons.Count; index++)
                {
                    CustomButton button = buttons[index];
                    if (!string.IsNullOrWhiteSpace(button.Primary?.Label))
                    {
                        yield return button.Primary.Label;
                    }

                    if (!string.IsNullOrWhiteSpace(button.Hold?.Label))
                    {
                        yield return button.Hold.Label;
                    }
                }
            }
        }
    }
}
