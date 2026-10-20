using System;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using BenchGauge.Shared;
using Button = System.Windows.Controls.Button;

namespace BenchGauge;

sealed partial class MainWindow
{
    async void ShowModelDetails(Entry entry)
    {
        modalOpen = true;
        try {
            if (entry.Details is null && engine is not null && (entry.DetailID is not null || entry.ModelMetadata is not null)) {
                var response = await engine.Request("modelDetails", prefs, pageText: entry.ModelMetadata?.GetRawText(), modelID: entry.DetailID);
                if (response.Error is { } error) throw new InvalidOperationException(error);
                entry = entry with { Details = response.ModelDetails };
            }
            CreateModelDetailsWindow(entry).ShowDialog();
        }
        catch (Exception error) when (error is IOException or TimeoutException or InvalidOperationException) {
            MessageBox.Show(this, Tr("Unable to load model details. Please try again.", "模型详情加载失败，请重试。", "模型詳情載入失敗，請重試。"),
                Tr("Model details", "模型详情", "模型詳情"), MessageBoxButton.OK, MessageBoxImage.Information);
        }
        finally { modalOpen = false; _ = Dispatcher.BeginInvoke(TryPresentPreparedUpdate); }
    }
    internal Window CreateModelDetailsWindow(Entry entry)
    {
        var dialog = new Window { Owner = this, Title = Tr("Model details", "模型详情", "模型詳情"),
            Width = 560, Height = 640, MinWidth = 360, MinHeight = 360, MaxHeight = SystemParameters.WorkArea.Height,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = PanelBackground, Foreground = PanelInk,
            FontFamily = FontFamily, FontSize = 13 };
        AutomationProperties.SetAutomationId(dialog, "model-details");
        var layout = new DockPanel(); dialog.Content = layout;
        var header = new Grid { Margin = new Thickness(20), HorizontalAlignment = HorizontalAlignment.Left };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        DockPanel.SetDock(header, Dock.Top); layout.Children.Add(header);
        var copy = new Button { Content = PanelIcon("copy", PanelInk, 18, 18), Width = 36, Height = 36,
            Background = Brushes.Transparent, BorderThickness = new Thickness(0), Margin = new Thickness(10, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Top, ToolTip = Tr("Copy model name", "复制模型名称", "複製模型名稱") };
        AutomationProperties.SetAutomationId(copy, "copy-model-name");
        AutomationProperties.SetName(copy, Tr("Copy model name", "复制模型名称", "複製模型名稱"));
        copy.Click += (_, _) => {
            try { Clipboard.SetText(entry.Name); copy.Content = new TextBlock { Text = "✓", FontSize = 20, Foreground = PanelInk };
                copy.ToolTip = Tr("Copied", "已复制", "已複製"); AutomationProperties.SetName(copy, (string)copy.ToolTip); }
            catch (System.Runtime.InteropServices.COMException) { copy.ToolTip = Tr("Copy failed", "复制失败", "複製失敗"); }
        };
        Grid.SetColumn(copy, 1); header.Children.Add(copy);
        header.Children.Add(new TextBlock { Text = entry.Name, FontSize = 21, FontWeight = FontWeights.SemiBold, Foreground = PanelInk,
            TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center });
        var content = new StackPanel { Margin = new Thickness(20, 0, 20, 20) };
        layout.Children.Add(new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        if (entry.Details is not { Length: > 0 }) content.Children.Add(new TextBlock {
            Text = Tr("No matching model information yet.", "暂未匹配到模型资料。", "暫未匹配到模型資料。"),
            Foreground = PanelMuted, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 20, 0, 20) });
        foreach (var section in entry.Details ?? [])
        {
            var rows = new StackPanel();
            foreach (var row in section.Rows)
            {
                if (row.Label.Length > 0) rows.Children.Add(new TextBlock { Text = row.Label, FontSize = 11, Foreground = PanelMuted,
                    TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 4) });
                if (row.Url is { } url && Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == "https" && uri.UserInfo.Length == 0)
                {
                    var link = new Button { Content = new TextBlock { Text = row.Value, TextWrapping = TextWrapping.Wrap, Foreground = PanelAccent },
                        Background = Brushes.Transparent, BorderThickness = new Thickness(0), HorizontalContentAlignment = HorizontalAlignment.Left };
                    link.Click += (_, _) => Open(url); rows.Children.Add(link);
                }
                else rows.Children.Add(new TextBlock { Text = row.Value, Foreground = PanelInk, TextWrapping = TextWrapping.Wrap });
            }
            var title = new StackPanel(); title.Children.Add(new TextBlock { Text = section.Title, Foreground = PanelInk,
                FontSize = 14, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
            if (section.Summary is { } summary) title.Children.Add(new TextBlock { Text = summary, Foreground = PanelMuted,
                FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 5, 0, 0) });
            FrameworkElement body;
            if (section.Summary is not null) body = new Expander { Header = title, Content = rows, Foreground = PanelInk, IsExpanded = false };
            else { var group = new StackPanel(); group.Children.Add(title); group.Children.Add(rows); body = group; }
            content.Children.Add(new Border { Child = body, Background = PanelSurface, CornerRadius = new CornerRadius(8),
                Padding = new Thickness(14), Margin = new Thickness(0, 0, 0, 14) });
        }
        return dialog;
    }
}
