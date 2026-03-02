using System.Text;
using GlassToKey.Platform.Linux.Models;

namespace GlassToKey.Platform.Linux.Uinput;

public static class LinuxUdevRuleTemplate
{
    public const string DefaultAccessGroup = "glasstokey";

    public static string BuildRules(IReadOnlyList<LinuxInputDeviceDescriptor> devices)
    {
        HashSet<string> seenPairs = new(StringComparer.OrdinalIgnoreCase);
        StringBuilder builder = new();
        builder.AppendLine("# /etc/udev/rules.d/90-glasstokey.rules");
        builder.AppendLine("# Grant the glasstokey access group ownership of Apple Magic Trackpad event nodes");
        builder.AppendLine("# and the GlassToKey uinput node. Keep uaccess as an additive hint for desktop sessions.");

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
            builder.Append("\", GROUP=\"");
            builder.Append(DefaultAccessGroup);
            builder.AppendLine("\", MODE=\"0660\", TAG+=\"uaccess\"");
        }

        builder.Append("KERNEL==\"uinput\", GROUP=\"");
        builder.Append(DefaultAccessGroup);
        builder.AppendLine("\", MODE=\"0660\", TAG+=\"uaccess\"");
        builder.AppendLine();
        builder.AppendLine("# Reload after install:");
        builder.AppendLine("#   sudo udevadm control --reload-rules");
        builder.AppendLine("#   sudo udevadm trigger");
        builder.AppendLine("#   sudo usermod -aG glasstokey $USER");
        builder.AppendLine("#   log out and back in");
        return builder.ToString();
    }
}
