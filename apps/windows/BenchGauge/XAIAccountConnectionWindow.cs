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
            Text = Tr("Sign in once with your CC Switch xAI account. BenchGauge refreshes independently; CC Switch can stay open.",
                "使用与 CC Switch 相同的 xAI 账号授权一次，AI 天梯即可独立更新余量，无需退出 CC Switch。",
                "使用與 CC Switch 相同的 xAI 帳號授權一次，AI 天梯即可獨立更新餘量，無需退出 CC Switch。") });
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
                if (result.LoginState == "saved")
                {
                    Hide();
                    if (result.Result is { } next) update?.Invoke(next);
                }
                else ShowState(result.LoginState ?? "failed");
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
            "accountChanged" => Tr("The selected login changed during authorization. Try again.", "授权期间所选账号发生了变化，请重新登录。", "授權期間所選帳號發生了變化，請重新登入。"),
            "storage" => Tr("Could not save the login. Check the BenchGauge data directory permissions and try again.", "登录未能保存，请检查 AI 天梯数据目录权限后重试。", "登入未能保存，請檢查 AI 天梯資料目錄權限後重試。"),
            "saved" => Tr("Signed in. Quota refreshes automatically, even while CC Switch is running.", "登录成功，余量会自动刷新，CC Switch 可保持运行。", "登入成功，餘量會自動刷新，CC Switch 可保持運行。"),
            _ => Tr("Authorization did not finish. Try again.", "授权未完成，请重试。", "授權未完成，請重試。")
        };
    }
}
