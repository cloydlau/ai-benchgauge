using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Input;
using System.Windows.Threading;
using System.Windows.Media.Imaging;
using System.Text.Json;
using BenchGauge.Shared;
using TextRun = System.Windows.Documents.Run;

namespace BenchGauge;
static class SmokeTests
{
    public static void Run()
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var directory = Path.Combine(Environment.CurrentDirectory, "work", "windows-ui-smoke");
        Directory.CreateDirectory(directory);
        var entries = Enumerable.Range(1, 20).Select(i => new Entry(i, "Synthetic model " + i, 100 - i, "OpenAI", "unitedStates", "openai", null, null, null)).ToArray();
        var state = new DisplayState([new("artificialAnalysis", "Artificial Analysis", "https://artificialanalysis.ai", "2026-09-29T00:00:00Z", null, entries), new("arenaText", "Arena", "https://arena.ai", null, null, entries)],
            [new("fixture-date", "Synthetic date warning", true, false, "fixture", null, false, null,
                 [new("90%", "#198542", "#7CD68C"), new(" · ", "#666666", "#AAAAAA"), new("to Sep 30", "#DB2828", "#FF736B")], "#DB2828"),
             new("fixture-quota", "Synthetic quota warning", false, false, "fixture", null, false, null,
                 [new("10%", "#DB2828", "#FF736B"), new(" · ", "#666666", "#AAAAAA"), new("to Oct 31", "#198542", "#7CD68C")], "#DB2828")], false, false, null, []);
        var fixture = System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(Environment.CurrentDirectory, "Tests", "fixtures", "visual-state.json")));
        var fullState = fixture.RootElement.GetProperty("state").Deserialize<DisplayState>(AppConfig.Json)!;
        foreach (var language in new[] { "en", "zh", "zh-Hant" })
        {
            var auto = new MainWindow(null, new Preferences { Language = language });
            auto.SetState(fullState); auto.Reveal(); auto.UpdateLayout();
            var cap = Math.Max(auto.MinWidth, SystemParameters.WorkArea.Width - 16);
            if (auto.Width > cap + 1 || (cap > 1200 && auto.Width <= 900)) throw new Exception("Popover must size to long names within the desktop");
            if (auto.Width < cap - 1)
            {
                var titles = fullState.Boards.SelectMany(board => board.Entries).Select(entry => entry.Name).ToHashSet();
                var labels = Descendants<TextBlock>(auto).Where(label => titles.Contains(label.Text)).ToArray();
                if (labels.Length != fullState.Boards.Sum(board => board.Entries.Length)) throw new Exception("Missing model name labels");
                foreach (var label in labels)
                {
                    var ink = new FormattedText(label.Text, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                        new Typeface(label.FontFamily, label.FontStyle, label.FontWeight, label.FontStretch), label.FontSize,
                        label.Foreground, VisualTreeHelper.GetDpi(label).PixelsPerDip);
                    if (ink.WidthIncludingTrailingWhitespace > label.ActualWidth + 1) throw new Exception("Long model name is unnecessarily truncated: " + label.Text);
                }
            }
            var widthBefore = auto.Width;
            auto.SetState(fullState with { Boards = fullState.Boards.Select(board => board with { Entries = board.Entries.Take(1).ToArray() }).ToArray(),
                LayoutEntries = fullState.Boards.SelectMany(board => board.Entries).Select(entry => new LayoutEntry(entry.Name, null, null)).ToArray() });
            auto.UpdateLayout();
            if (Math.Abs(auto.Width - widthBefore) > 1) throw new Exception("Changing to a short board must retain cached long-name width");
            auto.Stop(savePreferences: false); auto.Close();
        }
        foreach (var mode in new[] { "clickToClose", "alwaysOnTop", "closeOnBlur", "window" })
        foreach (var language in new[] { "en", "zh", "zh-Hant" })
        foreach (var width in new[] { 600, 900 })
        {
            var window = new MainWindow(null, new Preferences { PanelMode = mode, Language = language }) { Width = width };
            window.SetVisualViewport(width, window.Height);
            window.SetState(state); window.Reveal(); window.UpdateLayout();
            // Refresh an already visible window too: reused WPF elements must
            // retain one parent while quota and footer content are rebuilt.
            window.SetState(state); window.UpdateLayout();
            var cards = Descendants<Border>(window).Where(card => card.Child is Grid line &&
                line.Children.OfType<TextBlock>().Any(text => text.Inlines.OfType<TextRun>().FirstOrDefault()?.Text.Trim() is "Synthetic date warning" or "Synthetic quota warning")).ToArray();
            if (cards.Length != 2) throw new Exception($"Expected two quota cards, found {cards.Length}");
            foreach (var card in cards)
            {
                if (card.Background is not SolidColorBrush fill || fill.Color != (Color)ColorConverter.ConvertFromString("#DB2828") || fill.Opacity <= 0)
                    throw new Exception("Quota and date warnings must both tint the background");
                var runs = ((Grid)card.Child).Children.OfType<TextBlock>().Single().Inlines.OfType<TextRun>().ToArray();
                var dateWarning = runs[0].Text.Contains("date warning");
                if (card.BorderThickness.Left != (dateWarning ? 1 : 0)) throw new Exception("Only the active card has a border");
                var quotaColor = ((SolidColorBrush)runs[1].Foreground).Color;
                var dateColor = ((SolidColorBrush)runs[3].Foreground).Color;
                if (dateWarning ? quotaColor.G <= quotaColor.R || dateColor.R <= dateColor.G : quotaColor.R <= quotaColor.G || dateColor.G <= dateColor.R)
                    throw new Exception("Quota and date text must retain independent colors");
            }
            if (window.Topmost != (mode == "alwaysOnTop") || window.ShowInTaskbar != (mode == "window")) throw new Exception("Incorrect window mode");
            var workArea = SystemParameters.WorkArea;
            if (window.Height > workArea.Height || window.Top < workArea.Top - 1 || window.Top + window.Height > workArea.Bottom + 1)
                throw new Exception("Panel must fit the available desktop height");
            var expectedLeft = mode == "window" ? workArea.Left + (workArea.Width - width) / 2 : Math.Max(workArea.Left, workArea.Right - width - 12);
            var expectedTop = mode == "window" ? workArea.Top + (workArea.Height - window.Height) / 2 : Math.Max(workArea.Top, workArea.Bottom - window.Height - 12);
            if (Math.Abs(window.Left - expectedLeft) > 1 || Math.Abs(window.Top - expectedTop) > 1) throw new Exception("Incorrect initial window position");
            if (mode == "window")
            {
                window.WindowState = WindowState.Minimized; window.Reveal(); window.UpdateLayout();
                if (window.WindowState != WindowState.Normal) throw new Exception("Could not restore minimized window");
            }
            var bitmap = window.RenderScreenshot();
            if (bitmap.PixelWidth < 500 || bitmap.PixelHeight < 500) throw new Exception("Screenshot too small");
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var file = File.Create(Path.Combine(directory, $"{mode}-{language}-{width}.png"))) encoder.Save(file);
            var confirms = 0;
            PreparedUpdateDialog? update = null;
            update = new PreparedUpdateDialog(window, window.Tr, () =>
            {
                confirms++;
                update!.PrepareForShutdown(); update.Close();
            });
            window.Dispatcher.BeginInvoke(() =>
            {
                update.Close(); // Title-bar/Alt-F4 close requests must be rejected.
                if (!update.IsVisible) throw new Exception("Mandatory update was dismissible");
                var escape = new KeyEventArgs(Keyboard.PrimaryDevice, PresentationSource.FromVisual(update), 0, Key.Escape) { RoutedEvent = Keyboard.PreviewKeyDownEvent };
                update.RaiseEvent(escape);
                if (!escape.Handled || !update.IsVisible || confirms != 0) throw new Exception("Escape dismissed or confirmed update");
                var buttons = Descendants<Button>(update).ToArray();
                if (buttons.Length != 1 || update.WindowStyle != WindowStyle.None || update.ShowInTaskbar) throw new Exception("Update dialog has dismiss controls");
                if (language == "zh" && (update.Title != "发现新版本" || buttons[0].Content?.ToString() != "重启升级" || !Descendants<TextBlock>(update).Any(text => text.Text == "新版本已下载完成，重启后生效。")))
                    throw new Exception("Mini-program copy changed");
                buttons[0].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            }, DispatcherPriority.ApplicationIdle);
            update.ShowDialog();
            if (confirms != 1) throw new Exception("Update action must run once");
            window.Stop(); window.Close();
        }
        File.WriteAllText(Path.Combine(directory, "passed.txt"), "PASS: four modes, three languages, two widths, independent quota/date colors, warning backgrounds, active borders, positioning, restoring, repeated refresh, private screenshots and non-dismissible update dialogs\n");
        app.Shutdown();
    }

    static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match) yield return match;
            foreach (var descendant in Descendants<T>(child)) yield return descendant;
        }
    }
}
