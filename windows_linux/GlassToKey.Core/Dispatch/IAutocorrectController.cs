namespace GlassToKey;

public interface IAutocorrectController
{
    void SetAutocorrectEnabled(bool enabled);
    void ConfigureAutocorrectOptions(AutocorrectOptions options);
    void NotifyPointerActivity();
    void ForceAutocorrectReset(string reason);
    AutocorrectStatusSnapshot GetAutocorrectStatus();
}
