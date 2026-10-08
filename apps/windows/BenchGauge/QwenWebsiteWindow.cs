using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using BenchGauge.Shared;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace BenchGauge;
// Dedicated browser profile; no cookie/token export and no bridge injected into
// remote pages. Only the official page's rendered quota text crosses the pipe.
sealed class QwenWebsiteWindow : Window
{
    const string UsageURL = "https://platform.qianwenai.com/home/analytics/token-plan/individual";
    readonly WebView2 browser = new();
    readonly EngineClient engine;
    readonly Preferences prefs;
    readonly Action<DisplayState> update;
    readonly DispatcherTimer poll = new() { Interval = TimeSpan.FromSeconds(2) };
    bool busy, initialized, loading;
    public QwenWebsiteWindow(EngineClient engine, Preferences prefs, Action<DisplayState> update)
    {
        this.engine = engine; this.prefs = prefs; this.update = update;
        Title = "Qwen"; Width = 1080; Height = 740; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Content = browser;
        Closing += (_, e) => { e.Cancel = true; poll.Stop(); Hide(); };
        poll.Tick += async (_, _) => await Capture();
    }
    public async Task Connect()
    {
        Opacity = 1; ShowActivated = true; ShowInTaskbar = true; Show(); Activate();
        try { await Initialize(); browser.CoreWebView2.Navigate(UsageURL); poll.Start(); }
        catch { Hide(); throw; }
    }
    async Task Initialize()
    {
        if (initialized) return;
        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: Path.Combine(Preferences.DirectoryPath, "qwen-webview"));
        await browser.EnsureCoreWebView2Async(environment);
        browser.CoreWebView2.Settings.AreDevToolsEnabled = false;
        browser.CoreWebView2.Settings.IsWebMessageEnabled = false;
        browser.CoreWebView2.Settings.AreHostObjectsAllowed = false;
        browser.CoreWebView2.NavigationStarting += (_, e) =>
        {
            if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) || uri.Scheme != "https") e.Cancel = true;
        };
        browser.CoreWebView2.NewWindowRequested += (_, e) => { e.Handled = true; MainWindow.Open(e.Uri); };
        initialized = true;
    }
    public async Task Refresh()
    {
        if (!prefs.QwenWebsiteConnected || loading || IsVisible && Opacity == 1) return;
        loading = true;
        try
        {
            Opacity = 0; ShowActivated = false; ShowInTaskbar = false; Show();
            await Initialize();
            browser.CoreWebView2.Navigate(UsageURL);
            for (var i = 0; i < 12; i++) { await Task.Delay(1500); if (await Capture()) break; }
            Hide();
        }
        finally { if (Opacity == 0) Hide(); loading = false; }
    }
    async Task<bool> Capture()
    {
        if (busy || !initialized || !Uri.TryCreate(browser.Source?.AbsoluteUri, UriKind.Absolute, out var uri)
            || uri.Scheme != "https" || uri.Host != "platform.qianwenai.com" || !uri.AbsolutePath.Contains("/analytics/token-plan/")) return false;
        busy = true;
        try
        {
            var json = await browser.CoreWebView2.ExecuteScriptAsync("document.body.innerText.slice(0, 40000)");
            var text = JsonSerializer.Deserialize<string>(json);
            if (text is null) return false;
            var result = await engine.Request("captureQwen", prefs, pageText: text);
            // The shared parser distinguishes a quota from a rendered login,
            // missing-plan or query failure; a successful request isn't proof
            // that authentication succeeded.
            var captured = result.QwenQuotaCaptured == true;
            if (result.QwenAuthenticated == true)
            {
                prefs.QwenWebsiteConnected = true; prefs.Save();
            }
            if (result.Result is { } state) update(state);
            if (captured && IsVisible && Opacity == 1) { poll.Stop(); Hide(); }
            return captured;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException or TimeoutException or JsonException or System.Runtime.InteropServices.COMException) { return false; }
        finally { busy = false; }
    }
}
