using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using BenchGauge.Shared;
using Drawing = System.Drawing;

namespace BenchGauge;

// Runs the real WPF window on a Windows desktop, without starting the engine,
// reading accounts or using the privacy-redacted Copy command.
static class VisualTests
{
    sealed record Case(string Id, string Language, int Width, int Height, string Scenario, string Mode, int? QuotaAgeSeconds, string? VersionText);
    sealed record Fixture(DisplayState State, Case[] Cases, Dictionary<string, Quota[]>? QuotaScenarios);
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct Point { public int X, Y; }
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window, ref Point point);
    // DEVMODEW: retain all driver-populated bytes, modifying only a supported
    // mode returned by EnumDisplaySettings (not an invented resolution).
    [StructLayout(LayoutKind.Explicit, Size = 220)] struct DisplayMode
    {
        [FieldOffset(68)] public ushort Size;
        [FieldOffset(72)] public uint Fields;
        [FieldOffset(172)] public uint Width;
        [FieldOffset(176)] public uint Height;
    }
    [DllImport("user32.dll", EntryPoint = "EnumDisplaySettingsW", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettings(string? device, int index, ref DisplayMode mode);
    [DllImport("user32.dll", EntryPoint = "ChangeDisplaySettingsW")]
    static extern int ChangeDisplaySettings(ref DisplayMode mode, int flags);

    public static void Run()
    {
        DisplayMode? original = null;
        if (Environment.GetEnvironmentVariable("CI") == "true")
        {
            var current = new DisplayMode { Size = 220 };
            if (!EnumDisplaySettings(null, -1, ref current)) throw new InvalidOperationException("Cannot read CI desktop mode");
            if (current.Width < 1500 || current.Height < 900)
            {
                for (var index = 0; ; index++)
                {
                    var candidate = new DisplayMode { Size = 220 };
                    if (!EnumDisplaySettings(null, index, ref candidate)) throw new InvalidOperationException("CI desktop has no supported resolution large enough for visual cases");
                    if (candidate.Width < 1500 || candidate.Height < 900) continue;
                    if (ChangeDisplaySettings(ref candidate, 0) != 0) continue;
                    original = current; break;
                }
            }
        }
        try { CaptureCases(); }
        finally { if (original is { } restore) ChangeDisplaySettings(ref restore, 0); }
    }

    static void CaptureCases()
    {
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var root = Environment.CurrentDirectory;
        var captureRoot = Environment.GetEnvironmentVariable("BENCHGAUGE_VISUAL_ROOT") ?? Path.Combine(root, "work", "visual-parity");
        var directory = Path.Combine(captureRoot, "windows");
        Directory.CreateDirectory(directory);
        var fixturePath = Environment.GetEnvironmentVariable("BENCHGAUGE_VISUAL_FIXTURE") ?? Path.Combine(root, "Tests", "fixtures", "visual-state.json");
        var fixtureBytes = File.ReadAllBytes(fixturePath);
        var normalizedFixture = Encoding.UTF8.GetBytes(Encoding.UTF8.GetString(fixtureBytes).Replace("\r\n", "\n"));
        var fixtureHash = Convert.ToHexString(SHA256.HashData(normalizedFixture)).ToLowerInvariant();
        var fixture = JsonSerializer.Deserialize<Fixture>(fixtureBytes, AppConfig.Json)
            ?? throw new InvalidOperationException("Missing visual fixture");
        var metadata = new List<object>();
        foreach (var test in fixture.Cases)
        foreach (var theme in new[] { "light", "dark" })
        {
            var state = fixture.State;
            if (fixture.QuotaScenarios is { } scenarios && scenarios.TryGetValue(test.Scenario, out var scenarioQuotas))
                state = state with { Quotas = scenarioQuotas.Select(quota => quota with {
                    Runs = quota.Runs.Select(run => run with { Text = FixtureQuotaText(run.Text, test.Language) }).ToArray()
                }).ToArray() };
            if (test.Scenario is "normal" or "window" || test.QuotaAgeSeconds.HasValue) state = state with { Quotas = state.Quotas.Take(2).ToArray() };
            if (test.Scenario is "empty" or "installedEmpty") state = state with { Quotas = [], QuotaNeedsCCSwitch = test.Scenario == "empty" };
            if (test.Scenario == "error") state = state with { Boards = state.Boards.Select(board => board with { Error = "Refresh failed / 刷新失败（测试）" }).ToArray(), Quotas = [] };
            if (test.QuotaAgeSeconds is { } age)
            {
                var stamp = age < 0 ? null : DateTimeOffset.UtcNow.AddSeconds(-age).ToString("O");
                state = state with { QuotaUpdatedAt = stamp,
                    Boards = state.Boards.Select(board => board with { FetchedAt = stamp ?? board.FetchedAt }).ToArray() };
            }
            if (test.Scenario == "freshnessStale") state = state with {
                QuotaUnavailable = true, Quotas = state.Quotas.Select(quota => quota with { IsStale = true }).ToArray() };
            var panel = new MainWindow(null, new Preferences { Language = test.Language, PanelMode = test.Scenario == "window" ? "window" : test.Mode })
                { Width = test.Width, Height = test.Height };
            panel.SetVisualViewport(test.Width, test.Height);
            panel.SetVisualVersionText(test.VersionText);
            Window window = test.Scenario == "addModelDialog"
                ? panel.CreateOfficialAccountsWindow(new EngineResponse(0, null, null, null, null,
                    OfficialAccounts: [], OfficialProviders: [new OfficialProviderSummary("kimi", "Kimi Code", "Kimi Code plan")]))
                : test.Scenario.StartsWith("xaiDeviceDialog", StringComparison.Ordinal)
                    ? new XAIAccountConnectionWindow(null, new Preferences { Language = test.Language }, null, test.Scenario.Replace("xaiDeviceDialog-", ""))
                : test.Scenario.StartsWith("xaiSubscriptionDialog", StringComparison.Ordinal)
                    ? new XAIWebsiteSubscriptionWindow(null, new Preferences { Language = test.Language }, null, fixture: true, fixtureState: test.Scenario.Replace("xaiSubscriptionDialog-", ""))
                    : panel;
            try
            {
                panel.SetVisualAppearance(theme == "dark");
                if (window is XAIAccountConnectionWindow xaiLogin) xaiLogin.SetAppearance(theme == "dark");
                panel.SetState(state);
                if (test.Scenario == "addModelDialog" || test.Scenario.StartsWith("xaiSubscriptionDialog", StringComparison.Ordinal) || test.Scenario.StartsWith("xaiDeviceDialog", StringComparison.Ordinal))
                {
                    window.SizeToContent = SizeToContent.Manual; window.WindowStyle = WindowStyle.None;
                    window.Width = test.Width; window.Height = test.Height; window.Show();
                }
                else panel.Reveal();
                Settle(window);
                // Fixture dimensions describe the content, independent of
                // the native title bar and resize border in window mode.
                if (test.Scenario == "window" && window.Content is FrameworkElement client)
                {
                    window.Width += test.Width - client.ActualWidth;
                    window.Height += test.Height - client.ActualHeight;
                    Settle(window);
                }
                // Centre and verify the complete client area fits the desktop.
                window.Left = SystemParameters.WorkArea.Left + (SystemParameters.WorkArea.Width - window.ActualWidth) / 2;
                window.Top = SystemParameters.WorkArea.Top + (SystemParameters.WorkArea.Height - window.ActualHeight) / 2;
                Settle(window);
                var hwnd = new WindowInteropHelper(window).Handle;
                if (!GetClientRect(hwnd, out var rect)) throw new InvalidOperationException("Cannot measure Windows client area");
                var point = new Point();
                if (!ClientToScreen(hwnd, ref point)) throw new InvalidOperationException("Cannot locate Windows client area");
                var bounds = System.Windows.Forms.SystemInformation.VirtualScreen;
                if (!bounds.Contains(new Drawing.Rectangle(point.X, point.Y, rect.Right, rect.Bottom)))
                    throw new InvalidOperationException("Visual case does not fit the real Windows desktop: " + test.Id);
                for (var frame = 0; frame < 3; frame++)
                {
                    if (frame == 1) { panel.SetState(state); window.InvalidateVisual(); } // Catch layout changes after refresh.
                    Settle(window);
                    using var bitmap = new Drawing.Bitmap(rect.Right, rect.Bottom);
                    using (var graphics = Drawing.Graphics.FromImage(bitmap))
                        graphics.CopyFromScreen(point.X, point.Y, 0, 0, bitmap.Size);
                    // An inaccessible/locked desktop must fail instead of producing a false pass.
                    var colors = new HashSet<int>();
                    for (var y = 0; y < bitmap.Height; y += 7)
                    for (var x = 0; x < bitmap.Width; x += 7) colors.Add(bitmap.GetPixel(x, y).ToArgb());
                    if (colors.Count < 20) throw new InvalidOperationException("Blank Windows desktop capture: " + test.Id);
                    bitmap.Save(Path.Combine(directory, $"{test.Id}{(theme == "dark" ? "-dark" : "")}-frame-{frame}.png"), Drawing.Imaging.ImageFormat.Png);
                }
                var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(window);
                metadata.Add(new { test.Id, theme, test.Language, test.Scenario, test.Width, test.Height,
                    clientPixelWidth = rect.Right, clientPixelHeight = rect.Bottom, dpiScale = dpi.DpiScaleX,
                    fixtureHash, timezone = TimeZoneInfo.Local.Id,
                    sourceCommit = Environment.GetEnvironmentVariable("GITHUB_SHA") ?? "local-uncommitted",
                    capture = "desktop-client-area", frames = new[] { "shown", "refreshed", "settled" }, os = Environment.OSVersion.ToString() });
            }
            finally { panel.Stop(savePreferences: false); window.Close(); if (window != panel) panel.Close(); }
        }
        File.WriteAllText(Path.Combine(directory, "metadata.json"), JsonSerializer.Serialize(metadata, new JsonSerializerOptions { WriteIndented = true }));
        app.Shutdown();
    }

    static string FixtureQuotaText(string text, string language) => (language, text) switch
    {
        ("en", "登录失效") => "Login expired", ("en", "查询中") => "Checking",
        ("en", "查询失败") => "Query failed", ("zh-Hant", "查询失败") => "查詢失敗",
        ("en", " · 至11月18日") => " · to Nov 18", ("zh-Hant", " · 至11月18日") => " · 至11月18日",
        ("en", "未配置") => "Not configured", ("zh-Hant", "登录失效") => "登錄失效",
        ("en", "至10月5日") => "to Oct 5", ("en", "至10月24日") => "to Oct 24",
        ("zh-Hant", "查询中") => "查詢中", _ => text
    };

    static void Settle(Window window)
    {
        window.UpdateLayout();
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.ApplicationIdle) { Interval = TimeSpan.FromMilliseconds(250) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
        timer.Start(); Dispatcher.PushFrame(frame);
    }
}
