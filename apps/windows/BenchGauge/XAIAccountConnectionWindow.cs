using System;
using System.Threading;
using System.Threading.Tasks;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using BenchGauge.Shared;

namespace BenchGauge;

sealed class XAIAccountConnectionWindow : Window
{
    readonly EngineClient? engine;
    readonly Preferences prefs;
    readonly Action<DisplayState>? update;
    readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, FontSize = 13 };
    readonly TextBox code = new() { IsReadOnly = true, BorderThickness = new Thickness(0), FontSize = 23,
        FontWeight = FontWeights.SemiBold, FontFamily = new FontFamily("Consolas"), IsReadOnlyCaretVisible = false };
    readonly Button retry = new(), copy = new(), close = new();
    readonly ProgressBar progress = new() { IsIndeterminate = true, Height = 3, Margin = new Thickness(0, 12, 0, 0) };
    Task? loginTask;
    CancellationTokenSource? cancellation;
    string? authorizationURL;
    bool shutdown;
    string Tr(string en, string zh, string hant) => prefs.Language == "en" ? en : prefs.Language == "zh-Hant" ? hant : zh;

    public XAIAccountConnectionWindow(EngineClient? engine, Preferences prefs, Action<DisplayState>? update, string fixtureState = "starting")
    {
        this.engine = engine; this.prefs = prefs; this.update = update;
        Title = Tr("Sign in to xAI", "登录 xAI", "登入 xAI");
        Width = 520; Height = 350; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var stack = new StackPanel { Margin = new Thickness(24) };
        stack.Children.Add(new TextBlock { Text = Title, FontSize = 17, FontWeight = FontWeights.Bold });
        stack.Children.Add(new TextBlock { Margin = new Thickness(0, 18, 0, 18), FontSize = 13, TextWrapping = TextWrapping.Wrap,
            Text = Tr("Sign in with the same xAI account as CC Switch. Both apps share this login; your refresh token stays on this computer.",
                "请使用与 CC Switch 相同的 xAI 账号登录。两边共用此登录，刷新令牌只保存在本机。",
                "請使用與 CC Switch 相同的 xAI 帳號登入。兩邊共用此登入，刷新令牌只保存在本機。") });
        stack.Children.Add(code);
        status.Margin = new Thickness(0, 18, 0, 18); stack.Children.Add(status);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var button in new[] { retry, copy, close }) { button.Padding = new Thickness(10, 4, 10, 4); button.Margin = new Thickness(0, 0, 10, 0); buttons.Children.Add(button); }
        stack.Children.Add(buttons); stack.Children.Add(progress); Content = stack;
        retry.Click += (_, _) => { if (authorizationURL is { } url) Open(url); else Begin(); };
        copy.Click += (_, _) => { try { Clipboard.SetText(code.Text); } catch (System.Runtime.InteropServices.COMException) { } };
        close.Click += (_, _) => Close();
        Closing += (_, e) => { Cancel(); if (!shutdown) { e.Cancel = true; Hide(); } };
        code.Text = fixtureState == "waiting" ? "Q2QH-TEST" : "";
        ShowState(fixtureState);
    }

    public void SetAppearance(bool dark)
    {
        Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(dark ? "#1E1E1F" : "#FFFFFF"));
        Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(dark ? "#ECECEF" : "#232325"));
        code.Background = Background; code.Foreground = Foreground;
        foreach (var button in new[] { retry, copy, close }) { button.Foreground = Foreground; button.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(dark ? "#303033" : "#F1F1F3")); }
    }

    public void Connect() { Show(); Activate(); Begin(); }
    void Begin()
    {
        if (engine is null || loginTask is not null) return;
        cancellation?.Dispose(); cancellation = new CancellationTokenSource();
        authorizationURL = null; code.Text = ""; ShowState("starting");
        loginTask = Run(cancellation.Token);
    }
    async Task Run(CancellationToken cancel)
    {
        try
        {
            var attempt = await engine!.Request("connectXAI", prefs);
            cancel.ThrowIfCancellationRequested();
            if (attempt.LoginState != "waiting" || attempt.AuthorizationURL is not { } url || attempt.LoginID is not { } id || attempt.UserCode is not { } userCode)
            { ShowState(attempt.LoginState ?? "failed"); return; }
            authorizationURL = url; code.Text = userCode; ShowState("waiting");
            if (!Open(url)) { ShowState("network"); return; }
            var interval = attempt.PollInterval ?? 5;
            while (true)
            {
                await Task.Delay(TimeSpan.FromSeconds(Math.Clamp(interval, 1, 86400)), cancel);
                var result = await engine.Request("pollXAI", prefs, loginID: id);
                cancel.ThrowIfCancellationRequested();
                if (result.LoginState == "waiting") { interval = result.PollInterval ?? interval; continue; }
                ShowState(result.LoginState ?? "failed");
                if (result.LoginState == "saved" && result.Result is { } next) update?.Invoke(next);
                return;
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception e) when (e is IOException or TimeoutException or InvalidOperationException) { if (!cancel.IsCancellationRequested) ShowState("network"); }
        finally
        {
            authorizationURL = null;
            try { await engine!.Request("cancelXAI", prefs); } catch (Exception e) when (e is IOException or TimeoutException or InvalidOperationException) { }
            loginTask = null;
        }
    }
    static bool Open(string raw)
    {
        if (!Uri.TryCreate(raw, UriKind.Absolute, out var url) || url.Scheme != "https" || url.Host != "accounts.x.ai" || url.AbsolutePath != "/oauth2/device" || !url.IsDefaultPort || url.UserInfo != "" || url.Fragment != "") return false;
        try { Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true }); return true; }
        catch (System.ComponentModel.Win32Exception) { return false; }
    }
    void Cancel() { cancellation?.Cancel(); }
    public void CloseForShutdown() { shutdown = true; Cancel(); Close(); }
    void ShowState(string state)
    {
        var waiting = state == "waiting"; var starting = state == "starting"; var saved = state == "saved";
        retry.Content = waiting ? Tr("Open authorization page", "打开授权页", "開啟授權頁") : Tr("Try again", "重试", "重試");
        retry.IsEnabled = !starting && !saved;
        copy.Content = Tr("Copy code", "复制授权码", "複製授權碼"); copy.Visibility = waiting ? Visibility.Visible : Visibility.Collapsed;
        code.Visibility = waiting ? Visibility.Visible : Visibility.Collapsed;
        close.Content = saved ? Tr("Done", "完成", "完成") : Tr("Cancel", "取消", "取消");
        progress.Visibility = waiting || starting ? Visibility.Visible : Visibility.Collapsed;
        status.Text = state switch
        {
            "starting" => Tr("Preparing browser authorization…", "正在准备浏览器授权…", "正在準備瀏覽器授權…"),
            "waiting" => Tr("Finish signing in in your browser. Quota refreshes automatically.", "请在浏览器中完成登录，授权成功后自动刷新余量。", "請在瀏覽器中完成登入，授權成功後自動刷新餘量。"),
            "expired" => Tr("The code expired. Try again to get a new authorization link.", "授权码已过期，请重试以获取新的授权链接。", "授權碼已過期，請重試以取得新的授權連結。"),
            "denied" => Tr("Authorization was declined. Try again when you are ready.", "授权已被拒绝，可以重新发起登录。", "授權已被拒絕，可以重新發起登入。"),
            "network" => Tr("The auth service could not be reached. Check your connection and try again.", "暂时无法连接授权服务，请检查网络后重试。", "暫時無法連接授權服務，請檢查網絡後重試。"),
            "accountMismatch" => Tr("This is a different xAI account. Try again with the account used in CC Switch.", "登录的 xAI 账号与 CC Switch 中的账号不同，请使用原账号重试。", "登入的 xAI 帳號與 CC Switch 中的帳號不同，請使用原帳號重試。"),
            "accountChanged" => Tr("The shared login changed during authorization. Try again.", "授权期间共用登录发生了变化，请重新登录。", "授權期間共用登入發生了變化，請重新登入。"),
            "storage" => Tr("Could not save the shared login. Check the CC Switch directory permissions and try again.", "共用登录未能保存，请检查 CC Switch 目录权限后重试。", "共用登入未能保存，請檢查 CC Switch 目錄權限後重試。"),
            "saved" => Tr("Signed in. BenchGauge refreshes automatically. Restart a running CC Switch to load the shared login.", "登录成功，BenchGauge 会自动刷新余量。如 CC Switch 正在运行，请重启它以载入共用登录。", "登入成功，BenchGauge 會自動刷新餘量。如 CC Switch 正在運行，請重啟它以載入共用登入。"),
            _ => Tr("Authorization did not finish. Try again.", "授权未完成，请重试。", "授權未完成，請重試。")
        };
    }
}
