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
    int generation;
    public QwenWebsiteWindow(EngineClient engine, Preferences prefs, Action<DisplayState> update)
    {
        this.engine = engine; this.prefs = prefs; this.update = update;
        Title = "Qwen"; Width = 1080; Height = 740; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Content = browser;
        Closing += async (_, e) =>
        {
            e.Cancel = true;
            var verifyLogin = IsVisible && Opacity == 1;
            var closedGeneration = generation;
            poll.Stop(); Hide();
            // Let the cancelled Closing event finish before showing the
            // hidden WebView for its bounded post-login quota read.
            await Task.Yield();
            if (verifyLogin && closedGeneration == generation && !IsVisible) await Refresh(afterLogin: true);
        };
        poll.Tick += async (_, _) => await Capture(generation);
    }
    public async Task Connect()
    {
        var current = ++generation;
        loading = false;
        poll.Stop();
        Opacity = 1; ShowActivated = true; ShowInTaskbar = true; Show(); Activate();
        try
        {
            await Initialize();
            if (current != generation) return;
            browser.CoreWebView2.Navigate(UsageURL); poll.Start();
        }
        catch { if (current == generation) Hide(); throw; }
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
    public async Task Refresh(bool afterLogin = false)
    {
        if ((!prefs.QwenWebsiteConnected && !afterLogin) || loading || IsVisible && Opacity == 1) return;
        var current = ++generation;
        loading = true;
        try
        {
            Opacity = 0; ShowActivated = false; ShowInTaskbar = false; Show();
            await Initialize();
            if (current != generation) return;
            browser.CoreWebView2.Navigate(UsageURL);
            for (var i = 0; i < 12; i++)
            {
                await Task.Delay(1500);
                if (current != generation) return;
                if (await Capture(current)) break;
            }
        }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException
            or System.ComponentModel.Win32Exception or WebView2RuntimeNotFoundException
            or IOException or UnauthorizedAccessException) { }
        finally
        {
            if (current == generation) { if (Opacity == 0) Hide(); loading = false; }
        }
    }
    async Task<bool> Capture(int current)
    {
        if (current != generation || busy || !initialized || !Uri.TryCreate(browser.Source?.AbsoluteUri, UriKind.Absolute, out var uri)
            || uri.Scheme != "https" || uri.Host != "platform.qianwenai.com" || !uri.AbsolutePath.Contains("/analytics/token-plan/")) return false;
        busy = true;
        try
        {
            var json = await browser.CoreWebView2.ExecuteScriptAsync("document.body.innerText.slice(0, 40000)");
            if (current != generation) return false;
            var text = JsonSerializer.Deserialize<string>(json);
            if (text is null) return false;
            var result = await engine.Request("captureQwen", prefs, pageText: text);
            if (current != generation) return false;
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
