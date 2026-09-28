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
        {
            var window = new MainWindow(null, new Preferences { PanelMode = mode, Language = "en" });
            window.SetState(state); window.Reveal(); window.UpdateLayout();
            if (window.Topmost != (mode == "alwaysOnTop") || window.ShowInTaskbar != (mode == "window")) throw new Exception("Incorrect window mode");
            var bitmap = window.RenderScreenshot();
            if (bitmap.PixelWidth < 600 || bitmap.PixelHeight < 600) throw new Exception("Screenshot too small");
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var file = File.Create(Path.Combine(directory, mode + ".png"))) encoder.Save(file);
            window.Stop(); window.Close();
        }
        File.WriteAllText(Path.Combine(directory, "passed.txt"), "PASS: four native window modes and private screenshots\n");
        app.Shutdown();
    }
}
