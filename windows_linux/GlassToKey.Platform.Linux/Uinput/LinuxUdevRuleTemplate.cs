using System.Text;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux.Uinput;

public static class LinuxUdevRuleTemplate
{
    public static string BuildRules(IReadOnlyList<LinuxInputDeviceDescriptor> devices)
    {
        HashSet<string> seenPairs = new(StringComparer.OrdinalIgnoreCase);
        StringBuilder builder = new();
        builder.AppendLine("# /etc/udev/rules.d/90-glasstokey.rules");
        builder.AppendLine("# Grant the active desktop user access to Apple Magic Trackpad event nodes and the GlassToKey uinput node.");

        for (int index = 0; index < devices.Count; index++)
        {
            LinuxInputDeviceDescriptor device = devices[index];
            string pair = $"{device.VendorId:x4}:{device.ProductId:x4}";
            if (!seenPairs.Add(pair))
            {
                continue;
            }

            builder.Append("SUBSYSTEM==\"input\", KERNEL==\"event*\", ATTRS{id/vendor}==\"");
            builder.Append(device.VendorId.ToString("x4"));
            builder.Append("\", ATTRS{id/product}==\"");
            builder.Append(device.ProductId.ToString("x4"));
            builder.AppendLine("\", TAG+=\"uaccess\"");
        }

        builder.AppendLine("KERNEL==\"uinput\", MODE=\"0660\", TAG+=\"uaccess\"");
        builder.AppendLine();
        builder.AppendLine("# Reload after install:");
        builder.AppendLine("#   sudo udevadm control --reload-rules");
        builder.AppendLine("#   sudo udevadm trigger");
        return builder.ToString();
    }
}
