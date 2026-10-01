using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BenchGauge.Shared;
using Inline = System.Windows.Documents.InlineUIContainer;
using TextRun = System.Windows.Documents.Run;

namespace BenchGauge;

// Keep the native WPF view in the same visual hierarchy as the Mac panel.
// Each horizontal row contains both sources; one scroll view keeps them aligned.
sealed partial class MainWindow
{
    double renderedPanelWidth;
    bool panelMenuOpen;
    static readonly Brush PanelInk = new SolidColorBrush(Color.FromRgb(35, 35, 37));
    static readonly Brush PanelMuted = new SolidColorBrush(Color.FromRgb(119, 119, 123));
    static readonly Brush PanelLine = new SolidColorBrush(Color.FromRgb(221, 221, 224));
    static readonly Brush PanelBlue = new SolidColorBrush(Color.FromRgb(0, 112, 227));
    static readonly Brush PanelPurple = new SolidColorBrush(Color.FromRgb(156, 53, 202));
    static readonly Dictionary<string, string> BrandColors = new(StringComparer.OrdinalIgnoreCase)
    {
        ["openai"] = "#10A37F", ["anthropic"] = "#D97757", ["google"] = "#4285F4",
        ["qwen"] = "#623AE7", ["deepseek"] = "#4D6BFE", ["zai"] = "#3A3A3A",
        ["kimi"] = "#1677FF", ["spacexai"] = "#242424", ["mistral"] = "#F29D38",
        ["ideogram"] = "#404040", ["meta"] = "#0866FF", ["minimax"] = "#F23D75",
        ["tencent"] = "#0052D9", ["nvidia"] = "#76B900", ["bytedance"] = "#00C9CD",
    };
    static Brush Tint(string hex, double opacity = 1) => new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)) { Opacity = opacity };
    static TextBlock Caption(string text, Brush? foreground = null, double size = 11) => new()
    {
        Text = text, Foreground = foreground ?? PanelMuted, FontSize = size,
        VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis,
    };
    static Binding ParentBinding(string property) => new(property) { RelativeSource = RelativeSource.TemplatedParent };

    void ConfigurePanelStyles()
    {
        Foreground = PanelInk;
        var buttonTemplate = new ControlTemplate(typeof(Button));
        var frame = new FrameworkElementFactory(typeof(Border), "frame");
        frame.SetValue(Border.CornerRadiusProperty, new CornerRadius(5));
        frame.SetBinding(Border.BackgroundProperty, ParentBinding("Background"));
        frame.SetBinding(Border.BorderBrushProperty, ParentBinding("BorderBrush"));
        frame.SetBinding(Border.BorderThicknessProperty, ParentBinding("BorderThickness"));
        frame.SetBinding(Border.PaddingProperty, ParentBinding("Padding"));
        var label = new FrameworkElementFactory(typeof(ContentPresenter));
        label.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        label.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        frame.AppendChild(label); buttonTemplate.VisualTree = frame;
        var hover = new Trigger { Property = Button.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty, Tint("#E9E9EC"), "frame"));
        buttonTemplate.Triggers.Add(hover);
        var pressed = new Trigger { Property = Button.IsPressedProperty, Value = true };
        pressed.Setters.Add(new Setter(Border.BackgroundProperty, Tint("#DDDEE2"), "frame"));
        buttonTemplate.Triggers.Add(pressed);
        var disabled = new Trigger { Property = Button.IsEnabledProperty, Value = false };
        disabled.Setters.Add(new Setter(Button.OpacityProperty, 0.5)); buttonTemplate.Triggers.Add(disabled);
        var buttons = new Style(typeof(Button));
        buttons.Setters.Add(new Setter(Button.TemplateProperty, buttonTemplate));
        buttons.Setters.Add(new Setter(Button.ForegroundProperty, PanelInk));
        buttons.Setters.Add(new Setter(Button.BackgroundProperty, Brushes.Transparent));
        buttons.Setters.Add(new Setter(Button.BorderThicknessProperty, new Thickness(0)));
        buttons.Setters.Add(new Setter(Button.CursorProperty, Cursors.Hand));
        buttons.Setters.Add(new Setter(Button.FontSizeProperty, 11.0));
        Resources[typeof(Button)] = buttons;

        var template = new ControlTemplate(typeof(ComboBox));
        var grid = new FrameworkElementFactory(typeof(Grid));
        var toggle = new FrameworkElementFactory(typeof(ToggleButton));
        toggle.SetValue(ToggleButton.FocusableProperty, false);
        toggle.SetBinding(ToggleButton.IsCheckedProperty, new Binding("IsDropDownOpen") { RelativeSource = RelativeSource.TemplatedParent, Mode = BindingMode.TwoWay });
        var toggleTemplate = new ControlTemplate(typeof(ToggleButton));
        var outline = new FrameworkElementFactory(typeof(Border));
        outline.SetValue(Border.BackgroundProperty, Brushes.White);
        outline.SetValue(Border.BorderBrushProperty, PanelLine);
        outline.SetValue(Border.BorderThicknessProperty, new Thickness(1));
        outline.SetValue(Border.CornerRadiusProperty, new CornerRadius(5));
        toggleTemplate.VisualTree = outline; toggle.SetValue(ToggleButton.TemplateProperty, toggleTemplate);
        grid.AppendChild(toggle);
        var selection = new FrameworkElementFactory(typeof(ContentPresenter));
        selection.SetBinding(ContentPresenter.ContentProperty, ParentBinding("SelectionBoxItem"));
        selection.SetBinding(ContentPresenter.ContentTemplateProperty, ParentBinding("SelectionBoxItemTemplate"));
        selection.SetValue(ContentPresenter.MarginProperty, new Thickness(8, 2, 23, 2));
        selection.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        selection.SetValue(ContentPresenter.IsHitTestVisibleProperty, false); grid.AppendChild(selection);
        var arrow = new FrameworkElementFactory(typeof(TextBlock));
        arrow.SetValue(TextBlock.TextProperty, "⌄"); arrow.SetValue(TextBlock.ForegroundProperty, PanelMuted);
        arrow.SetValue(TextBlock.MarginProperty, new Thickness(0, 0, 7, 2));
        arrow.SetValue(TextBlock.HorizontalAlignmentProperty, HorizontalAlignment.Right);
        arrow.SetValue(TextBlock.VerticalAlignmentProperty, VerticalAlignment.Center);
        arrow.SetValue(TextBlock.IsHitTestVisibleProperty, false); grid.AppendChild(arrow);
        var popup = new FrameworkElementFactory(typeof(Popup), "PART_Popup");
        popup.SetValue(Popup.PlacementProperty, PlacementMode.Bottom); popup.SetValue(Popup.AllowsTransparencyProperty, true);
        popup.SetBinding(Popup.IsOpenProperty, ParentBinding("IsDropDownOpen"));
        var popupFrame = new FrameworkElementFactory(typeof(Border));
        popupFrame.SetValue(Border.BackgroundProperty, Brushes.White);
        popupFrame.SetValue(Border.BorderBrushProperty, PanelLine);
        popupFrame.SetValue(Border.BorderThicknessProperty, new Thickness(1));
        popupFrame.SetValue(Border.PaddingProperty, new Thickness(5));
        popupFrame.SetValue(Border.CornerRadiusProperty, new CornerRadius(5));
        popupFrame.AppendChild(new FrameworkElementFactory(typeof(ItemsPresenter)));
        popup.AppendChild(popupFrame); grid.AppendChild(popup); template.VisualTree = grid;
        var combos = new Style(typeof(ComboBox)); combos.Setters.Add(new Setter(ComboBox.TemplateProperty, template));
        combos.Setters.Add(new Setter(ComboBox.ForegroundProperty, PanelInk));
        combos.Setters.Add(new Setter(ComboBox.FontSizeProperty, 11.0)); Resources[typeof(ComboBox)] = combos;
    }

    void RenderPanel(Func<Task>? manageAccounts = null)
    {
        rendering = true;
        try
        {
            renderedPanelWidth = ActualWidth > 0 ? ActualWidth : Width;
            (status.Parent as Panel)?.Children.Remove(status);
            dropdowns.Clear(); content.Children.Clear(); content.RowDefinitions.Clear();
            for (var i = 0; i < 4; i++) content.RowDefinitions.Add(new RowDefinition { Height = i == 2 ? new GridLength(1, GridUnitType.Star) : GridLength.Auto });
            Place(PanelHeader(manageAccounts), 0);
            quotaPanel.Children.Clear();
            if (state?.QuotaNeedsCCSwitch == true) quotaPanel.Children.Add(QuotaPlaceholder());
            foreach (var quota in state?.Quotas ?? []) quotaPanel.Children.Add(QuotaCard(quota));
            if (state?.QuotaUnavailable == true) quotaPanel.Children.Add(Caption(Tr("CC Switch data unavailable", "CC Switch 数据暂不可用", "CC Switch 資料暫不可用"), Tint("#C87816")));
            Place(quotaArea, 1);
            Place(PairedBoards(), 2);
            footer = PanelFooter(); Place(footer, 3);
        }
        finally { rendering = false; }
    }

    FrameworkElement PanelHeader(Func<Task>? manageAccounts)
    {
        var header = new StackPanel { Margin = new Thickness(18, 9, 18, 10) };
        var titleLine = new Grid(); titleLine.ColumnDefinitions.Add(new ColumnDefinition()); titleLine.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var brand = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        headerTitle = new TextBlock { Text = "AI BenchGauge", FontFamily = new FontFamily("Segoe Script"), FontWeight = FontWeights.Bold, FontSize = 21, Height = 27, Foreground = PanelInk };
        brand.Children.Add(headerTitle);
        updateButton = QuietButton("v" + config.Version + (availableUpdate is null ? "" : " ↑"), async () => await CheckUpdates(true));
        updateButton.Foreground = Tint("#C6C6CA"); updateButton.Margin = new Thickness(8, 0, 0, 0); brand.Children.Add(updateButton);
        titleLine.Children.Add(brand);
        var freshness = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        freshness.Children.Add(Caption(Tr("UPDATED", "更新时间", "更新時間")));
        freshness.Children.Add(FreshnessPill(Tr("Boards ", "榜单 ", "榜單 ") + BoardFreshness(), state?.Boards.Any(board => board.Error is not null) == true));
        freshness.Children.Add(FreshnessPill(Tr("Quotas ", "余量 ", "餘量 ") + (state?.Quotas.Any() == true ? Tr("loaded", "已读取", "已讀取") : Tr("pending", "待更新", "待更新")), state?.QuotaUnavailable == true));
        Grid.SetColumn(freshness, 1); titleLine.Children.Add(freshness);
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        tabs.Children.Add(Segments([("model",Tr("Models","模型")),("company",Tr("Companies","公司"))], prefs.Grouping, 180,
            async value => { prefs.Grouping = value; SaveFrame(); await Refresh("state"); if (engine is null) Render(); }));
        var categories = Segments([("general",Tr("General","综合","綜合")),("coding",Tr("Coding","编程","編程")),("image",Tr("Image","图片","圖片")),("video",Tr("Video","视频","視頻"))], prefs.Category, 360,
            async value => { prefs.Category = value; SaveFrame(); await Refresh("state"); await Refresh("refreshBoards"); if (engine is null) Render(); });
        categories.Margin = new Thickness(8, 0, 0, 0); tabs.Children.Add(categories);
        if (renderedPanelWidth >= 1100)
        {
            // Equal side columns keep both segmented controls centered.
            var wide = new Grid(); wide.ColumnDefinitions.Add(new ColumnDefinition()); wide.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); wide.ColumnDefinitions.Add(new ColumnDefinition());
            titleLine.Children.Remove(brand); titleLine.Children.Remove(freshness);
            wide.Children.Add(brand); Grid.SetColumn(tabs, 1); wide.Children.Add(tabs); Grid.SetColumn(freshness, 2); wide.Children.Add(freshness);
            freshness.HorizontalAlignment = HorizontalAlignment.Right; header.Children.Add(wide);
        }
        else { header.Children.Add(titleLine); tabs.Margin = new Thickness(0, 8, 0, 0); header.Children.Add(tabs); }
        if (manageAccounts is not null)
        {
            var accounts = QuietButton(Tr("Manage accounts", "管理账号", "管理帳號"), manageAccounts);
            accounts.Foreground = PanelMuted; accounts.HorizontalAlignment = HorizontalAlignment.Right; accounts.IsEnabled = engine is not null;
            header.Children.Add(accounts);
        }
        return header;
    }
    string BoardFreshness()
    {
        var date = state?.Boards.Select(board => DateTimeOffset.TryParse(board.UpdatedAt, out var d) ? (DateTimeOffset?)d : null).Where(d => d.HasValue).Max();
        if (date is null) return Tr("pending", "待更新");
        var days = Math.Max(0, (DateTimeOffset.UtcNow - date.Value).Days);
        return days > 0 ? Tr($"{days}d ago", $"{days} 天前") : Tr("today", "今天");
    }
    FrameworkElement FreshnessPill(string text, bool failed) => new Border
    {
        Background = Tint(failed ? "#FFF0DE" : "#F1F1F3"), CornerRadius = new CornerRadius(10),
        Padding = new Thickness(8, 2, 8, 2), Margin = new Thickness(8, 0, 0, 0), MinWidth = 80,
        Child = Caption(text, failed ? Tint("#B96B0F") : PanelMuted, 10),
    };
    FrameworkElement Segments((string Value, string Title)[] items, string selected, double width, Func<string, Task> change)
    {
        var grid = new Grid();
        for (var i = 0; i < items.Length; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition()); var value = items[i].Value;
            var button = QuietButton(items[i].Title, async () => { await change(value); });
            button.Background = value == selected ? Brushes.White : Brushes.Transparent;
            button.BorderBrush = PanelLine; button.BorderThickness = new Thickness(value == selected ? 1 : 0);
            button.FontWeight = value == selected ? FontWeights.Medium : FontWeights.Normal;
            button.Padding = new Thickness(4, 1, 4, 1); button.HorizontalAlignment = HorizontalAlignment.Stretch;
            button.VerticalAlignment = VerticalAlignment.Stretch; Grid.SetColumn(button, i); grid.Children.Add(button);
        }
        return new Border { Child = grid, Width = width, Height = 22, Background = Tint("#F1F1F3"), BorderBrush = PanelLine, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(5) };
    }
    Button QuietButton(string text, Action action) => Quiet(Button(text, action));
    Button QuietButton(string text, Func<Task> action) => Quiet(Button(text, action));
    static Button Quiet(Button button) { button.Padding = new Thickness(2, 0, 2, 0); button.Margin = new Thickness(0); button.Foreground = PanelMuted; return button; }

    FrameworkElement QuotaPlaceholder()
    {
        var line = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        line.Children.Add(Caption(Tr("Install ", "安装 ", "安裝 ")));
        var link = QuietButton("CC Switch", () => Open("https://github.com/farion1231/cc-switch/releases/latest")); link.Foreground = PanelBlue;
        ((Button)link).ToolTip = Tr("Download CC Switch", "下载 CC Switch", "下載 CC Switch"); line.Children.Add(link);
        line.Children.Add(Caption(Tr(" to see provider quotas here.", "，即可在这里查看各家提供商的余量。", "，即可在這裡查看各家提供者的餘量。")));
        return new Border { Child = line, Width = Math.Max(1, renderedPanelWidth - 36), Height = 28, Background = Tint("#F8F8FA"),
            BorderBrush = PanelLine, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6) };
    }
    FrameworkElement QuotaCard(Quota quota)
    {
        var text = new TextBlock { FontSize = 11, VerticalAlignment = VerticalAlignment.Center, ToolTip = quota.Help };
        if (ProviderLogo(quota.Name) is { } key && Logo(key, 16) is { } image)
        {
            var mark = new Border { Child = image, Width = 17, Height = 17, Background = Brushes.White, CornerRadius = new CornerRadius(3), Margin = new Thickness(0, 0, 5, -3) };
            text.Inlines.Add(new Inline(mark) { BaselineAlignment = BaselineAlignment.Center });
        }
        text.Inlines.Add(new TextRun(quota.Name + "  ") { FontWeight = quota.IsCurrent ? FontWeights.SemiBold : FontWeights.Medium });
        foreach (var run in quota.Runs) text.Inlines.Add(new TextRun(run.Text) { Foreground = Tint(run.Light) });
        if (quota.IsStale) text.Inlines.Add(new TextRun(" · " + Tr("saved", "缓存", "快取")) { Foreground = PanelMuted });
        var fill = quota.AccentLight is { } accent ? Tint(accent, quota.IsCurrent ? 0.12 : 0.06) : Tint("#F1F1F3");
        var card = new Border { Child = text, Padding = new Thickness(7, 3, 7, 3), CornerRadius = new CornerRadius(5), Background = fill,
            Margin = new Thickness(0, 0, 6, 6), BorderThickness = new Thickness(quota.IsCurrent ? 1 : 0), BorderBrush = Tint("#238D50") };
        if (quota.CanConnect || quota.Url is not null) { card.Cursor = Cursors.Hand; card.MouseLeftButtonUp += async (_, _) => { if (quota.CanConnect) await Connect(quota); else if (quota.Url is { } url) Open(url); }; }
        return card;
    }
    static string? ProviderLogo(string name)
    {
        var value = name.ToLowerInvariant();
        foreach (var item in new[] { ("openai","openai"),("claude","anthropic"),("gemini","google"),("kimi","kimi"),("qwen","qwen"),("千问","qwen"),("deepseek","deepseek"),("glm","zai"),("grok","spacexai"),("智谱","zai") })
            if (value.Contains(item.Item1)) return item.Item2;
        return null;
    }
    static Image? Logo(string key, double size)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "logos", key + ".png");
        return File.Exists(path) ? new Image { Source = new BitmapImage(new Uri(path)), Width = size, Height = size, Stretch = Stretch.Uniform } : null;
    }

    FrameworkElement PairedBoards()
    {
        var pair = state?.Boards.Take(2).ToArray() ?? [];
        var table = new Grid(); table.RowDefinitions.Add(new RowDefinition { Height = new GridLength(24) }); table.RowDefinitions.Add(new RowDefinition());
        var headings = TableGrid(); headings.Background = Tint("#FCFCFC"); headings.Height = 24;
        AddCell(headings, Caption(Tr("Rank", "排名", "排名"), PanelInk) is { } rank ? Center(rank) : throw new InvalidOperationException(), 0);
        AddCell(headings, Caption(Tr("Score", "分数", "分數"), PanelInk) is { } leftScore ? Center(leftScore) : throw new InvalidOperationException(), 2);
        AddCell(headings, Caption(Tr("Score", "分数", "分數"), PanelInk) is { } rightScore ? Center(rightScore) : throw new InvalidOperationException(), 5);
        for (var i = 0; i < pair.Length; i++)
        {
            var board = pair[i]; var column = i == 0 ? 1 : 4;
            var summary = new TextBlock { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, FontSize = 9,
                Margin = new Thickness(5, 0, 4, 0), ToolTip = board.Error ?? board.Title + "\n" + Tr("Scores are not directly comparable across lists", "两榜分数不直接互比", "兩榜分數不直接互比") };
            var name = BoardTitle(board); var date = DateTimeOffset.TryParse(board.UpdatedAt, out var d) ? d.ToLocalTime().ToString("M/d HH:mm", CultureInfo.InvariantCulture) : "";
            summary.Inlines.Add(new TextRun(name + (date.Length == 0 ? "" : " · " + date) + " · "));
            summary.Inlines.Add(new TextRun(board.Error is not null ? Tr("Refresh failed", "刷新失败", "刷新失敗") : SourceLens(board)) { Foreground = board.Error is not null ? Tint("#B96B0F") : i == 0 ? PanelBlue : PanelPurple });
            summary.Cursor = Cursors.Hand; summary.MouseLeftButtonUp += (_, _) => Open(board.Url); AddCell(headings, summary, column);
            AddCell(headings, CountryPicker(board), column + 2);
        }
        var outline = new Border { Child = headings, BorderBrush = PanelLine, BorderThickness = new Thickness(1, 1, 1, 1) }; table.Children.Add(outline);
        var rows = new StackPanel();
        var entries = pair.Select(board => board.Entries.Where(entry => prefs.Countries.GetValueOrDefault(board.Kind, "") is { } filter && (filter.Length == 0 || entry.Country == filter)).ToArray()).ToArray();
        var count = entries.Length == 0 ? 20 : Math.Max(1, entries.Max(values => values.Length));
        for (var index = 0; index < count; index++)
        {
            var row = TableGrid(); row.Height = 32; row.Background = index % 2 == 0 ? Brushes.White : Tint("#F3F3F5");
            AddCell(row, Rank(index + 1), 0);
            for (var side = 0; side < entries.Length; side++)
            {
                var column = side == 0 ? 1 : 4;
                if (index >= entries[side].Length) continue;
                var entry = entries[side][index]; AddCell(row, ModelCell(entry), column);
                AddCell(row, Center(Caption(entry.Score.ToString("0.0", CultureInfo.InvariantCulture), PanelMuted, 13)), column + 1);
                AddCell(row, Flag(entry.Country), column + 2);
            }
            rows.Children.Add(row);
        }
        var scroll = new ScrollViewer { Content = rows, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        Grid.SetRow(scroll, 1); table.Children.Add(scroll);
        return table;
    }
    Grid TableGrid()
    {
        var grid = new Grid(); var compact = renderedPanelWidth < 850;
        foreach (var width in new[] { new GridLength(60), new GridLength(1, GridUnitType.Star), new GridLength(compact ? 56 : 78), new GridLength(compact ? 44 : 84), new GridLength(1, GridUnitType.Star), new GridLength(compact ? 56 : 78), new GridLength(compact ? 44 : 84) })
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        return grid;
    }
    static TextBlock Center(TextBlock text) { text.TextAlignment = TextAlignment.Center; text.HorizontalAlignment = HorizontalAlignment.Stretch; return text; }
    static FrameworkElement Rank(int rank)
    {
        if (rank > 3) return Center(Caption(rank.ToString(CultureInfo.InvariantCulture), PanelInk, 13));
        // The medal stays legible on Windows installations without color emoji.
        var grid = new Grid { Width = 18, Height = 23, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        var ribbon = new System.Windows.Shapes.Path { Data = Geometry.Parse("M 4,0 L 8,0 L 11,8 L 7,8 Z M 10,0 L 14,0 L 11,8 L 7,8 Z"), Fill = Tint(rank == 1 ? "#FFB900" : rank == 2 ? "#86A0A7" : "#E0783D") };
        grid.Children.Add(ribbon);
        grid.Children.Add(new Border { Width = 13, Height = 13, CornerRadius = new CornerRadius(7), Background = Tint(rank == 1 ? "#F8BF24" : rank == 2 ? "#B8BEC4" : "#C78C5C"), VerticalAlignment = VerticalAlignment.Bottom,
            Child = Center(Caption(rank.ToString(CultureInfo.InvariantCulture), Brushes.White, 9)) }); return grid;
    }
    FrameworkElement ModelCell(Entry entry)
    {
        var row = new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) }); row.ColumnDefinitions.Add(new ColumnDefinition());
        if (entry.Logo is { } key && Logo(key, 16) is { } logo)
            AddCell(row, new Border { Child = logo, Width = 20, Height = 20, Background = Brushes.White, CornerRadius = new CornerRadius(4), Margin = new Thickness(0, 0, 4, 0) }, 0);
        var name = Caption(entry.Name, PanelInk, 13); name.Margin = new Thickness(6, 0, 3, 0); AddCell(row, name, 1);
        if (entry.CodingURL is not null || entry.ApiURL is not null)
        {
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var links = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            if (entry.CodingURL is { } coding) links.Children.Add(LinkButton("↗", coding, Tr("Coding plan", "编程套餐")));
            if (entry.ApiURL is { } api) links.Children.Add(LinkButton("API", api, Tr("API pricing", "API 价格")));
            AddCell(row, links, 2);
        }
        var color = entry.Logo is { } logoKey && BrandColors.TryGetValue(logoKey, out var hex) ? Tint(hex, 0.34) : Brushes.Transparent;
        var cell = new Border { Child = row, Background = color, CornerRadius = new CornerRadius(5), Padding = new Thickness(4, 0, 3, 0), Margin = new Thickness(12, 4, 8, 4), ToolTip = entry.Help ?? entry.Name, Cursor = Cursors.Hand };
        cell.MouseLeftButtonUp += (_, _) => { try { Clipboard.SetText(entry.Name); status.Text = Tr("Copied", "已复制", "已複製"); } catch (System.Runtime.InteropServices.COMException) { } };
        return cell;
    }
    string BoardTitle(Board board) => board.Kind switch
    {
        "artificialAnalysis" => "Artificial Analysis Intelligence Index", "arenaText" => "Arena | Text",
        "artificialAnalysisCoding" => "Artificial Analysis Coding Index", "arenaWebdev" => "Arena | Code",
        _ => board.Title,
    };
    string SourceLens(Board board) => board.Kind switch
    {
        "artificialAnalysis" => Tr("Task evaluation", "任务测评", "任務測評"), "arenaText" => Tr("User preference", "用户盲测", "使用者盲測"),
        "artificialAnalysisCoding" => Tr("Coding evaluation", "代码测评", "程式碼測評"), "arenaWebdev" => Tr("Web development", "网页开发", "網頁開發"), _ => "",
    };
    FrameworkElement CountryPicker(Board board)
    {
        var button = QuietButton(Tr("Country ⌄", "国家 ⌄", "國家 ⌄"), () => { }); button.Foreground = PanelInk;
        var menu = new ContextMenu();
        foreach (var item in new[] { ("",Tr("All countries","所有国家","所有國家")),("china",Tr("China","中国","中國")),("unitedStates",Tr("United States","美国","美國")),("canada",Tr("Canada","加拿大")),("france",Tr("France","法国","法國")),("germany",Tr("Germany","德国","德國")),("singapore",Tr("Singapore","新加坡")) })
        {
            var value = item.Item1; var choice = new MenuItem { Header = item.Item2, IsCheckable = true, IsChecked = prefs.Countries.GetValueOrDefault(board.Kind, "") == value };
            choice.Click += (_, _) => { prefs.Countries[board.Kind] = value; SaveFrame(); Render(); }; menu.Items.Add(choice);
        }
        menu.Opened += (_, _) => panelMenuOpen = true;
        menu.Closed += (_, _) => panelMenuOpen = false;
        button.Click += (_, _) => { panelMenuOpen = true; menu.PlacementTarget = button; menu.Placement = PlacementMode.Bottom; menu.IsOpen = true; };
        button.ToolTip = Tr("Filter this source by country", "按国家筛选此榜单", "依國家篩選此榜單"); return button;
    }
    static FrameworkElement Flag(string? country)
    {
        var group = new DrawingGroup();
        void Rect(string color, double x, double y, double w, double h) => group.Children.Add(new GeometryDrawing(Tint(color), null, new RectangleGeometry(new Rect(x, y, w, h))));
        switch (country)
        {
            case "unitedStates":
                Rect("#FFFFFF",0,0,21,14); for (var i=0;i<7;i++) Rect("#D84B52",0,i*2,21,1); Rect("#375886",0,0,9,8);
                for(var y=1;y<8;y+=2) for(var x=1;x<9;x+=2) Rect("#FFFFFF",x,y,0.6,0.6); break;
            case "china":
                Rect("#D9333C",0,0,21,14); group.Children.Add(new GeometryDrawing(Tint("#FDE077"),null,Geometry.Parse("M 4,2 L 4.7,4 L 7,4 L 5.2,5.3 L 5.8,7.5 L 4,6.2 L 2.2,7.5 L 2.8,5.3 L 1,4 L 3.3,4 Z"))); break;
            case "france": Rect("#2850A0",0,0,7,14);Rect("#FFFFFF",7,0,7,14);Rect("#E85B60",14,0,7,14);break;
            case "germany": Rect("#252525",0,0,21,5);Rect("#D54649",0,5,21,4);Rect("#F2C453",0,9,21,5);break;
            case "canada":
                Rect("#E84B50",0,0,5,14);Rect("#FFFFFF",5,0,11,14);Rect("#E84B50",16,0,5,14);
                group.Children.Add(new GeometryDrawing(Tint("#E84B50"),null,Geometry.Parse("M 10.5,2 L 12,5 L 14,4 L 13,7 L 15,8 L 12,10 L 11,10 L 11,12 L 10,12 L 10,10 L 9,10 L 6,8 L 8,7 L 7,4 L 9,5 Z")));break;
            case "singapore": Rect("#DD4851",0,0,21,7);Rect("#FFFFFF",0,7,21,7);group.Children.Add(new GeometryDrawing(Brushes.White,null,new EllipseGeometry(new Point(4,3.5),2.4,2.4)));group.Children.Add(new GeometryDrawing(Tint("#DD4851"),null,new EllipseGeometry(new Point(5,3.5),2,2)));break;
            default: return Center(Caption(country is null ? "–" : country, PanelMuted, 10));
        }
        return new Image { Source = new DrawingImage(group), Width = 21, Height = 14, Stretch = Stretch.Fill, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, ToolTip = country };
    }

    DockPanel PanelFooter()
    {
        var dock = new DockPanel { LastChildFill = true, Height = 48, Background = Brushes.White };
        var border = new Border { BorderBrush = PanelLine, BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(18, 10, 18, 10) };
        var row = new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        left.Children.Add(QuietButton("◉", () => Open("https://github.com/" + config.Repository)));
        left.Children.Add(Caption(" Cloyd Lau · ", PanelMuted, 10)); left.Children.Add(QuietButton("MIT License", () => ShowLicenses(false)));
        left.Children.Add(Caption(" · ", PanelMuted, 10)); left.Children.Add(QuietButton(Tr("Open-source notices", "开源声明", "開源聲明"), () => ShowLicenses(true))); row.Children.Add(left);
        var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (renderedPanelWidth >= 850)
        {
            right.Children.Add(Caption(Tr("Sources ", "数据来源 ", "資料來源 "), PanelMuted, 10));
            var sources = state?.Boards.Take(2).ToArray() ?? [];
            for (var i = 0; i < sources.Length; i++) { var source = sources[i]; if (i > 0) right.Children.Add(Caption(" · ")); right.Children.Add(QuietButton(source.Kind.StartsWith("artificialAnalysis") ? "Artificial Analysis ↗" : "Arena ↗", () => Open(source.Url))); }
            right.Children.Add(Caption(" · "));
        }
        right.Children.Add(QuietButton("▣ " + Tr("Copy", "截图", "截圖"), Capture)); right.Children.Add(Caption(" · "));
        right.Children.Add(Select([("clickToClose",Tr("Keep open","保持打开","保持打開")),("alwaysOnTop",Tr("Always on top","保持置顶","保持置頂")),("closeOnBlur",Tr("Close on blur","失焦关闭","失焦關閉")),("window",Tr("Window","独立窗口","獨立視窗"))], prefs.PanelMode,
            value => { SaveFrame(); prefs.PanelMode = value; ApplyMode(); SaveFrame(); Reveal(); return Task.CompletedTask; }));
        right.Children.Add(Caption(" · ")); right.Children.Add(Segments([("en","EN"),("zh","简中"),("zh-Hant","繁中")], prefs.Language, renderedPanelWidth < 850 ? 120 : 150,
            async value => { prefs.Language = value; SaveFrame(); Render(); await Refresh("state"); }));
        right.Children.Add(Caption(" · ")); right.Children.Add(QuietButton("⏻ " + Tr("Quit", "退出", "退出"), () => { Stop(); Application.Current.Shutdown(); }));
        Grid.SetColumn(right, 2); row.Children.Add(right);
        status.Margin = new Thickness(4, 0, 4, 0); status.FontSize = 10; Grid.SetColumn(status, 1); row.Children.Add(status);
        border.Child = row; dock.Children.Add(border); return dock;
    }
}
