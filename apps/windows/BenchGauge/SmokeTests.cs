using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media.Imaging;
using BenchGauge.Shared;

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
            [new("fixture", "Synthetic provider", true, false, "fixture", null, false, null, [new("Balance 12345.67", "#198542", "#7CD68C")])], false, false, null, []);
        foreach (var mode in new[] { "clickToClose", "alwaysOnTop", "closeOnBlur", "window" })
        foreach (var language in new[] { "en", "zh", "zh-Hant" })
        foreach (var width in new[] { 600, 900 })
        {
            var window = new MainWindow(null, new Preferences { PanelMode = mode, Language = language }) { Width = width };
            window.SetState(state); window.Reveal(); window.UpdateLayout();
            // Refresh an already visible window too: reused WPF elements must
            // retain one parent while quota and footer content are rebuilt.
            window.SetState(state); window.UpdateLayout();
            if (window.Topmost != (mode == "alwaysOnTop") || window.ShowInTaskbar != (mode == "window")) throw new Exception("Incorrect window mode");
            var workArea = SystemParameters.WorkArea;
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
            window.Stop(); window.Close();
        }
        File.WriteAllText(Path.Combine(directory, "passed.txt"), "PASS: four modes, three languages, two widths, positioning, restoring, repeated refresh and private screenshots\n");
        app.Shutdown();
    }
}
