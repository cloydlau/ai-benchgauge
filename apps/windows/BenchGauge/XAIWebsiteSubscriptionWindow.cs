using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using BenchGauge.Shared;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace BenchGauge;
// Only the official site's subscription JSON crosses the local pipe. The
// engine verifies xaiUserId against the live CLI account before storing a date.
sealed class XAIWebsiteSubscriptionWindow : Window
{
    readonly WebView2 browser = new();
    readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, FontSize = 12 };
    readonly EngineClient? engine;
    readonly Preferences prefs;
    readonly Action<DisplayState>? update;
    readonly DispatcherTimer poll = new() { Interval = TimeSpan.FromSeconds(2) };
    bool initialized, busy, refreshing;
    int attempts;
    DateTime lastAttempt;
    string Tr(string en, string zh, string hant) => prefs.Language == "en" ? en : prefs.Language == "zh-Hant" ? hant : zh;

    public XAIWebsiteSubscriptionWindow(EngineClient? engine, Preferences prefs, Action<DisplayState>? update, bool fixture = false, string fixtureState = "")
    {
        this.engine = engine; this.prefs = prefs; this.update = update;
        Title = Tr("Connect xAI plan", "连接 xAI 套餐", "連接 xAI 套餐");
        Width = 900; Height = 700; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var layout = new DockPanel();
        var header = new StackPanel { Margin = new Thickness(20, 20, 20, 12) };
        header.Children.Add(new TextBlock { Text = Title, FontSize = 17, FontWeight = FontWeights.Bold });
        header.Children.Add(new TextBlock { Margin = new Thickness(0, 8, 0, 12), TextWrapping = TextWrapping.Wrap, FontSize = 13,
            Text = Tr("Use the same xAI account as CC Switch. After sign-in or verification, the app queries the official subscription and refreshes its date automatically. Usage stays available while connecting.",
                "请使用与 CC Switch 相同的 xAI 账号。登录或验证完成后，应用自动查询官方订阅并刷新日期；连接期间仍可查看余量。",
                "請使用與 CC Switch 相同的 xAI 帳號。登入或驗證完成後，應用自動查詢官方訂閱並刷新日期；連接期間仍可查看餘量。") });
        var row = new DockPanel();
        var retry = new Button { Content = Tr("Query again", "重新查询", "重新查詢"), Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(12, 0, 0, 0) };
        retry.Click += (_, _) => StartPolling(); DockPanel.SetDock(retry, Dock.Right); row.Children.Add(retry);
        status.VerticalAlignment = VerticalAlignment.Center;
        status.Text = StateText(fixtureState);
        row.Children.Add(status); header.Children.Add(row); DockPanel.SetDock(header, Dock.Top); layout.Children.Add(header);
        layout.Children.Add(fixture ? new Border { Background = Brushes.White } : browser);
        Content = layout;
        Closing += (_, e) => { e.Cancel = true; poll.Stop(); Hide(); };
        poll.Tick += async (_, _) => { if (--attempts <= 0) { poll.Stop(); status.Text = StateText("paused"); } else await Capture(); };
    }
    string StateText(string state) => state switch
    {
        "verification" => Tr("Complete the official site's verification below; the app retries automatically.", "请在下方官网完成验证，应用会自动重试。", "請在下方官網完成驗證，應用會自動重試。"),
        "mismatch" => Tr("No matching active plan date found. Check that this is the quota account.", "未找到同一额度账号的有效套餐日期，请检查网页登录账号。", "未找到同一額度帳號的有效套餐日期，請檢查網頁登入帳號。"),
        "paused" => Tr("Query paused. After sign-in or verification, select Query again.", "查询已暂停。完成登录或验证后，请点击重新查询。", "查詢已暫停。完成登入或驗證後，請點擊重新查詢。"),
        _ => Tr("Waiting for official sign-in or verification…", "等待官网登录或验证…", "等待官網登入或驗證…")
    };
    void StartPolling() { attempts = 90; poll.Start(); }
    async Task Initialize()
    {
        if (initialized) return;
        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: Path.Combine(Preferences.DirectoryPath, "xai-subscription-webview"));
        await browser.EnsureCoreWebView2Async(environment);
        browser.CoreWebView2.Settings.AreDevToolsEnabled = false;
        browser.CoreWebView2.Settings.IsWebMessageEnabled = false;
        browser.CoreWebView2.Settings.AreHostObjectsAllowed = false;
        browser.CoreWebView2.NavigationStarting += (_, e) => { if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) || uri.Scheme != "https") e.Cancel = true; };
        browser.CoreWebView2.NewWindowRequested += (_, e) => { e.Handled = true; if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) && uri.Scheme == "https") browser.CoreWebView2.Navigate(e.Uri); };
        browser.CoreWebView2.NavigationCompleted += (_, _) => { if (IsVisible && !refreshing) StartPolling(); };
        initialized = true;
    }
    public async Task Connect()
    {
        Opacity = 1; ShowActivated = true; ShowInTaskbar = true; Show(); Activate();
        await Initialize(); lastAttempt = DateTime.UtcNow;
        browser.CoreWebView2.Navigate("https://grok.com/"); StartPolling();
    }
    public async Task Refresh()
    {
        if (!prefs.XaiSubscriptionWebsiteConnected || refreshing || IsVisible || DateTime.UtcNow - lastAttempt < TimeSpan.FromMinutes(1)) return;
        refreshing = true; lastAttempt = DateTime.UtcNow;
        try
        {
            Opacity = 0; ShowActivated = false; ShowInTaskbar = false; Show();
            await Initialize(); browser.CoreWebView2.Navigate("https://grok.com/");
            for (int i = 0; i < 6; i++) { await Task.Delay(2000); if (await Capture()) break; }
        }
        finally { Hide(); refreshing = false; }
    }
    async Task<bool> Capture()
    {
        if (busy || engine is null || !initialized || !Uri.TryCreate(browser.Source?.AbsoluteUri, UriKind.Absolute, out var uri)
            || uri.Scheme != "https" || uri.Host != "grok.com") return false;
        busy = true;
        try
        {
            var script = """
                (async () => {
                  const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 8000);
                  try {
                    const response = await fetch('/rest/subscriptions', {credentials: 'include', headers: {Accept: 'application/json'}, signal: controller.signal});
                    const body = await response.text(); return {status: response.status, body: body.length <= 1048576 ? body : ''};
                  } catch (_) { return {status: 0, body: ''}; } finally { clearTimeout(timer); }
                })()
                """;
            // WebView2's ExecuteScriptAsync does not await promises. Put the
            // bounded fetch's result in this dedicated app browser's page and
            // read it after completion; never expose the native engine bridge.
            await browser.CoreWebView2.ExecuteScriptAsync("window.__benchgaugeSubscription = null; " + script.Replace("return {status: response.status, body: body.length <= 1048576 ? body : ''};", "window.__benchgaugeSubscription = {status: response.status, body: body.length <= 1048576 ? body : ''};").Replace("return {status: 0, body: ''};", "window.__benchgaugeSubscription = {status: 0, body: ''};"));
            string json = "null";
            for (int i = 0; i < 18 && json == "null"; i++) { await Task.Delay(500); json = await browser.CoreWebView2.ExecuteScriptAsync("window.__benchgaugeSubscription ?? null"); }
            if (browser.Source?.Host != "grok.com" || browser.Source.Scheme != "https" || json == "null") return false;
            using var result = JsonDocument.Parse(json);
            int code = result.RootElement.GetProperty("status").GetInt32();
            if (code == 403) { status.Text = StateText("verification"); return false; }
            if (code is < 200 or >= 300) return false;
            string? body = result.RootElement.GetProperty("body").GetString();
            if (body is null || System.Text.Encoding.UTF8.GetByteCount(body) > 1_048_576) return false;
            var response = await engine.Request("captureXAI", prefs, pageText: body);
            prefs.XaiSubscriptionWebsiteConnected = true; prefs.Save();
            if (response.Result is { } state) update?.Invoke(state);
            poll.Stop(); if (!refreshing) Hide(); return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException or TimeoutException or JsonException or System.Runtime.InteropServices.COMException)
        { status.Text = StateText("mismatch"); return false; }
        finally { busy = false; }
    }
}
