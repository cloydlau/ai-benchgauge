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
using WpfButton = System.Windows.Controls.Button;
using TextRun = System.Windows.Documents.Run;
using NativeButton = System.Windows.Controls.Button;

namespace BenchGauge;

// Keep the native WPF view in the same visual hierarchy as the Mac panel.
// Each horizontal row contains both sources; one scroll view keeps them aligned.
sealed partial class MainWindow
{
    double renderedPanelWidth;
    bool panelMenuOpen;
    bool panelRefreshing;
    bool panelDark = ReadSystemDark();
    readonly Dictionary<string, TimestampPolishClock> timestampPolishClocks = [];
    readonly List<TimestampPolish> timestampPolishViews = [];
    Brush PanelInk => Tint(panelDark ? "#F2F5FA" : "#20262F");
    Brush PanelMuted => Tint(panelDark ? "#A2ACBA" : "#687382");
    Brush PanelLine => Tint(panelDark ? "#343B46" : "#DFE3E9");
    Brush PanelAccent => Tint(panelDark ? "#D1DCE8" : "#414D5C");
    Brush PanelBlue => Tint(panelDark ? "#6FB3FF" : "#0070E3");
    Brush PanelPurple => Tint(panelDark ? "#D0A0F5" : "#9C35CA");
    Brush PanelBackground => Tint(panelDark ? "#101216" : "#FFFFFF");
    Brush PanelSurface => Tint(panelDark ? "#272E38" : "#E7EAF0");
    Brush PanelSelection => new LinearGradientBrush(new GradientStopCollection
    {
        new((Color)ColorConverter.ConvertFromString(panelDark ? "#4A5564" : "#FFFFFF"), 0),
        new((Color)ColorConverter.ConvertFromString(panelDark ? "#2F3743" : "#E1E6ED"), 0.55),
        new((Color)ColorConverter.ConvertFromString(panelDark ? "#3B4553" : "#F1F4F8"), 1),
    }, 90);
    bool? visualDarkOverride;
    static bool ReadSystemDark()
    {
        try { using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"); return key?.GetValue("AppsUseLightTheme") is int value && value == 0; }
        catch (System.Security.SecurityException) { return false; }
    }
    public void SetVisualAppearance(bool dark) { visualDarkOverride = dark; panelDark = dark; ConfigurePanelStyles(); Background = PanelBackground; Render(); }
    void SystemAppearanceChanged(object? sender, Microsoft.Win32.UserPreferenceChangedEventArgs args)
    {
        Dispatcher.BeginInvoke(() => { if (closing || visualDarkOverride.HasValue || ReadSystemDark() == panelDark) return; panelDark = ReadSystemDark(); ConfigurePanelStyles(); Background = PanelBackground; Render(); });
    }
    static readonly Dictionary<string, string> BrandColors = new(StringComparer.OrdinalIgnoreCase)
    {
        ["openai"] = "#10A37F", ["anthropic"] = "#D97757", ["google"] = "#4285F4",
        ["qwen"] = "#623AE7", ["deepseek"] = "#4D6BFE", ["zai"] = "#3A3A3A",
        ["kimi"] = "#007CFF", ["spacexai"] = "#242424", ["mistral"] = "#F29D38",
        ["ideogram"] = "#404040", ["meta"] = "#0068D5", ["minimax"] = "#F21985",
        ["tencent"] = "#0052D9", ["nvidia"] = "#76B900", ["bytedance"] = "#3C8CFF",
    };
    static Brush Tint(string hex, double opacity = 1) => new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)) { Opacity = opacity };
    TextBlock Caption(string text, Brush? foreground = null, double size = 11, bool numeric = false)
    {
        var label = new TextBlock { Text = text, Foreground = foreground ?? PanelMuted, FontSize = size,
            FontFamily = new FontFamily(numeric ? "Consolas" : "Segoe UI"), VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis };
        CenterTextInk(label); return label;
    }
    static void CenterTextInk(TextBlock label)
    {
        // WPF centres the line box, whose ascent/descent leave visible ink low.
        // Measure the actual glyphs so Latin and CJK labels use their own metrics.
        label.Loaded += (_, _) =>
        {
            if (label.Text.Length == 0 || label.ActualWidth <= 0 || label.ActualHeight <= 0) return;
            var dpi = VisualTreeHelper.GetDpi(label);
            var glyphs = new FormattedText(label.Text, CultureInfo.GetCultureInfo(label.Language.IetfLanguageTag), label.FlowDirection,
                new Typeface(label.FontFamily, label.FontStyle, label.FontWeight, label.FontStretch), label.FontSize,
                label.Foreground, dpi.PixelsPerDip)
            { MaxTextWidth = Math.Max(1, label.ActualWidth), MaxLineCount = 1, Trimming = label.TextTrimming };
            var ink = glyphs.BuildGeometry(new Point()).Bounds;
            if (!ink.IsEmpty) label.RenderTransform = new TranslateTransform(0,
                Math.Round((label.ActualHeight / 2 - ink.Top - ink.Height / 2) * dpi.DpiScaleY, MidpointRounding.AwayFromZero) / dpi.DpiScaleY);
        };
    }
    // Draw both header labels with the same native text renderer. TextBlock's
    // line baseline can differ from FormattedText's, especially for script fonts.
    static FrameworkElement HeaderInk(TextBlock spec) => new HeaderInkLabel(spec)
    { Height = 27, VerticalAlignment = VerticalAlignment.Center };

    sealed class HeaderInkLabel : FrameworkElement
    {
        static readonly BitmapImage LightBrandLogo = LoadBrandLogo("header-logo.png");
        static readonly BitmapImage DarkBrandLogo = LoadBrandLogo("header-logo-dark.png");
        BitmapImage BrandLogo => spec.Foreground is SolidColorBrush brush && brush.Color.R + brush.Color.G + brush.Color.B > 384
            ? DarkBrandLogo : LightBrandLogo;
        static BitmapImage LoadBrandLogo(string name)
        {
            var image = new BitmapImage();
            image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
            image.UriSource = new Uri(Path.Combine(AppContext.BaseDirectory, "brand", name));
            image.EndInit(); image.Freeze(); return image;
        }
        readonly TextBlock spec;
        public bool AlignInkTop { get; init; }
        public bool DimsAmpersand { get; init; }
        public double VisibleInkHeight => spec.Text == "AI 天梯"
            ? BrandGlyphs().Max(glyph => glyph.Ink.Height) : Text().BuildGeometry(new Point()).Bounds.Height;
        public double VisibleInkTop {
            get {
                if (spec.Text == "AI 天梯") return (ActualHeight - VisibleInkHeight) / 2;
                var bounds = Text().BuildGeometry(new Point()).Bounds;
                var scale = VisualTreeHelper.GetDpi(this).DpiScaleY;
                return bounds.Top + Math.Round((ActualHeight / 2 - bounds.Top - bounds.Height / 2) * scale,
                    MidpointRounding.AwayFromZero) / scale;
            }
        }
        public HeaderInkLabel(TextBlock spec)
        {
            this.spec = spec;
            System.Windows.Automation.AutomationProperties.SetName(this, spec.Text);
        }
        protected override System.Windows.Automation.Peers.AutomationPeer OnCreateAutomationPeer() => new HeaderInkPeer(this);
        sealed class HeaderInkPeer(HeaderInkLabel owner) : System.Windows.Automation.Peers.FrameworkElementAutomationPeer(owner)
        {
            protected override System.Windows.Automation.Peers.AutomationControlType GetAutomationControlTypeCore() => System.Windows.Automation.Peers.AutomationControlType.Text;
            protected override bool IsContentElementCore() => true;
        }
        FormattedText Text()
        {
            var text = new FormattedText(spec.Text, CultureInfo.GetCultureInfo(spec.Language.IetfLanguageTag), spec.FlowDirection,
                new Typeface(spec.FontFamily, spec.FontStyle, spec.FontWeight, spec.FontStretch), spec.FontSize,
                spec.Foreground, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            foreach (var separator in Enumerable.Range(0, spec.Text.Length).Where(index => DimsAmpersand && spec.Text[index] is '&' or '?'))
            {
                var muted = spec.Foreground.Clone();
                muted.Opacity *= 0.55;
                text.SetForegroundBrush(muted, separator, 1);
            }
            return text;
        }
        const double BrandGap = 2.5;
        List<(FormattedText Text, Rect Ink, double X)> BrandGlyphs()
        {
            var result = new List<(FormattedText, Rect, double)>();
            double x = 0;
            foreach (var character in "AI天梯")
            {
                var latin = character is 'A' or 'I';
                var family = latin ? new FontFamily("Segoe UI")
                    : new FontFamily(new Uri("pack://application:,,,/"), "./Fonts/#BenchGauge Calligraphy");
                var text = new FormattedText(character.ToString(), CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                    new Typeface(family, FontStyles.Normal, latin ? FontWeights.SemiBold : FontWeights.Normal, FontStretches.Normal),
                    latin ? 21 : 25, spec.Foreground, VisualTreeHelper.GetDpi(this).PixelsPerDip);
                var ink = text.BuildGeometry(new Point()).Bounds;
                result.Add((text, ink, x));
                x += ink.Width + BrandGap;
            }
            return result;
        }
        protected override Size MeasureOverride(Size available)
        {
            if (spec.Text == "AI 天梯")
            {
                var glyphs = BrandGlyphs();
                return new Size(glyphs[^1].X + glyphs[^1].Ink.Width, 27);
            }
            return new Size(Text().WidthIncludingTrailingWhitespace, double.IsNaN(Height) ? 27 : Height);
        }
        protected override void OnRender(DrawingContext drawing)
        {
            if (spec.Text == "AI 天梯")
            {
                var glyphs = BrandGlyphs();
                var first = glyphs[0];
                var height = glyphs[1].Ink.Height;
                var width = height * BrandLogo.PixelWidth / BrandLogo.PixelHeight;
                drawing.DrawImage(BrandLogo, new Rect(first.X + first.Ink.Width - width,
                    (ActualHeight - height) / 2, width, height));
                foreach (var glyph in glyphs.Skip(1))
                    drawing.DrawText(glyph.Text, new Point(glyph.X - glyph.Ink.Left,
                        ActualHeight / 2 - glyph.Ink.Top - glyph.Ink.Height / 2));
                return;
            }
            var text = Text();
            var bounds = text.BuildGeometry(new Point()).Bounds;
            if (bounds.IsEmpty) return;
            var dpi = VisualTreeHelper.GetDpi(this);
            var offset = AlignInkTop ? -bounds.Top : Math.Round((ActualHeight / 2 - bounds.Top - bounds.Height / 2) * dpi.DpiScaleY,
                MidpointRounding.AwayFromZero) / dpi.DpiScaleY;
            if (spec.Text == "AI BenchGauge")
            {
                var next = new FormattedText("I", CultureInfo.GetCultureInfo(spec.Language.IetfLanguageTag), spec.FlowDirection,
                    new Typeface(spec.FontFamily, spec.FontStyle, spec.FontWeight, spec.FontStretch), spec.FontSize,
                    spec.Foreground, dpi.PixelsPerDip).BuildGeometry(new Point()).Bounds;
                var nextOrigin = text.BuildHighlightGeometry(new Point(), 1, 1).Bounds.Left;
                text.SetForegroundBrush(Brushes.Transparent, 0, 1);
                var logoHeight = next.Height;
                var logoWidth = logoHeight * BrandLogo.PixelWidth / BrandLogo.PixelHeight;
                drawing.DrawImage(BrandLogo, new Rect(nextOrigin + next.Left - BrandGap - logoWidth,
                    offset + next.Top, logoWidth, logoHeight));
            }
            drawing.DrawText(text, new Point(0, offset));
        }
    }

    // Center the caption block on the title's painted ink, in both languages.
    sealed class HeaderCaptionStack(HeaderInkLabel title, params HeaderInkLabel[] captions) : Panel
    {
        const double RowGap = 2;
        double Scale => Math.Min(1, Math.Max(1, title.VisibleInkHeight - 3) /
            Math.Max(1, captions.Sum(caption => caption.Height) + RowGap * (captions.Length - 1)));
        public void AddLabels() { foreach (var caption in captions) Children.Add(caption); }
        protected override Size MeasureOverride(Size available) {
            foreach (var caption in captions) {
                caption.Height = caption.VisibleInkHeight;
                caption.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            }
            return new Size(captions.Max(caption => caption.DesiredSize.Width) * Scale, 27);
        }
        protected override Size ArrangeOverride(Size size) {
            var scale = Scale;
            var height = (captions.Sum(caption => caption.Height) + RowGap * (captions.Length - 1)) * scale;
            var y = title.VisibleInkTop + (title.VisibleInkHeight - height) / 2;
            foreach (var caption in captions) {
                caption.RenderTransform = new ScaleTransform(scale, scale);
                caption.Arrange(new Rect(0, y, caption.DesiredSize.Width, caption.Height));
                y += (caption.Height + RowGap) * scale;
            }
            return size;
        }
    }

    static Binding ParentBinding(string property) => new(property) { RelativeSource = RelativeSource.TemplatedParent };

    void ConfigurePanelStyles()
    {
        Foreground = PanelInk; Background = PanelBackground;
        var buttonTemplate = new ControlTemplate(typeof(NativeButton));
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
        var hover = new Trigger { Property = WpfButton.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty, Tint(panelDark ? "#3A3A3D" : "#E9E9EC"), "frame"));
        buttonTemplate.Triggers.Add(hover);
        var pressed = new Trigger { Property = WpfButton.IsPressedProperty, Value = true };
        pressed.Setters.Add(new Setter(Border.BackgroundProperty, Tint(panelDark ? "#4A4A4F" : "#DDDEE2"), "frame"));
        buttonTemplate.Triggers.Add(pressed);
        var disabled = new Trigger { Property = WpfButton.IsEnabledProperty, Value = false };
        disabled.Setters.Add(new Setter(WpfButton.OpacityProperty, 0.5)); buttonTemplate.Triggers.Add(disabled);
        var buttons = new Style(typeof(NativeButton));
        buttons.Setters.Add(new Setter(WpfButton.TemplateProperty, buttonTemplate));
        buttons.Setters.Add(new Setter(WpfButton.ForegroundProperty, PanelInk));
        buttons.Setters.Add(new Setter(WpfButton.BackgroundProperty, Brushes.Transparent));
        buttons.Setters.Add(new Setter(WpfButton.BorderThicknessProperty, new Thickness(0)));
        buttons.Setters.Add(new Setter(WpfButton.CursorProperty, Cursors.Hand));
        buttons.Setters.Add(new Setter(WpfButton.FontSizeProperty, 11.0));
        buttons.Setters.Add(new Setter(WpfButton.FontFamilyProperty, new FontFamily("Segoe UI")));
        Resources[typeof(NativeButton)] = buttons;

        var template = new ControlTemplate(typeof(ComboBox));
        var grid = new FrameworkElementFactory(typeof(Grid));
        var toggle = new FrameworkElementFactory(typeof(ToggleButton));
        toggle.SetValue(ToggleButton.FocusableProperty, false);
        toggle.SetBinding(ToggleButton.IsCheckedProperty, new Binding("IsDropDownOpen") { RelativeSource = RelativeSource.TemplatedParent, Mode = BindingMode.TwoWay });
        var toggleTemplate = new ControlTemplate(typeof(ToggleButton));
        var outline = new FrameworkElementFactory(typeof(Border));
        outline.SetValue(Border.BackgroundProperty, PanelBackground);
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
        var arrow = new FrameworkElementFactory(typeof(System.Windows.Shapes.Path));
        arrow.SetValue(System.Windows.Shapes.Path.DataProperty, Geometry.Parse("M0,0 L3,3 L6,0"));
        arrow.SetValue(System.Windows.Shapes.Path.StrokeProperty, PanelMuted);
        arrow.SetValue(System.Windows.Shapes.Path.StrokeThicknessProperty, 1.2);
        arrow.SetValue(System.Windows.Shapes.Path.StretchProperty, Stretch.Uniform);
        arrow.SetValue(FrameworkElement.WidthProperty, 7.0); arrow.SetValue(FrameworkElement.HeightProperty, 4.0);
        arrow.SetValue(FrameworkElement.MarginProperty, new Thickness(0, 0, 8, 0));
        arrow.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Right);
        arrow.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        arrow.SetValue(UIElement.IsHitTestVisibleProperty, false); grid.AppendChild(arrow);
        var popup = new FrameworkElementFactory(typeof(Popup), "PART_Popup");
        popup.SetValue(Popup.PlacementProperty, PlacementMode.Bottom); popup.SetValue(Popup.AllowsTransparencyProperty, true);
        popup.SetBinding(Popup.IsOpenProperty, ParentBinding("IsDropDownOpen"));
        var popupFrame = new FrameworkElementFactory(typeof(Border));
        popupFrame.SetValue(Border.BackgroundProperty, PanelBackground);
        popupFrame.SetValue(Border.BorderBrushProperty, PanelLine);
        popupFrame.SetValue(Border.BorderThicknessProperty, new Thickness(1));
        popupFrame.SetValue(Border.PaddingProperty, new Thickness(5));
        popupFrame.SetValue(Border.CornerRadiusProperty, new CornerRadius(5));
        popupFrame.AppendChild(new FrameworkElementFactory(typeof(ItemsPresenter)));
        popup.AppendChild(popupFrame); grid.AppendChild(popup); template.VisualTree = grid;
        var combos = new Style(typeof(ComboBox)); combos.Setters.Add(new Setter(ComboBox.TemplateProperty, template));
        combos.Setters.Add(new Setter(ComboBox.ForegroundProperty, PanelInk));
        combos.Setters.Add(new Setter(ComboBox.FontFamilyProperty, new FontFamily("Segoe UI")));
        combos.Setters.Add(new Setter(ComboBox.FontSizeProperty, 11.0)); Resources[typeof(ComboBox)] = combos;
    }

    void RenderPanel(Func<Task>? manageAccounts = null)
    {
        timestampPolishViews.Clear();
        foreach (var clock in timestampPolishClocks.Values) clock.Update(!VisibleBoardsLoading);
        var restoreSearchFocus = leaderboardSearchField?.IsKeyboardFocusWithin == true;
        var searchCaret = leaderboardSearchField?.CaretIndex ?? 0;
        rendering = true;
        try
        {
            Title = BrandName;
            if (Tray?.ContextMenuStrip?.Items.Count > 0) Tray.ContextMenuStrip.Items[0].Text = BrandName;
            UpdatePanelWidth();
            renderedPanelWidth = Content is FrameworkElement client && client.ActualWidth > 0 ? client.ActualWidth : Width;
            (status.Parent as Panel)?.Children.Remove(status);
            dropdowns.Clear(); content.Children.Clear(); content.RowDefinitions.Clear();
            for (var i = 0; i < 4; i++) content.RowDefinitions.Add(new RowDefinition { Height = i == 2 ? new GridLength(1, GridUnitType.Star) : GridLength.Auto });
            Place(PanelHeader(), 0);
            quotaPanel.Children.Clear();
            if (state?.QuotaNeedsCCSwitch == true) quotaPanel.Children.Add(QuotaPlaceholder());
            foreach (var quota in state?.Quotas ?? []) quotaPanel.Children.Add(QuotaCard(quota));
            if (state?.QuotaUnavailable == true) quotaPanel.Children.Add(Caption(Tr("CC Switch data unavailable", "CC Switch 数据暂不可用", "CC Switch 資料暫不可用"), Tint("#C87816")));
            if (manageAccounts is not null) quotaPanel.Children.Add(AddModelButton(manageAccounts));
            quotaPanel.Margin = new Thickness(18, 0, 18, quotaPanel.Children.Count == 0 ? 1 : 3);
            Place(quotaArea, 1);
            Place(PairedBoards(), 2);
            footer = PanelFooter(); Place(footer, 3);
            if (restoreSearchFocus) Dispatcher.BeginInvoke(() => {
                if (leaderboardSearchExpanded && leaderboardSearchField is { } field) {
                    field.Focus(); field.CaretIndex = Math.Min(searchCaret, field.Text.Length);
                }
            }, System.Windows.Threading.DispatcherPriority.Input);
        }
        finally { rendering = false; }
    }

    FrameworkElement PanelHeader()
    {
        var header = new StackPanel { Margin = new Thickness(18, 9, 18, 10) };
        var titleLine = new Grid(); titleLine.ColumnDefinitions.Add(new ColumnDefinition()); titleLine.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var brand = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        headerTitle = new TextBlock { Text = BrandName,
            FontFamily = new FontFamily("Segoe Script"), FontWeight = FontWeights.Bold,
            FontSize = 21, Height = 27, Foreground = PanelInk };
        var titleInk = (HeaderInkLabel)HeaderInk(headerTitle);
        brand.Children.Add(titleInk);
        HeaderInkLabel SubtitleRow(string text) {
            var spec = Caption(text, PanelMuted, 11);
            spec.FontWeight = FontWeights.SemiBold;
            return new HeaderInkLabel(spec) { AlignInkTop = true, DimsAmpersand = true };
        }
        var captions = new HeaderCaptionStack(titleInk,
            SubtitleRow(Tr("Compare leaderboards to make informed choices;", "多榜对照，选得明白；", "多榜對照，選得明白；")),
            SubtitleRow(Tr("track quotas to know where you stand.", "余量追踪，用得有数。", "餘量追蹤，用得有數。"))) {
            Height = 27, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0)
        };
        captions.AddLabels();
        brand.Children.Add(captions);
        titleLine.Children.Add(brand);
        var freshness = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (state?.Quotas.Any() == true || state?.QuotaUnavailable == true)
        {
            var quotaTime = UpdateAge.Parse(state.QuotaUpdatedAt);
            var quotaAge = UpdateAge.Format(quotaTime, DateTimeOffset.UtcNow, prefs.Language);
            var text = state.Quotas.Length == 0 ? Tr("Quota unavailable", "余量暂不可读", "餘量暫不可讀")
                : quotaTime is null ? Tr("Quota pending", "余量待更新", "餘量待更新")
                : Tr($"Quotas updated {quotaAge}", $"余量{quotaAge}更新", $"餘量{quotaAge}更新");
            freshness.Children.Add(Caption(text, state.QuotaUnavailable ? Tint("#B96B0F") : PanelMuted, 11));
        }
        freshness.Cursor = Cursors.Hand;
        freshness.ToolTip = (UpdateAge.Parse(state?.QuotaUpdatedAt) is { } quotaStamp
            ? Tr("Quotas updated: ", "余量更新于：", "餘量更新於：") + quotaStamp.ToLocalTime().ToString("g", CultureInfo.CurrentCulture) + "\n" : "")
            + Tr("Click to refresh boards and quotas", "点击刷新榜单与余量", "點擊重新整理榜單與餘量");
        freshness.MouseLeftButtonUp += async (_, _) => { if (panelRefreshing) return; panelRefreshing = true; try { await Task.WhenAll(Refresh("refreshBoards"), Refresh("refreshQuotas")); } finally { panelRefreshing = false; } };
        Grid.SetColumn(freshness, 1); titleLine.Children.Add(freshness);
        var compactTabs = prefs.VisibleBoardKinds().Length == 1;
        var switches = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        switches.Children.Add(Segments([("model",Tr("Models","模型")),("company",Tr("Companies","公司"))], prefs.Grouping, 180,
            async value => { prefs.Grouping = value; SaveFrame(); await Refresh("state"); if (engine is null) Render(); }, compact: compactTabs));
        var categories = Segments([("usage",Tr("Usage","用量","用量")),("general",Tr("General","综合","綜合")),("coding",Tr("Coding","编程","編程")),("image",Tr("Image","图片","圖片")),("video",Tr("Video","视频","視頻"))], prefs.Category, 420,
            async value => { prefs.Category = value; SaveFrame(); await Refresh("refreshBoardsIfStale"); if (engine is null) Render(); }, compact: compactTabs);
        categories.Margin = new Thickness(8, 0, 0, 0); switches.Children.Add(categories);
        var tabs = SearchNavigation(switches);
        var natural = new Size(double.PositiveInfinity, double.PositiveInfinity);
        brand.Measure(natural); tabs.Measure(natural); freshness.Measure(natural);
        var singleRowFits = compactTabs && brand.DesiredSize.Width + tabs.DesiredSize.Width
            + freshness.DesiredSize.Width + 24 <= renderedPanelWidth - 36;
        if (singleRowFits)
        {
            var single = new Grid();
            single.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            single.ColumnDefinitions.Add(new ColumnDefinition());
            single.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            titleLine.Children.Remove(brand); titleLine.Children.Remove(freshness);
            single.Children.Add(brand); tabs.Margin = new Thickness(12, 0, 12, 0);
            Grid.SetColumn(tabs, 1); single.Children.Add(tabs);
            Grid.SetColumn(freshness, 2); single.Children.Add(freshness); header.Children.Add(single);
        }
        else if (renderedPanelWidth >= (prefs.Language == "en" ? 1450 : 1250))
        {
            // Equal side columns keep both segmented controls centered.
            var wide = new Grid(); wide.ColumnDefinitions.Add(new ColumnDefinition()); wide.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); wide.ColumnDefinitions.Add(new ColumnDefinition());
            titleLine.Children.Remove(brand); titleLine.Children.Remove(freshness);
            wide.Children.Add(brand); Grid.SetColumn(tabs, 1); wide.Children.Add(tabs); Grid.SetColumn(freshness, 2); wide.Children.Add(freshness);
            freshness.HorizontalAlignment = HorizontalAlignment.Right; header.Children.Add(wide);
        }
        else { header.Children.Add(titleLine); tabs.Margin = new Thickness(0, 10, 0, 0); header.Children.Add(tabs); }
        return header;
    }
    Button AddModelButton(Func<Task> action)
    {
        var label = new StackPanel { Orientation = Orientation.Horizontal };
        label.Children.Add(new System.Windows.Shapes.Path {
            Data = Geometry.Parse("M0,5 L10,5 M5,0 L5,10"), Stroke = PanelMuted, StrokeThickness = 1.3,
            Width = 10, Height = 10, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 5, 0) });
        label.Children.Add(Caption(Tr("Add model", "添加模型", "添加模型")));
        var button = QuietButton("", action);
        button.Content = label; button.Foreground = PanelMuted;
        button.Margin = new Thickness(0, 0, 6, 6); button.Padding = new Thickness(7, 3, 7, 3);
        button.Height = 24;
        button.BorderThickness = new Thickness(1); button.BorderBrush = PanelLine;
        button.VerticalAlignment = VerticalAlignment.Center; button.IsEnabled = engine is not null;
        button.ToolTip = Tr("Add a model provider to view its quota", "添加模型供应商，查看其余量");
        System.Windows.Automation.AutomationProperties.SetName(button, Tr("Add model", "添加模型", "添加模型"));
        return button;
    }
    (string Text, bool IsSourceTime) BoardTime(Board board)
    {
        var time = BoardTimestamp.For(board);
        var dataset = time.IsSourceTime && ArenaAttribution.Applies(board);
        var value = time.FormatValue(DateTimeOffset.UtcNow, prefs.Language,
            dataset ? TimeZoneInfo.Utc : TimeZoneInfo.Local, dateOnly: dataset, includesYear: true);
        return (time.Caption(value, prefs.Language), time.IsSourceTime);
    }
    string BoardTimeHelp(Board board)
    {
        var time = BoardTimestamp.For(board);
        var value = time.IsSourceTime && ArenaAttribution.Applies(board)
            ? time.Value?.UtcDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
            : time.Value?.ToLocalTime().ToString("g", CultureInfo.CurrentCulture);
        return time.Caption(value ?? "—", prefs.Language);
    }
    FrameworkElement Segments((string Value, string Title)[] items, string selected, double width, Func<string, Task> change, bool compact = false)
    {
        if (compact)
        {
            var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
            var labelWidth = items.Max(item => new FormattedText(item.Title,
                CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Medium, FontStretches.Normal),
                13, Brushes.Black, dpi).WidthIncludingTrailingWhitespace);
            width = Math.Ceiling(labelWidth + 16) * items.Length;
        }
        var grid = new Grid();
        for (var i = 0; i < items.Length; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition()); var value = items[i].Value;
            var button = QuietButton(items[i].Title, async () => { await change(value); });
            button.Background = value == selected ? PanelSelection : Brushes.Transparent;
            button.BorderBrush = PanelLine; button.BorderThickness = new Thickness(value == selected ? 1 : 0);
            button.FontWeight = value == selected ? FontWeights.Medium : FontWeights.Normal;
            button.Padding = new Thickness(compact ? 3 : 4, 1, compact ? 3 : 4, 1); button.HorizontalAlignment = HorizontalAlignment.Stretch;
            button.VerticalAlignment = VerticalAlignment.Stretch; Grid.SetColumn(button, i); grid.Children.Add(button);
        }
        return new Border { Child = grid, Width = width, Height = 22, Background = PanelSurface, BorderBrush = PanelLine, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(5) };
    }
    Button QuietButton(string text, Action action) => Quiet(Button(text, action));
    Button QuietButton(string text, Func<Task> action) => Quiet(Button(text, action));
    Button Quiet(Button button) { button.Padding = new Thickness(2, 0, 2, 0); button.Margin = new Thickness(0); button.Foreground = PanelMuted; return button; }

    FrameworkElement QuotaPlaceholder()
    {
        var line = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        line.Children.Add(Caption(Tr("Install ", "安装 ", "安裝 ")));
        var link = QuietButton("CC Switch", () => Open("https://github.com/farion1231/cc-switch/releases/latest")); link.Foreground = PanelAccent;
        var linkText = Caption("CC Switch", PanelAccent); linkText.TextDecorations = TextDecorations.Underline; link.Content = linkText;
        ((Button)link).ToolTip = Tr("Download CC Switch", "下载 CC Switch", "下載 CC Switch"); line.Children.Add(link);
        line.Children.Add(Caption(Tr(" to see provider quotas here.", "，即可在这里查看各家提供商的余量。", "，即可在這裡查看各家提供者的餘量。")));
        var guide = new Grid { Width = Math.Max(1, renderedPanelWidth - 36), Height = 28, Margin = new Thickness(0, 0, 0, 2) };
        guide.Children.Add(new System.Windows.Shapes.Rectangle { RadiusX = 6, RadiusY = 6, Stroke = PanelLine, StrokeThickness = 1,
            StrokeDashArray = new DoubleCollection { 3, 3 }, Fill = Tint(panelDark ? "#29292B" : "#F8F8FA") });
        guide.Children.Add(line); return guide;
    }
    FrameworkElement QuotaCard(Quota quota)
    {
        var line = new Grid { Height = 18, VerticalAlignment = VerticalAlignment.Center };
        line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); line.ColumnDefinitions.Add(new ColumnDefinition());
        var text = Caption("", quota.IsDimmed ? PanelMuted : PanelInk); text.Inlines.Clear(); text.ToolTip = quota.Help;
        if (ProviderLogo(quota.Name) is { } key && Logo(key, 16) is { } image)
        {
            if (quota.IsDimmed) { image.Source = Monochrome(image.Source); image.Opacity = 0.55; }
            var mark = new Border { Child = image, Width = 18, Height = 18, VerticalAlignment = VerticalAlignment.Center,
                Background = Brushes.White, CornerRadius = new CornerRadius(3), Margin = new Thickness(0, 0, 5, 0) };
            AddCell(line, mark, 0);
        }
        text.Inlines.Add(new TextRun(quota.Name + "  ") { FontWeight = quota.IsCurrent ? FontWeights.SemiBold : FontWeights.Medium });
        foreach (var run in quota.Runs) text.Inlines.Add(new TextRun(run.Text) { Foreground = quota.IsDimmed ? PanelMuted : Tint(panelDark ? run.Dark : run.Light) });
        if (quota.IsStale) text.Inlines.Add(new TextRun(" · " + Tr("saved", "缓存", "快取")) { Foreground = PanelMuted });
        var fill = quota.IsDimmed ? Tint(panelDark ? "#272728" : "#F5F5F5")
            : quota.AccentLight is { } accent ? Tint(accent, quota.IsCurrent ? 0.12 : 0.06) : PanelSurface;
        AddCell(line, text, 1);
        var card = new Border { Child = line, Height = 24, Padding = new Thickness(7, 2, 7, 2), CornerRadius = new CornerRadius(5), Background = fill,
            Margin = new Thickness(0, 0, 6, 6), BorderThickness = new Thickness(quota.IsCurrent ? 1 : 0), BorderBrush = quota.IsDimmed ? PanelLine : Tint("#238D50") };
        if (quota.CanConnect || quota.Url is not null) { card.Cursor = Cursors.Hand; card.MouseLeftButtonUp += async (_, _) => { if (quota.CanConnect) await Connect(quota); else if (quota.Url is { } url) Open(url); }; }
        return card;
    }

    static ImageSource Monochrome(ImageSource source)
    {
        if (source is not BitmapSource bitmap) return source;
        var converted = new FormatConvertedBitmap(bitmap, PixelFormats.Pbgra32, null, 0);
        var stride = converted.PixelWidth * 4;
        var pixels = new byte[stride * converted.PixelHeight];
        converted.CopyPixels(pixels, stride, 0);
        for (var i = 0; i < pixels.Length; i += 4)
        {
            var gray = (byte)Math.Round(pixels[i] * 0.0722 + pixels[i + 1] * 0.7152 + pixels[i + 2] * 0.2126);
            pixels[i] = pixels[i + 1] = pixels[i + 2] = gray;
        }
        var result = BitmapSource.Create(converted.PixelWidth, converted.PixelHeight, converted.DpiX, converted.DpiY,
            PixelFormats.Pbgra32, null, pixels, stride);
        result.Freeze();
        return result;
    }
    static string? ProviderLogo(string name)
    {
        var value = name.ToLowerInvariant();
        foreach (var item in new[] { ("openai","openai"),("claude","anthropic"),("anthropic","anthropic"),("gemini","google"),("google","google"),("kimi","kimi"),("qwen","qwen"),("千问","qwen"),("deepseek","deepseek"),("glm","zai"),("grok","spacexai"),("xai","spacexai"),("智谱","zai") })
            if (value.Contains(item.Item1)) return item.Item2;
        return null;
    }
    static Image? Logo(string key, double size)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "logos", key + ".png");
        return File.Exists(path) ? new Image { Source = new BitmapImage(new Uri(path)), Width = size, Height = size, Stretch = Stretch.Uniform,
            VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center } : null;
    }

    FrameworkElement BrandLogo(Entry entry)
    {
        if (entry.LogoPNG is { Length: <= 22000 } encoded)
        {
            try
            {
                var bytes = Convert.FromBase64String(encoded);
                if (bytes.Length >= 33 && bytes.Length <= 16384
                    && bytes.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 })
                    && bytes.AsSpan(16, 8).SequenceEqual(new byte[] { 0, 0, 0, 64, 0, 0, 0, 64 }))
                {
                    using var stream = new MemoryStream(bytes, false);
                    var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad;
                    bitmap.DecodePixelWidth = 64; bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze();
                    return new Image { Source = bitmap, Width = 20, Height = 20, Stretch = Stretch.Uniform,
                        HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
                }
            }
            catch (Exception error) when (error is FormatException or IOException or NotSupportedException or ArgumentException) { }
        }
        if (entry.Logo is { } key && Logo(key, 20) is { } bundled) return bundled;
        var initial = entry.Initials;
        if (string.IsNullOrWhiteSpace(initial))
            initial = (string.IsNullOrWhiteSpace(entry.Organization) ? entry.Name : entry.Organization)
                .EnumerateRunes().FirstOrDefault(System.Text.Rune.IsLetterOrDigit).ToString().ToUpperInvariant();
        return new Border { Background = Brushes.White, Child = Center(Caption(
            string.IsNullOrWhiteSpace(initial) || initial == "\0" ? "?" : initial, Brushes.DimGray, 10)) };
    }

    FrameworkElement PairedBoards()
    {
        var pair = VisibleBoards();
        var table = new Grid();
        table.RowDefinitions.Add(new RowDefinition { Height = new GridLength(34) });
        table.RowDefinitions.Add(new RowDefinition());
        var headings = TableGrid(pair.Length); headings.Background = Tint(panelDark ? "#29292B" : "#FCFCFC"); headings.Height = 34;
        AddCell(headings, Caption(Tr("Rank", "排名", "排名"), PanelInk) is { } rank ? Center(rank) : throw new InvalidOperationException(), 0);
        for (var i = 0; i < pair.Length; i++)
        {
            var board = pair[i]; var column = 1 + i * 4;
            AddCell(headings, Center(Caption(board.Kind is "vercelUsage" or "cloudbaseUsage" ? Tr("Share", "占比", "佔比") : board.Kind == "openRouterUsage" ? Tr("Tokens", "用量", "用量") : Tr("Score", "分数", "分數"), PanelInk)), column + 3);
            var summary = new TextBlock { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, FontSize = 9,
                FontFamily = new FontFamily("Segoe UI"),
                Margin = new Thickness(5, 0, 4, 0), ToolTip = board.Error ?? BoardTitle(board) + "\n"
                    + (board.Kind.StartsWith("arena") || board.Kind == "codeArenaWebDev"
                        ? Tr("Formerly LMSYS Chatbot Arena / LMArena", "原 LMSYS Chatbot Arena / LMArena", "原 LMSYS Chatbot Arena / LMArena") + "\n" : "")
                    + SourceLens(board) + "\n" + (board.Kind == "openRouterUsage"
                        ? Tr("Latest complete UTC day · input + output tokens · 1B = 1 billion tokens. Top 50 public models; excludes private and zero-data-retention traffic. Provider tokenizers differ. Company totals cover listed models only.", "最近完整 UTC 日输入与输出 token 用量；1B = 十亿 token。展示公开流量前 50 名，排除私有及零数据留存流量；各供应商分词方式不同。公司用量仅汇总榜内模型。", "最近完整 UTC 日輸入與輸出 token 用量；1B = 十億 token。展示公開流量前 50 名，排除私有及零資料留存流量；各供應商分詞方式不同。公司用量僅彙總榜內模型。")
                        : Tr("Scores are not directly comparable across lists", "各榜分数不直接互比", "各榜分數不直接互比"))
                    + (board.Kind == "cloudbaseUsage" ? "\n" + Tr("Sampled-period text token shares, including cache hits; model families only. Full dates and absolute volumes unavailable.", "抽样统计日文本 token 累计占比，含缓存命中；按模型系列汇总，未公开完整日期或绝对用量。", "抽樣統計日文字 token 累計佔比，含快取命中；按模型系列彙總，未公開完整日期或絕對用量。") : "")
                    + (board.Kind == "vercelUsage" ? "\n" + Tr("Daily data uses UTC 00:00 to 00:00 the next day (08:00 to 08:00 the next day in Beijing). Text token shares include cached and reasoning tokens. Company shares sum listed models only; no absolute volumes are published.", "按 UTC 当天 00:00 至次日 00:00 统计，对应北京时间当天 08:00 至次日 08:00。文本 token 用量占比包含缓存及推理 token；公司只汇总榜内模型，不提供绝对用量。", "按 UTC 當天 00:00 至次日 00:00 統計，對應北京時間當天 08:00 至次日 08:00。文字 token 用量佔比包含快取及推理 token；公司只彙總榜內模型，不提供絕對用量。") : "")
                    + (BoardTimestamp.StatisticalDay(board, prefs.Language) is { } statisticalDay ? "\n" + statisticalDay : "")
                    + (board.Kind is "vercelUsage" or "cloudbaseUsage" ? "\n" + Tr("Refresh time records when we retrieved this snapshot; it does not indicate a new source update.", "刷新时间仅表示我们取得这份数据的时间，不代表来源数据刚刚更新。", "刷新時間僅表示我們取得這份資料的時間，不代表來源資料剛剛更新。") : "")
                    + (ArenaAttribution.Applies(board) ? "\n" + ArenaAttribution.FullText(prefs.Language) : "") };
            CenterTextInk(summary);
            summary.FontSize = 11;
            summary.FontWeight = FontWeights.SemiBold;
            void UpdateHeading()
            {
                double Measure(string text, double size, FontWeight weight) => new FormattedText(text,
                    CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                    new Typeface(summary.FontFamily, FontStyles.Normal, weight, FontStretches.Normal),
                    size, PanelInk, VisualTreeHelper.GetDpi(this).PixelsPerDip).WidthIncludingTrailingWhitespace;
                var title = BoardTitle(board);
                var available = summary.ActualWidth;
                var lens = SourceLens(board) + " · ";
                var lensWidth = Measure(lens, 10, FontWeights.Normal);
                if (available > 0 && lensWidth + Measure(title, 11, FontWeights.SemiBold) > available)
                    title = title.Replace("Artificial Analysis", "AA", StringComparison.Ordinal);
                var license = board.Kind is "epochECI" or "openRouterUsage" or "vercelUsage" || ArenaAttribution.Applies(board) ? " · CC BY 4.0" : "";
                var titleWidth = Measure(title, 11, FontWeights.SemiBold);
                var showsLens = lensWidth + titleWidth <= available;
                var licenseWidth = license.Length == 0 ? 0 : Measure(license, 11, FontWeights.SemiBold);
                var showsLicense = license.Length > 0 && (showsLens ? lensWidth : 0) + titleWidth + licenseWidth <= available;
                summary.Inlines.Clear();
                if (showsLens)
                    summary.Inlines.Add(new TextRun(lens) { Foreground = BoardTint(board.Kind), FontSize = 10, FontWeight = FontWeights.Normal });
                summary.Inlines.Add(new TextRun(title) { Foreground = BoardTint(board.Kind) });
                if (showsLicense)
                    summary.Inlines.Add(new TextRun(license) { Foreground = BoardTint(board.Kind) });
            }
            summary.SizeChanged += (_, _) => UpdateHeading();
            UpdateHeading();
            if (!string.IsNullOrEmpty(board.Url)) { summary.Cursor = Cursors.Hand; summary.MouseLeftButtonUp += (_, _) => Open(board.Url); }
            var heading = new Grid();
            heading.ColumnDefinitions.Add(new ColumnDefinition());
            heading.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var selectedTime = BoardTime(board);
            var time = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 5, 0) };
            var sourceTime = Caption(selectedTime.Text, selectedTime.IsSourceTime ? BoardTint(board.Kind) : PanelMuted, 8.5, numeric: true);
            sourceTime.FontWeight = selectedTime.IsSourceTime ? FontWeights.SemiBold : FontWeights.Normal;
            if (!timestampPolishClocks.TryGetValue(board.Kind, out var polishClock))
                timestampPolishClocks[board.Kind] = polishClock = new TimestampPolishClock();
            polishClock.Update(!VisibleBoardsLoading && board.Kind != "cloudbaseUsage" && selectedTime.Text != "—");
            var polishedTime = new TimestampPolish(sourceTime, polishClock);
            timestampPolishViews.Add(polishedTime);
            time.Children.Add(polishedTime);
            time.ToolTip = BoardTimeHelp(board);
            heading.Children.Add(summary);
            Grid.SetColumn(time, 1); heading.Children.Add(time);
            AddCell(headings, heading, column);
            AddCell(headings, OpennessPicker(board), column + 2);
            AddCell(headings, CountryPicker(board), column + 1);
        }
        var outline = new Border { Child = headings, BorderBrush = PanelLine, BorderThickness = new Thickness(1, 1, 1, 1) }; Grid.SetRow(outline, 0); table.Children.Add(outline);
        var unsearched = pair.Select(board => board.Entries.Where(entry => prefs.Countries.GetValueOrDefault(board.Kind, "") is { } filter && (filter.Length == 0 || (filter == "unknown" ? entry.Country is null : entry.Country == filter))).ToArray()).ToArray();
        var matches = LeaderboardSearch.Compile(leaderboardQuery);
        var entries = unsearched.Select(board => board.Where(entry => matches(entry.Name)).ToArray()).ToArray();
        var count = entries.Length == 0 ? 20 : Math.Max(string.IsNullOrWhiteSpace(leaderboardQuery) ? 1 : 4, entries.Max(values => values.Length));
        var rows = new VirtualLeaderboardList(count + 1, index =>
        {
            if (index == count) return DistributionPanels(pair);
            var row = TableGrid(pair.Length); row.Height = 32; row.Background = index % 2 == 0 ? PanelBackground : Tint(panelDark ? "#29292B" : "#F3F3F5");
            AddCell(row, Rank(index + 1), 0);
            for (var side = 0; side < entries.Length; side++)
            {
                var column = 1 + side * 4;
                if (index >= entries[side].Length) continue;
                var entry = entries[side][index]; AddCell(row, ModelCell(entry, unsearched[side][0].Score, BoardTint(pair[side].Kind), pair[side].Kind is not ("vercelUsage" or "cloudbaseUsage")), column);
                var score = new Grid();
                score.Children.Add(Center(Caption((pair[side].Kind is "vercelUsage" or "cloudbaseUsage" ? (entry.Score > 0 && entry.Score < 0.01 ? "<0.01%" : entry.Score.ToString("0.00", CultureInfo.InvariantCulture) + "%") : pair[side].Kind == "openRouterUsage" && entry.Score > 0 && entry.Score < 0.01 ? "<0.01B" : entry.Score.ToString(pair[side].Kind == "openRouterUsage" ? "0.00\"B\"" : pair[side].Kind == "epochECI" ? "0.00" : "0.0", CultureInfo.InvariantCulture)), PanelMuted, 13, numeric: true)));
                AddCell(row, score, column + 3);
                AddCell(row, OpennessBadge(entry.Openness), column + 2);
                AddCell(row, Flag(entry.Country), column + 1);
            }
            return row;
        });
        var viewport = new Grid(); viewport.Children.Add(rows);
        var backToTop = new Button { Content = "↑", Width = 32, Height = 32,
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 24, 12), Visibility = Visibility.Collapsed,
            ToolTip = Tr("Back to top", "返回顶部", "返回頂部"), Background = PanelSurface, Foreground = PanelInk };
        System.Windows.Automation.AutomationProperties.SetName(backToTop, Tr("Back to top", "返回顶部", "返回頂部"));
        System.Windows.Automation.AutomationProperties.SetAutomationId(backToTop, "leaderboard-back-to-top");
        backToTop.Click += (_, _) => rows.ScrollIntoView(0);
        rows.AddHandler(ScrollViewer.ScrollChangedEvent, new ScrollChangedEventHandler((_, change) =>
            backToTop.Visibility = change.VerticalOffset >= 32 ? Visibility.Visible : Visibility.Collapsed));
        viewport.Children.Add(backToTop);
        if (prefs.Category == "usage" && pair.All(board => board.Entries.Length == 0))
        {
            var loading = VisibleBoardsLoading;
            var errors = pair.Where(board => !string.IsNullOrWhiteSpace(board.Error)).Select(board => board.Title + " · " + board.Error).ToList();
            if (boardRefreshFailures.TryGetValue(BoardRefreshKey, out var failure)) errors.Add(failure);
            var pending = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 520 };
            var kind = loading ? "loading" : errors.Count > 0 ? "error" : "empty";
            System.Windows.Automation.AutomationProperties.SetAutomationId(pending, "usage-" + kind);
            if (loading) pending.Children.Add(new ProgressBar { IsIndeterminate = true, Width = 160, Height = 4, Margin = new Thickness(0, 0, 0, 12) });
            var label = Caption(loading ? Tr("Loading usage data…", "正在加载用量数据…", "正在載入用量資料…")
                : errors.Count > 0 ? Tr("Could not load usage data", "用量数据加载失败", "用量資料載入失敗")
                : Tr("No usage data yet", "暂无用量数据", "暫無用量資料"), PanelMuted, 13);
            label.TextWrapping = TextWrapping.Wrap; label.TextAlignment = TextAlignment.Center;
            pending.Children.Add(label);
            if (!loading) foreach (var error in errors) {
                var detail = Caption(error, PanelMuted, 11); detail.TextWrapping = TextWrapping.Wrap; detail.TextAlignment = TextAlignment.Center; detail.Margin = new Thickness(0, 8, 0, 0);
                pending.Children.Add(detail);
            }
            viewport.Children.Add(pending);
        }
        if (!string.IsNullOrWhiteSpace(leaderboardQuery) && entries.All(board => board.Length == 0))
        {
            var empty = Caption(Tr("No matching results", "没有匹配结果", "沒有符合的結果"), PanelMuted, 13);
            empty.HorizontalAlignment = HorizontalAlignment.Center; empty.VerticalAlignment = VerticalAlignment.Top; empty.Margin = new Thickness(0, 40, 0, 0); empty.IsHitTestVisible = false;
            viewport.Children.Add(empty);
        }
        Grid.SetRow(viewport, 1); table.Children.Add(viewport);
        // A resizable desktop window can be narrower than three readable source
        // groups. Keep every selected source reachable with one shared horizontal
        // viewport, so the native header and body move together.
        if (pair.Length == 3 && renderedPanelWidth < 748)
        {
            table.Width = 748;
            return new ScrollViewer { Content = table, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, VerticalContentAlignment = VerticalAlignment.Stretch };
        }
        return table;
    }

    Brush OpennessTint(string openness) => Tint(openness == "open"
        ? (panelDark ? "#77D9A1" : "#188966")
        : (panelDark ? "#B8BEC7" : "#6B7280"));

    FrameworkElement OpennessBadge(string? openness)
    {
        if (openness is not ("open" or "closed")) return Center(Caption("—", PanelMuted, 13));
        var open = openness == "open";
        var title = open ? Tr("Open", "开源", "開源") : Tr("Closed", "闭源", "閉源");
        var ink = OpennessTint(openness);
        // Same Lucide paths and fixed 24-point viewBox as the mini-program.
        // Keeping the viewport fixed aligns both lock bodies. See Licenses/Lucide.txt.
        var drawing = new DrawingGroup();
        drawing.Children.Add(new GeometryDrawing(Brushes.Transparent, null, new RectangleGeometry(new Rect(0, 0, 24, 24))));
        var pen = new Pen(ink, 2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        drawing.Children.Add(new GeometryDrawing(null, pen, new RectangleGeometry(new Rect(3, 10, 18, 12), 2, 2)));
        drawing.Children.Add(new GeometryDrawing(null, pen, new EllipseGeometry(new Point(12, 16), 1, 1)));
        drawing.Children.Add(new GeometryDrawing(null, pen, Geometry.Parse(open
            ? "M 7,10 V 7 A 5,5 0 0 1 16.33,4.5"
            : "M 7,10 V 7 A 5,5 0 0 1 17,7 V 10")));
        var content = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var icon = new Image { Source = new DrawingImage(drawing), Width = 14, Height = 14,
            Stretch = Stretch.Uniform };
        content.Children.Add(icon);
        var badge = new Border { Child = content, ToolTip = title,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        System.Windows.Automation.AutomationProperties.SetName(badge, title);
        return badge;
    }
    double CountryColumnWidth => prefs.Language == "en" ? 48 : 40;
    double SourceColumnWidth => prefs.Language == "en" ? 44 : 36;

    Board[] VisibleBoards()
    {
        var saved = state?.Boards ?? [];
        return prefs.VisibleBoardKinds().Select(kind => saved.FirstOrDefault(board => board.Kind == kind)
            ?? new Board(kind, kind == "epochECI" ? "Epoch AI" : kind.StartsWith("artificialAnalysis") ? "Artificial Analysis" : "Arena", "", null, null, [])).ToArray();
    }
    Brush BoardTint(string kind) => Tint(SourceTabTheme.For(kind, panelDark).Accent);

    Grid TableGrid(int boardCount)
    {
        var grid = new Grid(); var compact = renderedPanelWidth < 850;
        System.Windows.Automation.AutomationProperties.SetAutomationId(grid, "leaderboard-columns");
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        for (var i = 0; i < boardCount; i++)
            foreach (var width in new[] { new GridLength(1, GridUnitType.Star), new GridLength(CountryColumnWidth), new GridLength(SourceColumnWidth), new GridLength(compact ? 56 : 78) })
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        return grid;
    }
    static TextBlock Center(TextBlock text) { text.TextAlignment = TextAlignment.Center; text.HorizontalAlignment = HorizontalAlignment.Stretch; return text; }
    FrameworkElement Rank(int rank)
    {
        if (rank > 3) return Center(Caption(rank.ToString(CultureInfo.InvariantCulture), PanelInk, 13, numeric: true));
        // The medal stays legible on Windows installations without color emoji.
        var grid = new Grid { Width = 18, Height = 23, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        var ribbon = new System.Windows.Shapes.Path { Data = Geometry.Parse("M 4,0 L 8,0 L 11,8 L 7,8 Z M 10,0 L 14,0 L 11,8 L 7,8 Z"), Fill = Tint(rank == 1 ? "#FFB900" : rank == 2 ? "#86A0A7" : "#E0783D") };
        grid.Children.Add(ribbon);
        grid.Children.Add(new Border { Width = 13, Height = 13, CornerRadius = new CornerRadius(7), Background = Tint(rank == 1 ? "#F8BF24" : rank == 2 ? "#B8BEC4" : "#C78C5C"), VerticalAlignment = VerticalAlignment.Bottom,
            Child = Center(Caption(rank.ToString(CultureInfo.InvariantCulture), Brushes.White, 9, numeric: true)) }); return grid;
    }
    Brush BrandFill(string hex, string modelName)
    {
        var color = (Color)ColorConverter.ConvertFromString(hex);
        var channels = new[] { (int)color.R, (int)color.G, (int)color.B };
        if (panelDark && channels.Max() - channels.Min() <= 24)
        {
            var neutral = 255 - (int)(channels.Average() * 0.7);
            channels = [neutral, neutral, neutral];
        }
        // Match the Mac catalog's stable per-model shade, including UTF-8 names.
        ulong hash = 14695981039346656037;
        foreach (var rune in modelName.ToLowerInvariant().EnumerateRunes().Where(System.Text.Rune.IsLetterOrDigit))
            foreach (var value in System.Text.Encoding.UTF8.GetBytes(rune.ToString())) hash = unchecked((hash ^ value) * 1099511628211);
        var shade = new[] { -0.24, -0.12, 0, 0.12, 0.24 }[(int)(hash % 5)];
        channels = channels.Select(channel => (int)Math.Round(shade < 0 ? channel * (1 + shade) : channel + (255 - channel) * shade, MidpointRounding.AwayFromZero)).ToArray();
        return new SolidColorBrush(Color.FromRgb((byte)channels[0], (byte)channels[1], (byte)channels[2])) { Opacity = 0.34 };
    }
    FrameworkElement ModelCell(Entry entry, double leaderScore, Brush shareColor, bool showRelativeShare)
    {
        var row = new Grid { HorizontalAlignment = HorizontalAlignment.Left };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) }); row.ColumnDefinitions.Add(new ColumnDefinition());
        AddCell(row, new Border { Child = BrandLogo(entry), Width = 20, Height = 20, VerticalAlignment = VerticalAlignment.Center,
            Clip = new RectangleGeometry(new Rect(0, 0, 20, 20), 5, 5), Margin = new Thickness(0, 0, 4, 0) }, 0);
        var name = Caption(entry.Name, PanelInk, 13); name.Margin = new Thickness(6, 0, 3, 0); AddCell(row, name, 1);
        if (entry.CodingURL is not null || entry.ApiURL is not null)
        {
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var links = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            if (entry.CodingURL is { } coding) links.Children.Add(LinkButton("↗", coding, Tr("Coding plan", "编程套餐")));
            if (entry.ApiURL is { } api) links.Children.Add(LinkButton("API", api, Tr("API pricing", "API 价格")));
            AddCell(row, links, 2);
        }
        var hex = entry.BrandColor;
        if (hex is null || hex.Length != 7 || hex[0] != '#' || !hex.Skip(1).All(Uri.IsHexDigit))
            hex = entry.Logo is { } logoKey && BrandColors.TryGetValue(logoKey, out var known) ? known : "#607D8B";
        var color = BrandFill(hex, entry.Name);
        var ratio = ScoreShare.FillRatio(entry.Score, leaderScore);
        var background = new Grid { IsHitTestVisible = false };
        background.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(ratio, GridUnitType.Star) });
        background.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1 - ratio, GridUnitType.Star) });
        background.Children.Add(new Border { Background = color, CornerRadius = new CornerRadius(5) });
        var content = new Grid { ClipToBounds = true };
        // Every row reserves the same gutter, preserving the shared bar scale.
        var measure = Caption("99%", shareColor, 8, numeric: true);
        measure.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var badgeWidth = Math.Ceiling(measure.DesiredSize.Width);
        const double badgeGap = 4;
        background.HorizontalAlignment = HorizontalAlignment.Left;
        content.Children.Add(background);
        var nameContent = new Border { Child = row, Padding = new Thickness(4, 0, 3, 0),
            HorizontalAlignment = HorizontalAlignment.Left, ClipToBounds = true };
        content.Children.Add(nameContent);
        var share = showRelativeShare ? ScoreShare.Format(entry.Score, leaderScore) : "";
        var overlay = new Canvas { IsHitTestVisible = false, ClipToBounds = true };
        var label = Caption(share, shareColor, 8, numeric: true);
        label.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var badgeHeight = label.DesiredSize.Height;
        overlay.Children.Add(label);
        content.Children.Add(overlay);
        void PositionBadge()
        {
            var trackWidth = Math.Max(0, content.ActualWidth - badgeWidth - badgeGap);
            var filledWidth = trackWidth * ratio;
            var showsShare = share.Length > 0 && filledWidth >= 38;
            background.Width = trackWidth;
            // Names use the whole model column, independently of the score fill.
            nameContent.Width = trackWidth;
            name.Margin = new Thickness(nameContent.Width < 90 ? 0 : 6, 0, 3, 0);
            label.Visibility = showsShare ? Visibility.Visible : Visibility.Collapsed;
            Canvas.SetLeft(label, trackWidth + badgeGap);
            Canvas.SetTop(label, (content.ActualHeight - badgeHeight) / 2);
        }
        content.SizeChanged += (_, _) => PositionBadge();
        var cell = new Border { Child = content, Background = Brushes.Transparent, CornerRadius = new CornerRadius(5), Margin = new Thickness(12, 4, 8, 4), ToolTip = entry.Help ?? entry.Name, Cursor = Cursors.Hand };
        cell.MouseLeftButtonUp += (_, _) => {
            if (prefs.Grouping != "company") { ShowModelDetails(entry); return; }
            try { Clipboard.SetText(entry.Name); status.Text = Tr("Copied", "已复制", "已複製"); } catch (System.Runtime.InteropServices.COMException) { }
        };
        return cell;
    }
    string BoardTitle(Board board) => board.Kind switch
    {
        "cloudbaseUsage" => "Tencent Cloud",
        "vercelUsage" => "Vercel AI Gateway",
        "openRouterUsage" => "OpenRouter",
        "artificialAnalysis" => "Artificial Analysis", "arenaText" => "Text Arena", "epochECI" => "Epoch ECI",
        "artificialAnalysisCodingAgent" => Tr("Artificial Analysis Coding", "Artificial Analysis 编程", "Artificial Analysis 編程"),
        "codeArenaWebDev" => "Code Arena",
        "artificialAnalysisTextToImage" => Tr("Artificial Analysis Text to Image", "Artificial Analysis 文生图", "Artificial Analysis 文生圖"),
        "arenaTextToImage" => Tr("Text to Image Arena", "Arena 文生图", "Arena 文生圖"),
        "artificialAnalysisTextToVideo" => Tr("Artificial Analysis Text to Video", "Artificial Analysis 文生视频", "Artificial Analysis 文生影片"),
        "arenaTextToVideo" => Tr("Text to Video Arena", "Arena 文生视频", "Arena 文生影片"),
        _ => board.Title,
    };
    string SourceLens(Board board) => board.Kind switch
    {
        "artificialAnalysis" => Tr("Task benchmarks", "任务测评", "任務測評"),
        "cloudbaseUsage" or "vercelUsage" => Tr("Token share", "用量占比", "用量佔比"),
        "openRouterUsage" => Tr("Usage ranking", "用量排行", "用量排行"),
        "epochECI" => Tr("Calibrated tests", "难度校准", "難度校準"),
        "arenaText" => Tr("User votes", "用户盲测", "使用者盲測"),
        "artificialAnalysisCodingAgent" => Tr("Task completion", "任务完成率", "任務完成率"),
        "codeArenaWebDev" => Tr("WebDev votes", "网页开发盲选", "網頁開發盲選"),
        "artificialAnalysisTextToImage" => Tr("Curated prompts", "场景化盲测", "場景化盲測"),
        "artificialAnalysisTextToVideo" => Tr("Matched settings", "统一设置", "統一設定"),
        "arenaTextToImage" or "arenaTextToVideo" => Tr("User prompts", "用户出题", "使用者出題"), _ => "",
    };
    FrameworkElement FilterHeaderLabel(string title, bool active)
    {
        var ink = PanelInk;
        if (active)
        {
            var text = Caption(title, ink, 9.5); text.FontWeight = FontWeights.SemiBold;
            var content = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            content.Children.Add(text);
            content.Children.Add(new System.Windows.Shapes.Path {
                Data = Geometry.Parse("M1,1 L7,1 L4.8,3.8 L4.8,6 L3.2,7 L3.2,3.8 Z"),
                Stroke = ink, StrokeThickness = 0.9, StrokeLineJoin = PenLineJoin.Round,
                Width = 8, Height = 8, Margin = new Thickness(2, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
            return new Border { Child = content, Padding = new Thickness(2, 3, 2, 3),
                BorderThickness = new Thickness(0.5) };
        }
        // Only the caption contributes width; the caret sits beyond its right edge.
        var label = new Grid { VerticalAlignment = VerticalAlignment.Center };
        label.Children.Add(Caption(title, ink, 9.5));
        var overlay = new Canvas { Width = 0, Height = 3, HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false };
        var caret = PanelIcon("chevron", ink, 5, 3);
        Canvas.SetLeft(caret, 2); overlay.Children.Add(caret); label.Children.Add(overlay);
        return label;
    }
    FrameworkElement OpennessPicker(Board board)
    {
        var selected = prefs.Sources.GetValueOrDefault(board.Kind, "all");
        var button = QuietButton("", () => { }); button.Foreground = PanelInk; button.Padding = new Thickness(1, 0, 1, 0);
        button.Content = FilterHeaderLabel(Tr("Source", "源码", "源碼"), selected != "all");
        var menu = new ContextMenu();
        foreach (var (value, title) in new[] { ("all", Tr("All sources", "全部源码", "全部源碼")),
            ("open", Tr("Open", "开源", "開源")), ("closed", Tr("Closed", "闭源", "閉源")), ("unknown", Tr("Unknown", "未知")) })
        {
            var choice = new MenuItem { Header = title, IsCheckable = true, IsChecked = selected == value };
            choice.Click += async (_, _) => { prefs.Sources[board.Kind] = value; SaveFrame(); await Refresh("state"); Render(); };
            menu.Items.Add(choice);
        }
        menu.Opened += (_, _) => panelMenuOpen = true;
        menu.Closed += (_, _) => panelMenuOpen = false;
        button.Click += (_, _) => { panelMenuOpen = true; menu.PlacementTarget = button; menu.Placement = PlacementMode.Bottom; menu.IsOpen = true; };
        button.ToolTip = Tr("Filter this leaderboard by source", "按源码筛选此榜单", "依源碼篩選此榜單");
        return button;
    }
    FrameworkElement CountryPicker(Board board)
    {
        var active = !string.IsNullOrEmpty(prefs.Countries.GetValueOrDefault(board.Kind, ""));
        var button = QuietButton("", () => { }); button.Foreground = PanelInk; button.Padding = new Thickness(1, 0, 1, 0);
        button.Content = FilterHeaderLabel(Tr("Country", "国家", "國家"), active);
        var menu = new ContextMenu();
        var options = board.CountryOptions ?? new[] {
            new CountryOption("china", Tr("China", "中国", "中國")), new CountryOption("unitedStates", Tr("United States", "美国", "美國")),
            new CountryOption("canada", Tr("Canada", "加拿大")), new CountryOption("france", Tr("France", "法国", "法國")),
            new CountryOption("germany", Tr("Germany", "德国", "德國")), new CountryOption("singapore", Tr("Singapore", "新加坡")) };
        foreach (var item in new[] { new CountryOption("", Tr("All countries", "所有国家", "所有國家")) }.Concat(options))
        {
            var value = item.Value; var choice = new MenuItem { Header = item.Label, IsCheckable = true, IsChecked = prefs.Countries.GetValueOrDefault(board.Kind, "") == value };
            choice.Click += async (_, _) => { prefs.Countries[board.Kind] = value; SaveFrame(); await Refresh("state"); Render(); }; menu.Items.Add(choice);
        }
        menu.Opened += (_, _) => panelMenuOpen = true;
        menu.Closed += (_, _) => panelMenuOpen = false;
        button.Click += (_, _) => { panelMenuOpen = true; menu.PlacementTarget = button; menu.Placement = PlacementMode.Bottom; menu.IsOpen = true; };
        button.ToolTip = Tr("Filter this source by country", "按国家筛选此榜单", "依國家篩選此榜單"); return button;
    }
    FrameworkElement Flag(string? country)
    {
        if (string.IsNullOrWhiteSpace(country))
        {
            var title = Tr("Why no country?", "为什么没有国家归属？", "為什麼沒有國家歸屬？");
            var help = QuietButton("?", () => MessageBox.Show(this,
                Tr("Country reflects the model developer’s headquarters. Some models are community projects or collaborations, or lack enough reliable information to identify one developer and headquarters. We leave them unassigned rather than guess from the model name, language, base model or hosting provider.",
                    "国家归属依据模型开发者的总部所在地。部分模型属于社区项目或多方合作，也可能缺少足够可靠的信息来确认开发者及其总部，因此暂不归属到某个国家。我们不会根据模型名称、语言、基座模型或托管平台猜测归属。",
                    "國家歸屬依據模型開發者的總部所在地。部分模型屬於社群專案或多方合作，也可能缺少足夠可靠的資訊來確認開發者及其總部，因此暫不歸屬到某個國家。我們不會根據模型名稱、語言、基礎模型或託管平台猜測歸屬。"), title, MessageBoxButton.OK, MessageBoxImage.Information));
            help.Content = Caption("?", PanelMuted, 13);
            help.Padding = new Thickness(0); help.MinWidth = 24; help.MinHeight = 24;
            help.ToolTip = title;
            System.Windows.Automation.AutomationProperties.SetName(help, title);
            System.Windows.Automation.AutomationProperties.SetAutomationId(help, "unknown-country-help");
            help.HorizontalAlignment = HorizontalAlignment.Center;
            help.VerticalAlignment = VerticalAlignment.Center;
            return help;
        }
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
        var dock = new DockPanel { LastChildFill = true, Height = 48, Background = PanelBackground };
        var border = new Border { BorderBrush = PanelLine, BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(18, 10, 18, 10) };
        var row = new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        Button FooterButton(string text, Action action) { var button = QuietButton(text, action); button.FontSize = 10; button.Content = Caption(text, size: 10); return button; }
        var repository = FooterButton("", () => Open("https://github.com/" + config.Repository));
        if (Logo("github", 13) is { } github) repository.Content = new System.Windows.Shapes.Rectangle { Width = 13, Height = 13, Fill = PanelMuted, OpacityMask = new ImageBrush(github.Source) };
        else repository.Content = "GitHub";
        left.Children.Add(repository);
        left.Children.Add(Caption(" Cloyd Lau · ", PanelMuted, 10)); left.Children.Add(FooterButton("MIT License", () => ShowLicenses(false)));
        left.Children.Add(Caption(" · ", PanelMuted, 10)); left.Children.Add(FooterButton(Tr("Open-source notices", "开源声明", "開源聲明"), () => ShowLicenses(true))); row.Children.Add(left);
        var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        right.Children.Add(DataSourcesMenu()); right.Children.Add(Caption(" · ", size: 10));
        right.Children.Add(BoardVisibilityMenu()); right.Children.Add(Caption(" · ", size: 10));
        right.Children.Add(IconButton("camera", Tr("Copy", "截图", "截圖"), Capture)); right.Children.Add(Caption(" · ", size: 10));
        right.Children.Add(Select([("clickToClose",Tr("Keep open","保持打开","保持打開")),("alwaysOnTop",Tr("Always on top","保持置顶","保持置頂")),("closeOnBlur",Tr("Close on blur","失焦关闭","失焦關閉")),("window",Tr("Window","独立窗口","獨立視窗"))], prefs.PanelMode,
            value => { SaveFrame(); prefs.PanelMode = value; ApplyMode(); SaveFrame(); Reveal(); return Task.CompletedTask; }));
        right.Children.Add(Caption(" · ")); right.Children.Add(Segments([("en","EN"),("zh","简中"),("zh-Hant","繁中")], prefs.Language, renderedPanelWidth < 850 ? 120 : 150,
            async value => { prefs.Language = value; SaveFrame(); Render(); await Refresh("state"); }));
        right.Children.Add(Caption(" · ", size: 10)); right.Children.Add(IconButton("power", Tr("Quit", "退出", "退出"), () => { Stop(); Application.Current.Shutdown(); }));
        Grid.SetColumn(right, 2); row.Children.Add(right);
        status.Margin = new Thickness(4, 0, 4, 0); status.FontSize = 10; status.FontFamily = new FontFamily("Segoe UI"); Grid.SetColumn(status, 1); row.Children.Add(status);
        border.Child = row; dock.Children.Add(border); return dock;
    }
    Button DataSourcesMenu()
    {
        var button = QuietButton("", () => { });
        var label = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        label.Children.Add(Caption(Tr("Data sources", "数据来源", "資料來源"), size: 10));
        label.Children.Add(PanelIcon("chevron", PanelMuted, width: 6, height: 4, margin: new Thickness(4, 0, 0, 0)));
        button.Content = label;
        button.ToolTip = Tr("Leaderboard data sources", "榜单数据来源", "榜單資料來源");
        System.Windows.Automation.AutomationProperties.SetAutomationId(button, "data-sources-menu");
        var menu = new ContextMenu();
        foreach (var (kind, title, url) in new[] {
            ("artificialAnalysis", "Artificial Analysis", "https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index"),
            ("arenaText", "Arena", "https://arena.ai/leaderboard/text"),
            ("epochECI", "Epoch AI", "https://epoch.ai/eci"),
            ("openRouterUsage", "OpenRouter", "https://openrouter.ai/rankings"),
            ("vercelUsage", "Vercel AI Gateway", "https://vercel.com/ai-gateway/leaderboards/models"),
            ("cloudbaseUsage", "Tencent Cloud", "https://docs.cloudbase.net/ai/announcement/model-token-volume")
        }) {
            if (kind == "openRouterUsage") menu.Items.Add(new Separator());
            var link = new MenuItem { Header = title + " ↗" };
            System.Windows.Automation.AutomationProperties.SetAutomationId(link, "data-source-" + kind);
            link.Click += (_, _) => Open(url);
            menu.Items.Add(link);
        }
        button.ContextMenu = menu;
        menu.Opened += (_, _) => panelMenuOpen = true;
        menu.Closed += (_, _) => panelMenuOpen = false;
        button.Click += (_, _) => { panelMenuOpen = true; menu.PlacementTarget = button; menu.Placement = PlacementMode.Top; menu.IsOpen = true; };
        return button;
    }

    Button BoardVisibilityMenu()
    {
        var button = QuietButton(Tr("Leaderboards", "显示榜单", "顯示榜單"), () => { });
        button.Content = Caption(Tr("Leaderboards", "显示榜单", "顯示榜單"), size: 10);
        button.ToolTip = Tr("Choose leaderboards, then confirm. Keep at least one.", "选择榜单后点击确认，至少保留一个。", "選擇榜單後點擊確認，至少保留一個。");
        System.Windows.Automation.AutomationProperties.SetAutomationId(button, "board-visibility-menu");
        var menu = new ContextMenu();
        void Populate()
        {
            menu.Items.Clear();
            var category = prefs.Category;
            var draft = prefs.VisibleBoardKinds().ToHashSet();
            var checkboxes = new List<(string Kind, MenuItem Item)>();
            void UpdateCheckboxes()
            {
                foreach (var (kind, item) in checkboxes)
                {
                    item.IsChecked = draft.Contains(kind);
                    item.IsEnabled = draft.Count > 1 || !draft.Contains(kind);
                }
            }
            foreach (var kind in prefs.AvailableBoardKinds())
            {
                var board = VisibleBoards().FirstOrDefault(value => value.Kind == kind)
                    ?? state?.Boards.FirstOrDefault(value => value.Kind == kind)
                    ?? new Board(kind, kind == "epochECI" ? "Epoch AI" : kind.StartsWith("artificialAnalysis") ? "Artificial Analysis" : "Arena", "", null, null, []);
                var item = new MenuItem { Header = (kind == "cloudbaseUsage" ? "Tencent Cloud" : kind == "vercelUsage" ? "Vercel AI Gateway" : kind == "openRouterUsage" ? "OpenRouter" : kind == "epochECI" ? "Epoch AI" : kind.StartsWith("artificialAnalysis") ? "Artificial Analysis" : "Arena") + " · " + SourceLens(board), IsCheckable = true,
                    IsChecked = draft.Contains(kind), IsEnabled = draft.Count > 1 || !draft.Contains(kind), StaysOpenOnClick = true };
                System.Windows.Automation.AutomationProperties.SetAutomationId(item, "board-visibility-" + kind);
                item.Click += (_, _) => {
                    if (item.IsChecked) draft.Add(kind);
                    else if (draft.Count > 1) draft.Remove(kind);
                    UpdateCheckboxes();
                };
                checkboxes.Add((kind, item));
                menu.Items.Add(item);
            }
            menu.Items.Add(new Separator());
            menu.Items.Add(new MenuItem { Header = Tr("Keep at least one leaderboard", "至少保留一个榜单", "至少保留一個榜單"), IsEnabled = false });
            var confirm = new MenuItem { Header = Tr("Confirm", "确认", "確認") };
            System.Windows.Automation.AutomationProperties.SetAutomationId(confirm, "board-visibility-confirm");
            confirm.Click += async (_, _) => {
                menu.IsOpen = false;
                if (prefs.Category != category || !prefs.SetVisibleBoards(draft)) return;
                SaveFrame(); Render(); await Refresh("refreshBoardsIfStale");
            };
            menu.Items.Add(confirm);
            var cancel = new MenuItem { Header = Tr("Cancel", "取消", "取消") };
            System.Windows.Automation.AutomationProperties.SetAutomationId(cancel, "board-visibility-cancel");
            cancel.Click += (_, _) => menu.IsOpen = false;
            menu.Items.Add(cancel);
        }
        menu.Opened += (_, _) => panelMenuOpen = true;
        menu.Closed += (_, _) => panelMenuOpen = false;
        button.Click += (_, _) => { Populate(); panelMenuOpen = true; menu.PlacementTarget = button; menu.Placement = PlacementMode.Bottom; menu.IsOpen = true; };
        return button;
    }

    static FrameworkElement PanelIcon(string kind, Brush ink, double width = 12, double height = 12, Thickness? margin = null) => new System.Windows.Shapes.Path
    {
        Data = Geometry.Parse(kind switch {
            "help" => "M6,0.5 A5.5,5.5 0 1 1 5.99,0.5 M4.4,4 A1.6,1.6 0 1 1 6,5.6 L6,7 M6,8.8 L6,9",
            "chevron" => "M0,0 L3,3 L6,0",
            "camera" => "M2,4 L5,4 L6,2 L10,2 L11,4 L14,4 L14,13 L2,13 Z M11,8.5 A3,3 0 1 1 5,8.5 A3,3 0 1 1 11,8.5",
            "copy" => "M5,5 L14,5 L14,15 L5,15 Z M11,5 L11,1 L1,1 L1,11 L5,11",
            "power" => "M8,1 L8,8 M4,3.5 A6,6 0 1 0 12,3.5",
            _ => throw new ArgumentOutOfRangeException(nameof(kind)),
        }),
        Stroke = ink, StrokeThickness = 1.1, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
        StrokeLineJoin = PenLineJoin.Round, Stretch = Stretch.Uniform, Width = width, Height = height,
        VerticalAlignment = VerticalAlignment.Center, Margin = margin ?? new Thickness(0), IsHitTestVisible = false,
    };
    Button IconButton(string icon, string label, Action action)
    {
        var line = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        line.Children.Add(PanelIcon(icon, PanelMuted, margin: new Thickness(0, 0, 4, 0)));
        line.Children.Add(Caption(label, size: 10));
        var button = QuietButton("", action); button.FontSize = 10; button.Content = line; return button;
    }
}
