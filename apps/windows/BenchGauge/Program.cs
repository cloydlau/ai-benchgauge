using System;
using System.IO;
using System.IO.Pipes;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using BenchGauge.Shared;
using Forms = System.Windows.Forms;

namespace BenchGauge;
static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        if (Array.IndexOf(args, "--smoke-test") >= 0)
        {
            try { SmokeTests.Run(); }
            catch (Exception error)
            {
                var directory = Path.Combine(Environment.CurrentDirectory, "work", "windows-ui-smoke");
                Directory.CreateDirectory(directory);
                File.WriteAllText(Path.Combine(directory, "failed.txt"), error.ToString());
                Environment.ExitCode = 1;
            }
            return;
        }
        using var mutex = new Mutex(true, @"Local\AI-BenchGauge", out var first);
        if (!first)
        {
            try { using var pipe = new NamedPipeClientStream(".", "AI-BenchGauge-open", PipeDirection.Out); pipe.Connect(1500); pipe.WriteByte(1); }
            catch (IOException) { } catch (TimeoutException) { }
            return;
        }
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        try
        {
            using var engine = new EngineClient(Path.Combine(AppContext.BaseDirectory, "engine", "benchgauge-engine.exe"));
            var prefs = Preferences.Load();
            var window = new MainWindow(engine, prefs);
            app.MainWindow = window;
            using var tray = new Forms.NotifyIcon { Icon = System.Drawing.SystemIcons.Application, Text = "AI BenchGauge", Visible = true };
            window.Tray = tray;
            tray.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) window.Toggle(); };
            var menu = new Forms.ContextMenuStrip();
            menu.Items.Add("AI BenchGauge", null, (_, _) => window.Reveal());
            menu.Items.Add("GitHub", null, (_, _) => MainWindow.Open("https://github.com/cloydlau/ai-benchgauge"));
            menu.Items.Add(window.Tr("Check for updates", "检查更新"), null, async (_, _) => await window.CheckUpdates(manual: true));
            menu.Items.Add(window.Tr("Quit", "退出"), null, (_, _) => app.Shutdown());
            tray.ContextMenuStrip = menu;
            app.Startup += async (_, _) => { window.Reveal(); await window.Start(); };
            _ = Task.Run(async () =>
            {
                while (true)
                {
                    await using var pipe = new NamedPipeServerStream("AI-BenchGauge-open", PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                    await pipe.WaitForConnectionAsync();
                    var one = new byte[1];
                    if (await pipe.ReadAsync(one) == 1) await app.Dispatcher.InvokeAsync(window.Reveal);
                }
            });
            app.Run();
            window.Stop();
        }
        catch (Exception)
        {
            MessageBox.Show("AI BenchGauge could not start. Please reinstall the application.", "AI BenchGauge", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}
