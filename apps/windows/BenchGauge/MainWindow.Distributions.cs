using System;
using System.Linq;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BenchGauge.Shared;

namespace BenchGauge;
sealed partial class MainWindow
{
    FrameworkElement DistributionValue(int count, string percent)
    {
        var value = new Grid { Width = 82, VerticalAlignment = VerticalAlignment.Center };
        value.ColumnDefinitions.Add(new ColumnDefinition());
        value.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
        value.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
        var countText = Caption($"{count}", PanelMuted, 10, numeric: true);
        countText.TextAlignment = TextAlignment.Right; value.Children.Add(countText);
        var separator = Caption("·", PanelMuted, 10, numeric: true);
        separator.TextAlignment = TextAlignment.Center; Grid.SetColumn(separator, 1); value.Children.Add(separator);
        var percentText = Caption(percent, PanelMuted, 10, numeric: true);
        percentText.TextAlignment = TextAlignment.Right; Grid.SetColumn(percentText, 2); value.Children.Add(percentText);
        return value;
    }

    FrameworkElement DistributionCountryIcon(string id)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "flags", id.ToLowerInvariant() + ".png");
        if (id.Length == 2 && File.Exists(path)) return new Image { Source = new BitmapImage(new Uri(path)),
            Width = 18, Height = 14, Stretch = Stretch.Uniform, VerticalAlignment = VerticalAlignment.Center };
        return Center(Caption(id == "other" ? "◇" : "?", PanelMuted, 11));
    }

    FrameworkElement DistributionPanels(Board[] boards)
    {
        var host = new Grid { Margin = new Thickness(12), VerticalAlignment = VerticalAlignment.Top };
        System.Windows.Automation.AutomationProperties.SetAutomationId(host, "leaderboard-distributions");
        for (var i = 0; i < boards.Length; i++) {
            host.ColumnDefinitions.Add(new ColumnDefinition());
            var board = boards[i];
            var data = board.Distribution ?? LeaderboardDistribution.FromEntries(prefs.Grouping == "company" ? [] : board.Entries);
            var panel = new StackPanel { Margin = new Thickness(12) };
            panel.Children.Add(Caption(BoardTitle(board), PanelInk, 11));
            TextBlock Heading(string label) => new() { Text = label, FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = PanelInk, Margin = new Thickness(0, 12, 0, 8) };
            var countries = Heading(Tr("Country share", "国家占比", "國家占比"));
            System.Windows.Automation.AutomationProperties.SetAutomationId(countries, "country-distribution-heading"); panel.Children.Add(countries);
            panel.Children.Add(Caption(Tr($"{data.Total} models", $"{data.Total} 个模型", $"{data.Total} 個模型"), PanelMuted, 10));
            string CountryName(string key) => key switch {
                "unknown" => Tr("Unknown", "未知"), "other" => Tr("Other", "其他"),
                "CN" => Tr("China", "中国", "中國"), "US" => Tr("United States", "美国", "美國"),
                "CA" => Tr("Canada", "加拿大"), "FR" => Tr("France", "法国", "法國"),
                "DE" => Tr("Germany", "德国", "德國"), "SG" => Tr("Singapore", "新加坡"),
                _ => board.CountryOptions?.FirstOrDefault(option => LeaderboardDistribution.CountryKey(option.Value) == key)?.Label ?? key
            };
            if (data.Total == 0) panel.Children.Add(Caption(Tr("No model data yet", "暂无模型数据", "暫無模型資料"), PanelMuted, 11));
            foreach (var slice in data.Countries) {
                var row = new Grid { MinHeight = 22 };
                var nameWidth = prefs.Language == "en" ? 144 : 96;
                var nameColumn = new ColumnDefinition { Width = new GridLength(nameWidth) };
                row.ColumnDefinitions.Add(nameColumn); row.ColumnDefinitions.Add(new ColumnDefinition { MinWidth = 24 }); row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(82) });
                row.SizeChanged += (_, _) => nameColumn.Width = new GridLength(Math.Clamp(row.ActualWidth - 82 - 24, 96, nameWidth));
                var label = new DockPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) };
                var icon = new Border { Child = DistributionCountryIcon(slice.Id), Width = 18, Margin = new Thickness(0, 0, 4, 0) };
                DockPanel.SetDock(icon, Dock.Left); label.Children.Add(icon);
                var name = Caption(CountryName(slice.Id), PanelInk, 10); name.TextWrapping = TextWrapping.Wrap; name.ToolTip = name.Text; label.Children.Add(name); row.Children.Add(label);
                var track = new Grid { Height = 6, Background = Tint(panelDark ? "#333840" : "#E4E7EB"), VerticalAlignment = VerticalAlignment.Center };
                var bar = new Border { Background = Tint("#718FBE"), HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new CornerRadius(3) };
                track.Children.Add(bar); track.SizeChanged += (_, _) => bar.Width = track.ActualWidth * slice.Fraction;
                Grid.SetColumn(track, 1); row.Children.Add(track);
                var value = DistributionValue(slice.Count, slice.Percent); Grid.SetColumn(value, 2); row.Children.Add(value); panel.Children.Add(row);
            }
            var source = Heading(Tr("Source share", "源码占比", "原始碼占比"));
            System.Windows.Automation.AutomationProperties.SetAutomationId(source, "source-distribution-heading"); panel.Children.Add(source);
            Brush SourceColor(string id) => id is "open" or "closed" ? OpennessTint(id) : Tint("#9399A3");
            var stacked = new Grid { Height = 10, Background = Tint(panelDark ? "#333840" : "#E4E7EB"), Margin = new Thickness(0, 0, 0, 8) };
            for (var j = 0; j < data.Sources.Length; j++) {
                var slice = data.Sources[j]; stacked.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(slice.Count, GridUnitType.Star) });
                var segment = new Border { Background = SourceColor(slice.Id) }; Grid.SetColumn(segment, j); stacked.Children.Add(segment);
            }
            panel.Children.Add(stacked);
            foreach (var slice in data.Sources) {
                var row = new DockPanel { Height = 20 };
                var value = DistributionValue(slice.Count, slice.Percent); DockPanel.SetDock(value, Dock.Right); row.Children.Add(value);
                var icon = new Border { Child = slice.Id == "unknown" ? Center(Caption("?", PanelMuted, 11)) : OpennessBadge(slice.Id), Width = 18, Margin = new Thickness(0, 0, 6, 0) }; DockPanel.SetDock(icon, Dock.Left); row.Children.Add(icon);
                row.Children.Add(Caption(slice.Id == "open" ? Tr("Open", "开源", "開源") : slice.Id == "closed" ? Tr("Closed", "闭源", "閉源") : Tr("Unknown", "未知"), PanelInk, 11)); panel.Children.Add(row);
            }
            var basis = Caption(Tr("All models on this board · counts, not scores", "按全榜模型数量统计，不按分数加权", "按全榜模型數量統計，不按分數加權"), PanelMuted, 10); basis.TextWrapping = TextWrapping.Wrap; basis.Margin = new Thickness(0, 10, 0, 0); panel.Children.Add(basis);
            var card = new Border { Child = panel, Background = PanelSurface, CornerRadius = new CornerRadius(10), Margin = new Thickness(i == 0 ? 0 : 6, 0, i == boards.Length - 1 ? 0 : 6, 0) };
            Grid.SetColumn(card, i); host.Children.Add(card);
        }
        return host;
    }
}
