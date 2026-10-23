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
    sealed record Case(string Id, string Language, int Width, int Height, string Scenario, string Mode, int? QuotaAgeSeconds, string? VersionText, int? RowCount, string? Category, string[]? SelectedBoards, string[]? RefreshedSelectedBoards, string? SearchQuery, string? Grouping, Dictionary<string, string>? Countries, Dictionary<string, string>? Sources);
    sealed record Fixture(DisplayState State, Case[] Cases, Dictionary<string, Quota[]>? QuotaScenarios, Dictionary<string, ModelDetailSection[]>? ModelDetails);
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
            if (test.RowCount is { } rowCount)
                state = state with { Boards = state.Boards.Select(board => board with {
                    Entries = Enumerable.Range(1, rowCount).Select(rank =>
                        new Entry(rank, $"Fixture model {rank}", rowCount - rank + 1,
                            $"Fixture maker {rank}", null, "openai", null, null, null)).ToArray()
                }).ToArray() };
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
            if (test.Scenario == "sourceTimes") state = state with { Boards = state.Boards.Select(board => board with {
                UpdatedAt = board.Kind == "artificialAnalysis" ? null : board.Kind == "arenaText" ? "2026-10-15T00:00:00Z" : board.UpdatedAt,
                FetchedAt = "2026-10-22T00:00:00Z"
            }).ToArray() };
            if (test.Scenario == "freshnessStale") state = state with {
                QuotaUnavailable = true, Quotas = state.Quotas.Select(quota => quota with { IsStale = true }).ToArray() };
            state = state with { Boards = state.Boards.Select(board => board with { Distribution = LeaderboardDistribution.FromEntries(board.Entries) }).ToArray() };
            if (test.Scenario == "usagePending") state = state with { Boards = state.Boards.Select(board => board.Kind == "openRouterUsage" ? board with { Entries = [], Error = "Data source awaiting configuration / 数据源待配置" } : board).ToArray() };
            var preferences = new Preferences { Language = test.Language, Category = test.Category ?? "general", PanelMode = test.Scenario == "window" ? "window" : test.Mode };
            if (test.SelectedBoards is { } selected) preferences.BoardSelections[preferences.Category] = selected;
            if (test.Grouping is { } grouping) preferences.Grouping = grouping;
            if (test.Countries is { } countries) preferences.Countries = countries;
            if (test.Sources is { } sources) preferences.Sources = sources;
            if (test.Grouping == "company") state = state with { Boards = state.Boards.Select(board => board with {
                Entries = board.Entries.GroupBy(entry => entry.Organization).Select(group => {
                    var best = group.OrderByDescending(entry => entry.Score).First();
                    return best with { Name = best.Organization ?? best.Name, Score = board.Kind is "openRouterUsage" or "vercelUsage" or "cloudbaseUsage" ? group.Sum(entry => entry.Score) : best.Score };
                }).OrderByDescending(entry => entry.Score).ToArray()
            }).ToArray() };
            var panel = new MainWindow(null, preferences)
                { Width = test.Width, Height = test.Height };
            panel.SetVisualViewport(test.Width, test.Height);
            // The account dialog owns the panel; WPF requires that owner to
            // have been shown before assigning Window.Owner.
            panel.SetVisualAppearance(theme == "dark");
            if (test.Scenario is "addModelDialog" or "thirdPartyNotices" || test.Scenario.StartsWith("modelDetails")) panel.Show();
            var detailEntry = state.Boards[0].Entries[0] with { Details = fixture.ModelDetails?.GetValueOrDefault(test.Language) };
            if (test.Scenario == "modelDetailsMissing") detailEntry = detailEntry with { Name = "Unmatched model / 暂无模型资料", Details = [] };
            if (test.Scenario == "modelDetailsLong") detailEntry = detailEntry with { Name = "Research Model — Extended Reasoning / Very Long Provider Variant 长名称测试模型（高推理预算版本）" };
            Window window = test.Scenario == "thirdPartyNotices" ? panel.CreateLicenseWindow(true)
                : test.Scenario.StartsWith("modelDetails") ? panel.CreateModelDetailsWindow(detailEntry)
                : test.Scenario == "addModelDialog"
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
                if (test.Scenario.StartsWith("modelDetails") || test.Scenario is "addModelDialog" or "thirdPartyNotices" || test.Scenario.StartsWith("xaiSubscriptionDialog", StringComparison.Ordinal) || test.Scenario.StartsWith("xaiDeviceDialog", StringComparison.Ordinal))
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
                    if (test.Scenario.StartsWith("usageLoading", StringComparison.Ordinal)) {
                        var displayed = state;
                        var loading = frame < 2;
                        if (test.Scenario != "usageLoadingCached" && !(frame == 2 && test.Scenario == "usageLoadingSuccess"))
                            displayed = state with { Boards = state.Boards.Select(board => board.Kind is "openRouterUsage" or "vercelUsage" ? board with { Entries = [], Error = test.Scenario == "usageLoadingFailure" && frame == 2 ? "Refresh failed / 加载失败（测试）" : null } : board).ToArray() };
                        panel.SetVisualBoardLoading(loading); panel.SetState(displayed);
                    }
                    else if (frame == 1) { if (test.RefreshedSelectedBoards is { } selectedBoards) preferences.BoardSelections[preferences.Category] = selectedBoards; panel.SetState(state); window.InvalidateVisual(); } // Catch layout changes after refresh.
                    Settle(window);
                    if (test.Scenario == "distributionCharts" && frame > 0) {
                        static System.Collections.Generic.IEnumerable<DependencyObject> Walk(DependencyObject view) {
                            yield return view;
                            for (var i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(view); i++)
                                foreach (var child in Walk(System.Windows.Media.VisualTreeHelper.GetChild(view, i))) yield return child;
                        }
                        var list = Walk(window).OfType<VirtualLeaderboardList>().First();
                        list.ScrollIntoView(list.Items[list.Items.Count - 1]); Settle(window);
                        if (!Walk(window).OfType<FrameworkElement>().Any(view => System.Windows.Automation.AutomationProperties.GetAutomationId(view) == "leaderboard-distributions" && view.IsVisible))
                            throw new InvalidOperationException("Distribution footer missing");
                    }
                    if (test.Scenario.StartsWith("usageLoading", StringComparison.Ordinal)) {
                        static IEnumerable<DependencyObject> WalkLoading(DependencyObject view) {
                            yield return view;
                            for (var i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(view); i++)
                                foreach (var child in WalkLoading(System.Windows.Media.VisualTreeHelper.GetChild(view, i))) yield return child;
                        }
                        var placeholders = WalkLoading(window).OfType<FrameworkElement>().Select(view => System.Windows.Automation.AutomationProperties.GetAutomationId(view)).Where(id => id is "usage-loading" or "usage-empty" or "usage-error").ToArray();
                        var hasData = test.Scenario == "usageLoadingCached" || frame == 2 && test.Scenario == "usageLoadingSuccess";
                        var expected = frame < 2 ? "usage-loading" : test.Scenario == "usageLoadingFailure" ? "usage-error" : "usage-empty";
                        if (hasData ? placeholders.Length != 0 : !placeholders.SequenceEqual(new[] { expected }))
                            throw new InvalidOperationException("Usage loading, empty and error states overlap or replace cached data");
                    }
                    if (test.Scenario == "sourceMenu")
                    {
                        static IEnumerable<DependencyObject> Walk(DependencyObject view) {
                            yield return view;
                            for (var i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(view); i++)
                                foreach (var child in Walk(System.Windows.Media.VisualTreeHelper.GetChild(view, i))) yield return child;
                        }
                        var button = Walk(window).OfType<System.Windows.Controls.Button>().Single(view =>
                            System.Windows.Automation.AutomationProperties.GetAutomationId(view) == "data-sources-menu");
                        if (!button.IsVisible || button.ActualWidth <= 0) throw new InvalidOperationException("Data sources button is missing");
                        if (frame > 0) {
                            button.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
                            Settle(window);
                            var links = button.ContextMenu.Items.OfType<System.Windows.Controls.MenuItem>().ToArray();
                            var expected = new[] { "artificialAnalysis", "arenaText", "epochECI", "openRouterUsage", "vercelUsage" };
                            if (!button.ContextMenu.IsOpen || !links.Select(link => System.Windows.Automation.AutomationProperties.GetAutomationId(link)).SequenceEqual(expected.Select(kind => "data-source-" + kind)))
                                throw new InvalidOperationException("Data source links are incomplete or contain a disabled source");
                        }
                    }
                    if (test.Scenario.StartsWith("desktopSearch", StringComparison.Ordinal))
                    {
                        static System.Collections.Generic.IEnumerable<DependencyObject> Descendants(DependencyObject view) {
                            yield return view;
                            for (var i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(view); i++)
                                foreach (var child in Descendants(System.Windows.Media.VisualTreeHelper.GetChild(view, i))) yield return child;
                        }
                        FrameworkElement Find(string id) => Descendants(window).OfType<FrameworkElement>().First(view =>
                            System.Windows.Automation.AutomationProperties.GetAutomationId(view) == id);
                        if (frame == 1) {
                            ((System.Windows.Controls.Button)Find("leaderboard-search-button")).RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
                            var field = (System.Windows.Controls.TextBox)Find("leaderboard-search-input");
                            if (!field.IsVisible || !field.IsKeyboardFocusWithin)
                                throw new InvalidOperationException("Search must open and focus synchronously: " + test.Id);
                            Settle(window);
                            var beforeTyping = Descendants(window).OfType<VirtualLeaderboardList>().First();
                            var query = test.SearchQuery ?? "";
                            if (query.Length > 0) {
                                foreach (var prefix in new[] { query[..1], query }) field.Text = prefix;
                                if (!Descendants(window).Contains(beforeTyping))
                                    throw new InvalidOperationException("Draft typing synchronously rebuilt the table: " + test.Id);
                            }
                            else field.Text = "";
                        }
                        if (frame == 2) {
                            panel.SetState(state); Settle(window);
                            System.Windows.Input.Keyboard.ClearFocus();
                            window.Focus();
                        }
                        Settle(window);
                        var input = (System.Windows.Controls.TextBox)Find("leaderboard-search-input");
                        if (frame > 0 && (input.Text != (test.SearchQuery ?? "") || input.IsVisible != (frame == 1 || !string.IsNullOrEmpty(test.SearchQuery))))
                            throw new InvalidOperationException("Search query or blur state lost: " + test.Id);
                    }
                    if (test.Scenario == "boardSelection")
                    {
                        var grids = Descendants(window).OfType<System.Windows.Controls.Grid>().Where(grid =>
                            System.Windows.Automation.AutomationProperties.GetAutomationId(grid) == "leaderboard-columns").ToArray();
                        var expected = 1 + preferences.VisibleBoardKinds().Length * 4;
                        if (grids.Length == 0 || grids.Any(grid => grid.ColumnDefinitions.Count != expected))
                            throw new InvalidOperationException("Hidden leaderboard columns remain in the native table");
                        if (test.Width < 748 && preferences.VisibleBoardKinds().Length == 3 && frame > 0)
                        {
                            var horizontal = Descendants(window).OfType<System.Windows.Controls.ScrollViewer>().FirstOrDefault(scroll => scroll.ScrollableWidth > 0);
                            if (horizontal is null) throw new InvalidOperationException("Selected sources have no horizontal viewport");
                            horizontal.ScrollToRightEnd(); Settle(window);
                            if (horizontal.HorizontalOffset <= 0) throw new InvalidOperationException("Selected sources cannot be reached by horizontal scrolling");
                        }
                    }
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
                if (test.Scenario == "virtualRanking") VerifyVirtualRanking(window);
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

    static IEnumerable<System.Windows.DependencyObject> Descendants(System.Windows.DependencyObject root)
    {
        yield return root;
        for (var index = 0; index < System.Windows.Media.VisualTreeHelper.GetChildrenCount(root); index++)
            foreach (var child in Descendants(System.Windows.Media.VisualTreeHelper.GetChild(root, index))) yield return child;
    }

    static void VerifyVirtualRanking(Window window)
    {
        var list = Descendants(window).OfType<VirtualLeaderboardList>().Single();
        int Realized() => Descendants(list).OfType<System.Windows.Controls.VirtualizingStackPanel>().Single().Children.Count;
        var initial = Realized();
        if (list.Items.Count < 1000 || initial == 0 || initial >= 200)
            throw new InvalidOperationException("Long ranking created too many row controls");
        list.ScrollIntoView(list.Items.Count - 1); Settle(window);
        if (list.ItemContainerGenerator.ContainerFromIndex(list.Items.Count - 1) is null || Realized() >= 200)
            throw new InvalidOperationException("Long ranking tail or recycling failed");
        Console.WriteLine($"[virtual-ranking] rows={list.Items.Count} initialViews={initial} tailViews={Realized()}");
        var back = Descendants(window).OfType<System.Windows.Controls.Button>().Single(button =>
            System.Windows.Automation.AutomationProperties.GetAutomationId(button) == "leaderboard-back-to-top");
        back.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent)); Settle(window);
        if (list.ItemContainerGenerator.ContainerFromIndex(0) is null)
            throw new InvalidOperationException("Long ranking did not return to first row");
    }

    static string FixtureQuotaText(string text, string language) => (language, text) switch
    {
        ("en", "登录失效") => "Login expired", ("en", "查询中") => "Checking",
        ("en", "查询失败") => "Query failed", ("zh-Hant", "查询失败") => "查詢失敗",
        ("en", "未订购") => "Not subscribed", ("zh-Hant", "未订购") => "未訂購",
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
