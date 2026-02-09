using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using WinForms = System.Windows.Forms;

namespace AmtPtpVisualizer;

internal sealed class StatusTrayController : IDisposable
{
    private readonly WinForms.NotifyIcon _notifyIcon;
    private readonly WinForms.ToolStripMenuItem _openItem;
    private readonly WinForms.ToolStripMenuItem _exitItem;
    private readonly WinForms.ContextMenuStrip _menu;
    private readonly Icon _iconUnknown;
    private readonly Icon _iconMouse;
    private readonly Icon _iconMixed;
    private readonly Icon _iconKeyboard;
    private readonly Icon _iconLayerActive;
    private RuntimeModeIndicator _currentMode = RuntimeModeIndicator.Unknown;

    public StatusTrayController(Action openConfig, Action exitApplication)
    {
        _menu = new WinForms.ContextMenuStrip();
        _openItem = new WinForms.ToolStripMenuItem("Open Config", null, (_, _) => openConfig());
        _exitItem = new WinForms.ToolStripMenuItem("Exit", null, (_, _) => exitApplication());
        _menu.Items.Add(_openItem);
        _menu.Items.Add(new WinForms.ToolStripSeparator());
        _menu.Items.Add(_exitItem);

        _iconUnknown = CreateCircleIcon(Color.FromArgb(107, 114, 121));
        _iconMouse = CreateCircleIcon(Color.FromArgb(231, 76, 60));
        _iconMixed = CreateCircleIcon(Color.FromArgb(46, 204, 113));
        _iconKeyboard = CreateCircleIcon(Color.FromArgb(155, 89, 182));
        _iconLayerActive = CreateCircleIcon(Color.FromArgb(52, 152, 219));

        _notifyIcon = new WinForms.NotifyIcon
        {
            Text = "AmtPtp Status App (Unknown)",
            Icon = _iconUnknown,
            Visible = true,
            ContextMenuStrip = _menu
        };

        _notifyIcon.DoubleClick += (_, _) => openConfig();
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _iconUnknown.Dispose();
        _iconMouse.Dispose();
        _iconMixed.Dispose();
        _iconKeyboard.Dispose();
        _iconLayerActive.Dispose();
        _menu.Dispose();
    }

    public void SetModeIndicator(RuntimeModeIndicator mode)
    {
        if (_currentMode == mode)
        {
            return;
        }

        _currentMode = mode;
        _notifyIcon.Icon = mode switch
        {
            RuntimeModeIndicator.Mouse => _iconMouse,
            RuntimeModeIndicator.Mixed => _iconMixed,
            RuntimeModeIndicator.Keyboard => _iconKeyboard,
            RuntimeModeIndicator.LayerActive => _iconLayerActive,
            _ => _iconUnknown
        };
        _notifyIcon.Text = mode switch
        {
            RuntimeModeIndicator.Mouse => "AmtPtp Status App (Mouse)",
            RuntimeModeIndicator.Mixed => "AmtPtp Status App (Mixed)",
            RuntimeModeIndicator.Keyboard => "AmtPtp Status App (Keyboard)",
            RuntimeModeIndicator.LayerActive => "AmtPtp Status App (Layer Active)",
            _ => "AmtPtp Status App (Unknown)"
        };
    }

    private static Icon CreateCircleIcon(Color color)
    {
        using Bitmap bitmap = new(16, 16);
        using (Graphics graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.Clear(Color.Transparent);
            using SolidBrush fill = new(color);
            using Pen outline = new(Color.FromArgb(204, 12, 14, 16), 1f);
            graphics.FillEllipse(fill, 2f, 2f, 12f, 12f);
            graphics.DrawEllipse(outline, 2f, 2f, 12f, 12f);
        }

        IntPtr hIcon = bitmap.GetHicon();
        try
        {
            using Icon raw = Icon.FromHandle(hIcon);
            return (Icon)raw.Clone();
        }
        finally
        {
            _ = DestroyIcon(hIcon);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);
}
