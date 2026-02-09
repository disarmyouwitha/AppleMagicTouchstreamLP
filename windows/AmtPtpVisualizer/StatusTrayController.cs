using System;
using System.Drawing;
using WinForms = System.Windows.Forms;

namespace AmtPtpVisualizer;

internal sealed class StatusTrayController : IDisposable
{
    private readonly WinForms.NotifyIcon _notifyIcon;
    private readonly WinForms.ToolStripMenuItem _openItem;
    private readonly WinForms.ToolStripMenuItem _exitItem;
    private readonly WinForms.ContextMenuStrip _menu;

    public StatusTrayController(Action openConfig, Action exitApplication)
    {
        _menu = new WinForms.ContextMenuStrip();
        _openItem = new WinForms.ToolStripMenuItem("Open Config", null, (_, _) => openConfig());
        _exitItem = new WinForms.ToolStripMenuItem("Exit", null, (_, _) => exitApplication());
        _menu.Items.Add(_openItem);
        _menu.Items.Add(new WinForms.ToolStripSeparator());
        _menu.Items.Add(_exitItem);

        _notifyIcon = new WinForms.NotifyIcon
        {
            Text = "AmtPtp Status App",
            Icon = SystemIcons.Application,
            Visible = true,
            ContextMenuStrip = _menu
        };

        _notifyIcon.DoubleClick += (_, _) => openConfig();
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
    }
}
