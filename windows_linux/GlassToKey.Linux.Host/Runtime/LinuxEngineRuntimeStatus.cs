namespace GlassToKey.Linux.Runtime;

public enum LinuxEngineRuntimeStatus : byte
{
    Stopped = 0,
    Starting = 1,
    Running = 2,
    Stopping = 3,
    Faulted = 4
}
