using System;
using System.IO;
using System.Linq;
using System.Windows.Controls.Primitives;
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
        var header = new Grid { Margin = new Thickness(20), HorizontalAlignment = HorizontalAlignment.Stretch };
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
        var content = new StackPanel { Margin = new Thickness(20, 0, 20, 72) };
        var scroll = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        var scrolling = new Grid(); layout.Children.Add(scrolling); scrolling.Children.Add(scroll);
        var top = new Button { Content = "↑", Width = 44, Height = 44, FontSize = 21,
            Background = PanelSurface, Foreground = PanelInk, BorderThickness = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(20), Visibility = Visibility.Collapsed,
            ToolTip = Tr("Back to top", "返回顶部", "返回頂部") };
        AutomationProperties.SetAutomationId(top, "model-details-back-to-top");
        AutomationProperties.SetName(top, (string)top.ToolTip);
        top.Click += (_, _) => scroll.ScrollToTop();
        scroll.ScrollChanged += (_, _) => top.Visibility = scroll.VerticalOffset > 240 ? Visibility.Visible : Visibility.Collapsed;
        scrolling.Children.Add(top);
        if (entry.Details is not { Length: > 0 }) content.Children.Add(new TextBlock {
            Text = Tr("No matching model information yet.", "暂未匹配到模型资料。", "暫未匹配到模型資料。"),
            Foreground = PanelMuted, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 20, 0, 20) });
        int Order(string id) => id switch { "limits" => 0, "capabilities" => 1, "modalities" => 2, "general" => 3, "source" => 9, _ => 4 };
        foreach (var section in (entry.Details ?? []).OrderBy(section => Order(section.Id)))
        {
            var tiles = section.Id is "limits" or "capabilities";
            Panel rows = tiles ? new UniformGrid { Columns = 2 } : new StackPanel();
            foreach (var row in section.Rows)
            {
                var fact = new StackPanel { Margin = tiles ? new Thickness(0) : new Thickness(0, 10, 0, 10) };
                if (row.Label.Length > 0) fact.Children.Add(new TextBlock { Text = row.Label, FontSize = 11, Foreground = PanelMuted,
                    TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 6) });
                if (row.Url is { } url && Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == "https" && uri.UserInfo.Length == 0)
                {
                    var link = new Button { Content = new TextBlock { Text = row.Value, TextWrapping = TextWrapping.Wrap, Foreground = PanelAccent },
                        Background = Brushes.Transparent, BorderThickness = new Thickness(0), HorizontalContentAlignment = HorizontalAlignment.Left };
                    link.Click += (_, _) => Open(url); fact.Children.Add(link);
                }
                else fact.Children.Add(new TextBlock { Text = row.Value, Foreground = PanelInk, TextWrapping = TextWrapping.Wrap,
                    FontSize = tiles ? section.Id == "limits" ? 19 : 14 : 13, FontWeight = tiles ? FontWeights.SemiBold : FontWeights.Normal });
                rows.Children.Add(new Border { Child = fact, Background = tiles ? PanelBackground : Brushes.Transparent,
                    CornerRadius = new CornerRadius(9), Padding = tiles ? new Thickness(12) : new Thickness(0),
                    Margin = tiles ? new Thickness(0, 4, 8, 4) : new Thickness(0) });
            }
            var title = new StackPanel { Margin = new Thickness(0, 3, 0, 6) };
            title.Children.Add(new TextBlock { Text = section.Title, Foreground = PanelInk,
                FontSize = 14, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
            title.Children.Add(new TextBlock { Text = section.Summary ?? $"{section.Rows.Length} {Tr("facts", "项资料", "項資料")}", Foreground = PanelMuted,
                FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) });
            var body = new Expander { Header = title, Content = rows, Foreground = PanelInk,
                IsExpanded = section.Id is "limits" or "capabilities" or "modalities" };
            content.Children.Add(new Border { Child = body, Background = PanelSurface, CornerRadius = new CornerRadius(14),
                Padding = new Thickness(16), Margin = new Thickness(0, 0, 0, 10) });
        }
        return dialog;
    }
}
