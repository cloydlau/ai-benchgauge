using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace BenchGauge;

/// The only dismissal is starting the prepared installer and shutting down.
sealed class PreparedUpdateDialog : Window
{
    bool installing, shuttingDown;
    readonly Button confirm;
    readonly TextBlock message;
    readonly Func<string, string, string?, string> tr;

    public PreparedUpdateDialog(Window owner, Func<string, string, string?, string> tr, Action install)
    {
        this.tr = tr;
        Owner = owner;
        Title = tr("New version found", "发现新版本", "發現新版本");
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        SizeToContent = SizeToContent.Height;
        Width = 380;
        Topmost = owner.Topmost;
        FontFamily = owner.FontFamily;
        FontSize = 13;
        var stack = new StackPanel { Margin = new Thickness(24) };
        stack.Children.Add(new TextBlock { Text = Title, FontWeight = FontWeights.Bold, FontSize = 16, Margin = new Thickness(0, 0, 0, 18) });
        message = new TextBlock { Text = tr("The new version has downloaded. Restart to apply it.", "新版本已下载完成，重启后生效。", "新版本已下載完成，重啟後生效。"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 18) };
        stack.Children.Add(message);
        confirm = new Button { Content = tr("Restart to update", "重启升级", "重啟升級"), IsDefault = true, HorizontalAlignment = HorizontalAlignment.Right, Padding = new Thickness(14, 6, 14, 6) };
        confirm.Click += (_, _) => { if (installing) return; installing = true; confirm.IsEnabled = false; install(); };
        stack.Children.Add(confirm);
        Content = stack;
        Closing += (_, e) => { if (!shuttingDown) e.Cancel = true; };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape || (e.Key == Key.System && e.SystemKey == Key.F4)) e.Handled = true; };
    }
    internal void PrepareForShutdown() { shuttingDown = true; }
    public void InstallationFailed()
    {
        installing = false;
        confirm.IsEnabled = true;
        message.Text = tr("Could not start the update. Try again.", "更新启动失败，请重试。", "更新啟動失敗，請重試。");
    }
}
