namespace GlassToKey;

public readonly record struct TouchProcessorRuntimeSnapshot(
    int ActiveLayer,
    bool TypingEnabled,
    bool KeyboardModeEnabled,
    int ContactCount,
    int LeftContacts,
    int RightContacts);
