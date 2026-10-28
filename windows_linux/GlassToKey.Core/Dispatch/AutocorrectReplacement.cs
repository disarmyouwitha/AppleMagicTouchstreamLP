namespace GlassToKey;

public readonly record struct AutocorrectReplacement(
    int BackspaceCount,
    string ReplacementText);
