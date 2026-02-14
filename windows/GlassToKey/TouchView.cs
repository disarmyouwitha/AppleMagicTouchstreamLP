using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace GlassToKey;

public sealed class TouchView : FrameworkElement
{
    public TouchState? State { get; set; }
    public ushort? RequestedMaxX { get; set; }
    public ushort? RequestedMaxY { get; set; }
    public double TrackpadWidthMm { get; set; } = 160.0;
    public double TrackpadHeightMm { get; set; } = 114.9;
    public string? EmptyMessage { get; set; }
    public KeyLayout? Layout { get; set; }
    public NormalizedRect? HighlightedKey { get; set; }
    public NormalizedRect? SelectedKey { get; set; }
    public SurfaceCustomButton[] CustomButtons { get; set; } = Array.Empty<SurfaceCustomButton>();
    public string? HighlightedCustomButtonId { get; set; }
    public string? SelectedCustomButtonId { get; set; }
    public string[][]? LabelMatrix { get; set; }
    public string LastHitLabel { get; set; } = "--";
    public string ClickLabel { get; set; } = "--";
    public bool ShowPressureValues { get; set; } = true;

    private readonly Pen _borderPen = new(new SolidColorBrush(Color.FromRgb(56, 62, 69)), 2);
    private readonly Brush _canvasBrush = new SolidColorBrush(Color.FromRgb(12, 15, 18));
    private readonly Brush _padBrush = new SolidColorBrush(Color.FromRgb(15, 19, 23));
    private readonly Brush _gridBrush = new SolidColorBrush(Color.FromRgb(20, 24, 28));
    private readonly Pen _gridPen;
    private readonly Brush _tipBrush = new SolidColorBrush(Color.FromRgb(60, 196, 110));
    private readonly Brush _textBrush = new SolidColorBrush(Color.FromRgb(220, 225, 230));
    private readonly Brush _keyStrokeBrush = new SolidColorBrush(Color.FromRgb(100, 108, 116));
    private readonly Pen _keyStrokePen;
    private readonly Brush _keyFillBrush = new SolidColorBrush(Color.FromRgb(14, 18, 22));
    private readonly Brush _hitFillBrush = new SolidColorBrush(Color.FromRgb(20, 80, 40));
    private readonly Brush _hitStrokeBrush = new SolidColorBrush(Color.FromRgb(90, 210, 130));
    private readonly Pen _hitStrokePen;
    private readonly Brush _selectedFillBrush = new SolidColorBrush(Color.FromRgb(18, 64, 120));
    private readonly Brush _selectedStrokeBrush = new SolidColorBrush(Color.FromRgb(90, 170, 255));
    private readonly Pen _selectedStrokePen;
    private readonly Brush _customFillBrush = new SolidColorBrush(Color.FromRgb(26, 33, 40));
    private readonly Brush _customStrokeBrush = new SolidColorBrush(Color.FromRgb(112, 122, 130));
    private readonly Pen _customStrokePen;
    private readonly Brush _customHitFillBrush = new SolidColorBrush(Color.FromRgb(25, 96, 50));
    private readonly Brush _customHitStrokeBrush = new SolidColorBrush(Color.FromRgb(95, 220, 140));
    private readonly Pen _customHitStrokePen;
    private readonly Brush _customSelectedFillBrush = new SolidColorBrush(Color.FromRgb(24, 74, 136));
    private readonly Brush _customSelectedStrokeBrush = new SolidColorBrush(Color.FromRgb(110, 186, 255));
    private readonly Pen _customSelectedStrokePen;
    private readonly Brush _messageBrush = new SolidColorBrush(Color.FromRgb(120, 128, 136));
    private readonly Brush _footerBrush = new SolidColorBrush(Color.FromRgb(150, 156, 162));
    private readonly Typeface _uiTypeface = new("Segoe UI");
    private readonly Typeface _monoTypeface = new("Consolas");

    public TouchView()
    {
        SnapsToDevicePixels = true;
        Focusable = false;
        _gridPen = new Pen(_gridBrush, 1);
        _keyStrokePen = new Pen(_keyStrokeBrush, 1);
        _hitStrokePen = new Pen(_hitStrokeBrush, 1.5);
        _selectedStrokePen = new Pen(_selectedStrokeBrush, 1.8);
        _customStrokePen = new Pen(_customStrokeBrush, 1.1);
        _customHitStrokePen = new Pen(_customHitStrokeBrush, 1.6);
        _customSelectedStrokePen = new Pen(_customSelectedStrokeBrush, 1.9);
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);

        double width = ActualWidth;
        double height = ActualHeight;
        if (width <= 1 || height <= 1)
        {
            return;
        }

        Rect bounds = new Rect(0, 0, width, height);
        dc.DrawRectangle(_canvasBrush, null, bounds);

        DrawGrid(dc, bounds);
        DrawSurface(dc, bounds);
    }

    private void DrawGrid(DrawingContext dc, Rect bounds)
    {
        int cols = 8;
        int rows = 5;

        for (int i = 1; i < cols; i++)
        {
            double x = bounds.Left + bounds.Width * i / cols;
            dc.DrawLine(_gridPen, new Point(x, bounds.Top), new Point(x, bounds.Bottom));
        }

        for (int i = 1; i < rows; i++)
        {
            double y = bounds.Top + bounds.Height * i / rows;
            dc.DrawLine(_gridPen, new Point(bounds.Left, y), new Point(bounds.Right, y));
        }
    }

    private void DrawSurface(DrawingContext dc, Rect bounds)
    {
        if (State == null)
        {
            return;
        }

        Span<TouchContact> contacts = stackalloc TouchContact[PtpReport.MaxContacts];
        int contactCount = State.Snapshot(contacts, out ushort maxX, out ushort maxY, out PressureCapability pressureCapability);

        if (RequestedMaxX.HasValue) maxX = RequestedMaxX.Value;
        if (RequestedMaxY.HasValue) maxY = RequestedMaxY.Value;
        if (maxX == 0) maxX = 1;
        if (maxY == 0) maxY = 1;

        Rect pad = CreatePadRect(bounds);
        dc.DrawRoundedRectangle(_padBrush, _borderPen, pad, 14, 14);

        DrawKeyGrid(dc, pad);
        DrawCustomButtons(dc, pad);
        for (int i = 0; i < contactCount; i++)
        {
            TouchContact c = contacts[i];
            double x = pad.Left + (c.X / (double)maxX) * pad.Width;
            double y = pad.Top + (c.Y / (double)maxY) * pad.Height;

            dc.DrawEllipse(_tipBrush, null, new Point(x, y), 20, 20);

            if (ShowPressureValues && pressureCapability != PressureCapability.Unsupported)
            {
                FormattedText idText = new(
                    c.Id.ToString(CultureInfo.InvariantCulture),
                    CultureInfo.InvariantCulture,
                    FlowDirection.LeftToRight,
                    _uiTypeface,
                    10,
                    _textBrush,
                    1.0);
                FormattedText pressureText = new(
                    $"fn:{c.ForceNorm}",
                    CultureInfo.InvariantCulture,
                    FlowDirection.LeftToRight,
                    _monoTypeface,
                    9,
                    _textBrush,
                    1.0);
                double spacing = 1.0;
                double startY = y - ((idText.Height + pressureText.Height + spacing) / 2);
                dc.DrawText(idText, new Point(x - (idText.Width / 2), startY));
                dc.DrawText(pressureText, new Point(x - (pressureText.Width / 2), startY + idText.Height + spacing));
            }
            else
            {
                FormattedText idText = new(
                    c.Id.ToString(CultureInfo.InvariantCulture),
                    CultureInfo.InvariantCulture,
                    FlowDirection.LeftToRight,
                    _uiTypeface,
                    10,
                    _textBrush,
                    1.0);
                dc.DrawText(idText, new Point(x - (idText.Width / 2), y - (idText.Height / 2)));
            }
        }

        if (contactCount == 0)
        {
            string message = EmptyMessage ?? string.Empty;
            FormattedText text = new(
                message,
                CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                _uiTypeface,
                14,
                _messageBrush,
                1.0);
            dc.DrawText(text, new Point(pad.Left + 18, pad.Top + 18));
        }

        string footer = $"Contacts: {contactCount}";
        FormattedText footerLeft = new(
            footer,
            CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight,
            _uiTypeface,
            12,
            _footerBrush,
            1.0);
        dc.DrawText(footerLeft, new Point(pad.Left + 18, pad.Bottom - 24));

        string hitText = $"Last hit: {LastHitLabel}";
        FormattedText footerRight = new(
            hitText,
            CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight,
            _uiTypeface,
            12,
            _footerBrush,
            1.0);

        string clickText = $"Pressed: {ClickLabel}";
        FormattedText footerClick = new(
            clickText,
            CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight,
            _uiTypeface,
            12,
            _footerBrush,
            1.0);

        const double rightPadding = 18;
        const double footerGap = 14;
        double footerY = pad.Bottom - 24;
        double hitX = pad.Right - footerRight.Width - rightPadding;
        double clickX = hitX - footerClick.Width - footerGap;
        dc.DrawText(footerClick, new Point(clickX, footerY));
        dc.DrawText(footerRight, new Point(hitX, footerY));
    }

    private void DrawKeyGrid(DrawingContext dc, Rect pad)
    {
        if (Layout == null || Layout.Rects.Length == 0)
        {
            return;
        }

        for (int row = 0; row < Layout.Rects.Length; row++)
        {
            NormalizedRect[] rowRects = Layout.Rects[row];
            for (int col = 0; col < rowRects.Length; col++)
            {
                Rect rect = rowRects[col].ToRect(pad);
                dc.DrawRoundedRectangle(_keyFillBrush, _keyStrokePen, rect, 6, 6);

                if (HighlightedKey.HasValue && RectEquals(rowRects[col], HighlightedKey.Value))
                {
                    dc.DrawRoundedRectangle(_hitFillBrush, _hitStrokePen, rect, 6, 6);
                }
                if (SelectedKey.HasValue && RectEquals(rowRects[col], SelectedKey.Value))
                {
                    dc.DrawRoundedRectangle(_selectedFillBrush, _selectedStrokePen, rect, 6, 6);
                }

                if (LabelMatrix != null && row < LabelMatrix.Length && col < LabelMatrix[row].Length)
                {
                    string label = LabelMatrix[row][col];
                    int split = label.IndexOf('\n');
                    if (split > 0 && split < label.Length - 1)
                    {
                        string primary = label.Substring(0, split);
                        string hold = label.Substring(split + 1);

                        FormattedText primaryText = new(
                            primary,
                            CultureInfo.InvariantCulture,
                            FlowDirection.LeftToRight,
                            _monoTypeface,
                            10,
                            _textBrush,
                            1.0);
                        dc.DrawText(primaryText, new Point(rect.Left + (rect.Width - primaryText.Width) / 2, rect.Top + (rect.Height - primaryText.Height) / 2));

                        FormattedText holdText = new(
                            hold,
                            CultureInfo.InvariantCulture,
                            FlowDirection.LeftToRight,
                            _monoTypeface,
                            8,
                            _textBrush,
                            1.0);
                        dc.DrawText(holdText, new Point(rect.Left + (rect.Width - holdText.Width) / 2, rect.Bottom - holdText.Height - 2));
                    }
                    else
                    {
                        FormattedText text = new(
                            label,
                            CultureInfo.InvariantCulture,
                            FlowDirection.LeftToRight,
                            _monoTypeface,
                            10,
                            _textBrush,
                            1.0);
                        dc.DrawText(text, new Point(rect.Left + (rect.Width - text.Width) / 2, rect.Top + (rect.Height - text.Height) / 2));
                    }
                }
            }
        }
    }

    private void DrawCustomButtons(DrawingContext dc, Rect pad)
    {
        if (CustomButtons == null || CustomButtons.Length == 0)
        {
            return;
        }

        for (int i = 0; i < CustomButtons.Length; i++)
        {
            SurfaceCustomButton button = CustomButtons[i];
            Rect rect = button.Rect.ToRect(pad);
            dc.DrawRoundedRectangle(_customFillBrush, _customStrokePen, rect, 8, 8);

            if (!string.IsNullOrWhiteSpace(HighlightedCustomButtonId) &&
                string.Equals(button.Id, HighlightedCustomButtonId, StringComparison.Ordinal))
            {
                dc.DrawRoundedRectangle(_customHitFillBrush, _customHitStrokePen, rect, 8, 8);
            }

            if (!string.IsNullOrWhiteSpace(SelectedCustomButtonId) &&
                string.Equals(button.Id, SelectedCustomButtonId, StringComparison.Ordinal))
            {
                dc.DrawRoundedRectangle(_customSelectedFillBrush, _customSelectedStrokePen, rect, 8, 8);
            }

            DrawButtonLabel(dc, rect, button.Label);
        }
    }

    private void DrawButtonLabel(DrawingContext dc, Rect rect, string label)
    {
        int split = label.IndexOf('\n');
        if (split > 0 && split < label.Length - 1)
        {
            string primary = label.Substring(0, split);
            string hold = label.Substring(split + 1);

            FormattedText primaryText = new(
                primary,
                CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                _monoTypeface,
                10,
                _textBrush,
                1.0);
            dc.DrawText(primaryText, new Point(rect.Left + (rect.Width - primaryText.Width) / 2, rect.Top + (rect.Height - primaryText.Height) / 2));

            FormattedText holdText = new(
                hold,
                CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                _monoTypeface,
                8,
                _textBrush,
                1.0);
            dc.DrawText(holdText, new Point(rect.Left + (rect.Width - holdText.Width) / 2, rect.Bottom - holdText.Height - 2));
            return;
        }

        FormattedText text = new(
            label,
            CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight,
            _monoTypeface,
            10,
            _textBrush,
            1.0);
        dc.DrawText(text, new Point(rect.Left + (rect.Width - text.Width) / 2, rect.Top + (rect.Height - text.Height) / 2));
    }

    private static bool RectEquals(NormalizedRect a, NormalizedRect b)
    {
        return Math.Abs(a.X - b.X) < 0.00001 && Math.Abs(a.Y - b.Y) < 0.00001 && Math.Abs(a.Width - b.Width) < 0.00001 && Math.Abs(a.Height - b.Height) < 0.00001;
    }

    private Rect CreatePadRect(Rect bounds)
    {
        double padding = 0;
        Rect inner = new Rect(bounds.Left + padding, bounds.Top + padding, bounds.Width - padding * 2, bounds.Height - padding * 2);
        if (inner.Width <= 0 || inner.Height <= 0)
        {
            return inner;
        }

        double aspect = TrackpadWidthMm <= 0 || TrackpadHeightMm <= 0 ? 1.0 : TrackpadWidthMm / TrackpadHeightMm;
        double width = inner.Width;
        double height = width / aspect;
        if (height > inner.Height)
        {
            height = inner.Height;
            width = height * aspect;
        }

        double x = inner.Left + (inner.Width - width) / 2;
        double y = inner.Top + (inner.Height - height) / 2;
        return new Rect(x, y, width, height);
    }
}

public readonly record struct SurfaceCustomButton(string Id, NormalizedRect Rect, string Label);
