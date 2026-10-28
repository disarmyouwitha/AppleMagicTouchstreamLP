namespace GlassToKey.Linux.Runtime;

public sealed record LinuxInputPreviewSnapshot(
    LinuxInputPreviewStatus Status,
    string Message,
    string? Failure,
    IReadOnlyList<LinuxInputPreviewTrackpadState> Trackpads)
{
    public bool IsActive => Status is LinuxInputPreviewStatus.Starting or LinuxInputPreviewStatus.Running or LinuxInputPreviewStatus.Stopping;
}
