using Microsoft.Win32.SafeHandles;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux.Uinput;

public sealed class LinuxUinputPermissionProbe
{
    private static readonly string[] CandidateDeviceNodes =
    [
        "/dev/uinput",
        "/dev/input/uinput"
    ];

    public LinuxUinputAccessStatus Probe()
    {
        string deviceNode = CandidateDeviceNodes[0];
        for (int index = 0; index < CandidateDeviceNodes.Length; index++)
        {
            if (File.Exists(CandidateDeviceNodes[index]))
            {
                deviceNode = CandidateDeviceNodes[index];
                break;
            }
        }

        if (!File.Exists(deviceNode))
        {
            return new LinuxUinputAccessStatus(
                DeviceNode: deviceNode,
                DevicePresent: false,
                CanOpenReadWrite: false,
                AccessError: "missing",
                Guidance: "Load the uinput kernel module and install a targeted udev rule for the GlassToKey virtual device.");
        }

        try
        {
            using SafeFileHandle _ = File.OpenHandle(deviceNode, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite);
            return new LinuxUinputAccessStatus(
                DeviceNode: deviceNode,
                DevicePresent: true,
                CanOpenReadWrite: true,
                AccessError: "ok",
                Guidance: "uinput is present and writable.");
        }
        catch (Exception ex)
        {
            return new LinuxUinputAccessStatus(
                DeviceNode: deviceNode,
                DevicePresent: true,
                CanOpenReadWrite: false,
                AccessError: ex.Message,
                Guidance: "Grant rw access to the chosen uinput node through packaging, ideally with a dedicated udev rule instead of broad group membership.");
        }
    }
}
