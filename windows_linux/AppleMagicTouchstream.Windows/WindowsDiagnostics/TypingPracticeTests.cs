using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AppleMagicTouchstream;

internal static class TypingPracticeTests
{
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static void Near(double actual, double expected, string message) => Check(Math.Abs(actual - expected) < 0.001, message);
    internal static void Run()
    {
        var random = new Random(17);
        foreach (var mode in Enum.GetValues<TypingPracticeSession.Mode>())
        {
            var words = TypingPracticeSession.Generate(mode, 25, "cat dog sun", random).Split(' ');
            var source = mode == TypingPracticeSession.Mode.Custom ? new[] { "cat", "dog", "sun" }
                : mode == TypingPracticeSession.Mode.Steno ? TypingPracticeSession.StenoWords : TypingPracticeSession.CommonWords;
            Check(words.Length == 25 && words.All(source.Contains), "Generated words escaped the selected practice pool");
            Check(words.Zip(words.Skip(1)).All(pair => pair.First != pair.Second), "Practice repeated adjacent words");
        }
        Check(TypingPracticeSession.Generate(TypingPracticeSession.Mode.Custom, 25, " \n ", random) == "", "Blank custom list generated a prompt");
        Check(TypingPracticeSession.Generate(TypingPracticeSession.Mode.Custom, 10, "one one", random).Split(' ').Length == 10, "Duplicate single-word custom list failed");
        Check(TypingPracticeSession.Words(string.Concat(Enumerable.Repeat("word ", 1000))).Length == 500, "Custom list is unbounded");
        Check(TypingPracticeSession.Words(new string('x', 80))[0].Length == 40, "Custom word length is unbounded");

        var start = DateTimeOffset.UnixEpoch;
        var session = new TypingPracticeSession("hello world");
        session.Update("", start);
        Check(session.StartedAt == null && session.Elapsed(start) == 0, "Empty input started practice clock");
        session.Update("hello", start);
        Near(session.Wpm(start.AddSeconds(60)), 1, "WPM did not use five correct characters per word");
        session.Update("hello world", start.AddSeconds(60));
        Near(session.Wpm(start.AddSeconds(120)), 2.2, "Completed clock did not freeze");
        session.Update("changed", start.AddSeconds(130));
        Check(session.Input == "hello world" && session.Progress == 1, "Completed round remained editable");
        session = new("cat cats", true);
        session.Update("Car", start);
        Near(session.Accuracy, 200.0 / 3, "Incorrect character was not scored");
        session.Update("Ca", start.AddSeconds(1));
        Near(session.Accuracy, 100, "Backspace did not recompute accuracy");
        session.Update(" Cat\t Cats \n", start.AddSeconds(2));
        Check(session.IsComplete && session.ComparisonInput == "cat cats", "Translated steno whitespace/case normalization failed");
        session = new("cat"); session.Update("CAT", start);
        Check(!session.IsComplete && session.Accuracy == 0, "Words mode ignored case");
        session.Update("catx", start); Near(session.Accuracy, 75, "Extra characters were not errors");
        session.Update(new string('x', 7000), start); Check(session.Input.Length == 6000, "Practice input exceeded its bound");
        session = new("café 🐈"); session.Update("café 🐈", start);
        Check(session.IsComplete && session.CorrectCharacters == 6, "Unicode was counted as UTF-16 code units");

        // Construct only the practice panel: no MainWindow, settings load or native input.
        var free = new TextBox { Text = "keep my free text", Height = 72 };
        var panel = new TypingPracticePanel { FreeInput = free, Background = new SolidColorBrush(Color.FromRgb(12, 15, 18)) };
        panel.AreaSelector.SelectedIndex = 1;
        Check(panel.Session.Prompt.Length > 0 && panel.Session.StartedAt == null, "Entering practice did not create an idle round");
        panel.ModeSelector.SelectedIndex = 1;
        panel.PracticeInput.Text = "Car";
        panel.PracticeInput.Select(0, 3); panel.PracticeInput.SelectedText = "café";
        Check(panel.Session.Input == "café", "Native input replacement failed");
        panel.PracticeInput.Select(panel.PracticeInput.Text.Length - 1, 1); panel.PracticeInput.SelectedText = "";
        Check(panel.Session.Input == "caf", "Native deletion failed");
        panel.PracticeInput.Text = panel.Session.Prompt.ToUpperInvariant();
        Check(panel.Session.IsComplete && panel.PracticeInput.IsReadOnly, "Translated steno completion did not freeze native input");
        panel.Restart(); Check(panel.Session.StartedAt == null && panel.PracticeInput.Text == "", "New drill did not reset metrics/input");
        panel.AreaSelector.SelectedIndex = 0;
        Check(free.Text == "keep my free text" && panel.FreeInput == free, "Practice overwrote free text");
        panel.AreaSelector.SelectedIndex = 1;
        panel.ModeSelector.SelectedIndex = 2;
        Check(!panel.NewDrillButton.IsEnabled && panel.Session.Prompt == "", "Blank custom list was not handled");
        panel.CustomInput.Text = "café cat sun";
        Check(panel.NewDrillButton.IsEnabled, "Custom list did not enable New drill");
        panel.Restart(); Check(panel.Session.Prompt.Length > 0, "Custom round did not generate");

        if (Environment.GetEnvironmentVariable("AMT_TYPING_PREVIEW_DIR") is {} directory)
        {
            Directory.CreateDirectory(directory);
            foreach (int width in new[] { 440, 760 })
            {
                foreach (int mode in new[] { 0, 1, 2 })
                {
                    panel.ModeSelector.SelectedIndex = mode; panel.Restart();
                    panel.PracticeInput.Text = panel.Session.Prompt[..3] + "x";
                    Render(panel, width, Path.Combine(directory, $"practice-{mode}-{width}.png"));
                }
                panel.AreaSelector.SelectedIndex = 0;
                Render(panel, width, Path.Combine(directory, $"free-{width}.png"));
                panel.AreaSelector.SelectedIndex = 1;
            }
        }
    }
    private static void Render(FrameworkElement panel, int width, string path)
    {
        panel.Measure(new Size(width, double.PositiveInfinity));
        int height = (int)Math.Ceiling(panel.DesiredSize.Height);
        panel.Arrange(new Rect(0, 0, width, height)); panel.UpdateLayout();
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(panel);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path); encoder.Save(stream);
    }
}
