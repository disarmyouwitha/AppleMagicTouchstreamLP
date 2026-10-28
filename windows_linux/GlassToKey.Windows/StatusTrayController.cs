using System;
using System.Drawing;
using WinForms = System.Windows.Forms;

namespace GlassToKey;

internal sealed class StatusTrayController : IDisposable
{
    private readonly WinForms.NotifyIcon _notifyIcon;
    private readonly WinForms.ToolStripMenuItem _openItem;
    private readonly WinForms.ToolStripMenuItem _captureItem;
    private readonly WinForms.ToolStripMenuItem _replayItem;
    private readonly WinForms.ToolStripMenuItem _restartItem;
    private readonly WinForms.ToolStripMenuItem _exitItem;
    private readonly WinForms.ToolStripMenuItem _releaseMouseTakeoverItem;
    private bool _mouseTakeoverEnabled;
    private readonly WinForms.ContextMenuStrip _menu;
    private readonly Icon _handIcon;

    public StatusTrayController(
        Action openConfig,
        Action startCapture,
        Action startReplay,
        Action restartApplication,
        Action exitApplication,
        Action releaseMouseTakeover)
    {
        _menu = new WinForms.ContextMenuStrip();
        _openItem = new WinForms.ToolStripMenuItem("Config...", null, (_, _) => openConfig());
        _captureItem = new WinForms.ToolStripMenuItem("Capture", null, (_, _) => startCapture());
        _replayItem = new WinForms.ToolStripMenuItem("Replay", null, (_, _) => startReplay());
        _restartItem = new WinForms.ToolStripMenuItem("Restart", null, (_, _) => restartApplication());
        _exitItem = new WinForms.ToolStripMenuItem("Exit", null, (_, _) => exitApplication());
        _releaseMouseTakeoverItem = new WinForms.ToolStripMenuItem("Release Mouse Takeover (Ctrl+Alt+R)", null, (_, _) => releaseMouseTakeover()) { Enabled = false };
        _menu.Items.Add(_openItem);
        _menu.Items.Add(_releaseMouseTakeoverItem);
        _menu.Items.Add(new WinForms.ToolStripSeparator());
        _menu.Items.Add(_captureItem);
        _menu.Items.Add(_replayItem);
        _menu.Items.Add(new WinForms.ToolStripSeparator());
        _menu.Items.Add(_restartItem);
        _menu.Items.Add(_exitItem);

        _handIcon = ApplicationHandIcon.CreateTrayIcon();

        _notifyIcon = new WinForms.NotifyIcon
        {
            Text = "GlassToKey",
            Icon = _handIcon,
            Visible = true,
            ContextMenuStrip = _menu
        };

        _notifyIcon.DoubleClick += (_, _) => openConfig();
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _handIcon.Dispose();
        _menu.Dispose();
    }

    public void SetMouseTakeoverIndicator(bool enabled)
    {
        _mouseTakeoverEnabled = enabled;
        UpdateTakeoverStatus();
    }

    private void UpdateTakeoverStatus()
    {
        _releaseMouseTakeoverItem.Enabled = _mouseTakeoverEnabled;
        _notifyIcon.Text = "GlassToKey" + (_mouseTakeoverEnabled ? " · Mouse Takeover ON" : string.Empty);
    }

}
