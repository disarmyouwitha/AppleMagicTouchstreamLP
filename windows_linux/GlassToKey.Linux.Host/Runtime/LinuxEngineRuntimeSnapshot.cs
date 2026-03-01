using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Linux.Runtime;

public sealed record LinuxEngineRuntimeSnapshot(
    LinuxEngineRuntimeStatus Status,
    string Message,
    string? Failure,
    IReadOnlyList<LinuxRuntimeBindingState> BindingStates)
{
    public bool IsActive => Status is LinuxEngineRuntimeStatus.Starting or LinuxEngineRuntimeStatus.Running or LinuxEngineRuntimeStatus.Stopping;
}
