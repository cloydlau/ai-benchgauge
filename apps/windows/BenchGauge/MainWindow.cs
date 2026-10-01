using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BenchGauge.Shared;
using Forms = System.Windows.Forms;

namespace BenchGauge;
sealed class MainWindow : Window
{
    readonly EngineClient? engine;
    readonly Preferences prefs;
    readonly AppConfig config = AppConfig.Load();
    readonly UpdateClient updater;
    readonly Grid content = new();
    readonly Grid quotaArea = new();
    readonly WrapPanel quotaPanel = new() { Margin = new Thickness(0, 0, 0, 12) };
    readonly TextBlock privatePrompt = new() { Visibility = Visibility.Collapsed, Margin = new Thickness(0, 0, 0, 12), TextWrapping = TextWrapping.Wrap };
    readonly TextBlock status = new() { FontSize = 11, Foreground = Brushes.Gray, Margin = new Thickness(4) };
    readonly DispatcherTimer boardTimer = new() { Interval = TimeSpan.FromMinutes(30) };
    readonly DispatcherTimer quotaClockTimer = new() { Interval = TimeSpan.FromMinutes(1) };
    readonly DispatcherTimer updateTimer = new() { Interval = TimeSpan.FromHours(24) };
    readonly List<ComboBox> dropdowns = [];
    DisplayState? state;
    QwenWebsiteWindow? qwenWindow;
    XAIWebsiteSubscriptionWindow? xaiSubscriptionWindow;
    DockPanel? footer;
    Button? updateButton;
    TextBlock? headerTitle;
    bool rendering, modalOpen, closing, checkingUpdate;
    WindowsUpdate? availableUpdate;
    readonly PreparedUpdate preparedUpdate = new();
    PreparedUpdateDialog? updateDialog;
    public Forms.NotifyIcon? Tray { get; set; }
    public string Tr(string en, string zh, string? traditional = null) => prefs.Language switch { "en" => en, "zh-Hant" => traditional ?? zh, _ => zh };
    public MainWindow(EngineClient? engine, Preferences prefs)
    {
        this.engine = engine; this.prefs = prefs; updater = new UpdateClient(config);
        Title = "AI BenchGauge"; Width = 850; MinWidth = 600;
        MinHeight = Math.Min(600, SystemParameters.WorkArea.Height);
        Height = Math.Min(820, SystemParameters.WorkArea.Height);
        WindowStartupLocation = WindowStartupLocation.Manual;
        FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI"); FontSize = 13;
        UseLayoutRounding = true; SnapsToDevicePixels = true;
        ConfigurePanelStyles();
        Microsoft.Win32.SystemEvents.UserPreferenceChanged += SystemAppearanceChanged;
        Closed += (_, _) => Microsoft.Win32.SystemEvents.UserPreferenceChanged -= SystemAppearanceChanged;
        Content = new Border { Padding = new Thickness(0), Child = content };
        quotaArea.Children.Add(quotaPanel); quotaArea.Children.Add(privatePrompt);
        ApplyMode(); Render();
        SizeChanged += (_, _) => Dispatcher.BeginInvoke(() => { if (!closing && !rendering && Content is FrameworkElement client && Math.Abs(client.ActualWidth - renderedPanelWidth) > 1) Render(); }, DispatcherPriority.Loaded);
        Closing += (_, e) => { if (!closing) { e.Cancel = true; if (!preparedUpdate.IsPresenting) { Hide(); SaveFrame(); } } };
        Deactivated += (_, _) => Dispatcher.BeginInvoke(() =>
        {
            if (!closing && IsVisible && prefs.PanelMode == "closeOnBlur" && !IsActive && !modalOpen && !(panelMenuOpen || dropdowns.Any(box => box.IsDropDownOpen))) Hide();
        }, DispatcherPriority.Background);
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape && !modalOpen) Hide(); };
        boardTimer.Tick += async (_, _) => { await Refresh("refreshBoards"); await Refresh("refreshCurrentQuota"); };
        quotaClockTimer.Tick += async (_, _) =>
        {
            if (IsVisible && !modalOpen && !(panelMenuOpen || dropdowns.Any(box => box.IsDropDownOpen))) await Refresh("state");
        };
        updateTimer.Tick += async (_, _) => await CheckUpdates(false);
        Activated += (_, _) => Dispatcher.BeginInvoke(TryPresentPreparedUpdate, DispatcherPriority.Background);

    }
    public async Task Start()
    {
        boardTimer.Start(); quotaClockTimer.Start(); updateTimer.Start();
        await Refresh("state");
        await Task.WhenAll(Refresh("refreshBoards"), Refresh("refreshQuotas"));
        await CheckUpdates(false);
    }
    public void Stop(bool savePreferences = true) { closing = true; updateDialog?.PrepareForShutdown(); boardTimer.Stop(); quotaClockTimer.Stop(); updateTimer.Stop(); if (savePreferences) SaveFrame(); }
    public void Toggle() { if (preparedUpdate.IsPresenting) { updateDialog?.Activate(); return; } if (IsVisible) { Hide(); SaveFrame(); } else { Reveal(); _ = Refresh("refreshQuotas"); } }
    public void Reveal()
    {
        if (preparedUpdate.IsPresenting) { updateDialog?.Activate(); return; }
        if (prefs.PanelMode == "window")
        {
            if (!IsVisible && prefs.WindowWidth is { } width && prefs.WindowHeight is { } height)
            {
                Width = Math.Clamp(width, MinWidth, SystemParameters.WorkArea.Width);
                Height = Math.Clamp(height, MinHeight, SystemParameters.WorkArea.Height);
                Left = Math.Clamp(prefs.WindowLeft ?? (SystemParameters.WorkArea.Width - Width) / 2, SystemParameters.WorkArea.Left, Math.Max(SystemParameters.WorkArea.Left, SystemParameters.WorkArea.Right - Width));
                Top = Math.Clamp(prefs.WindowTop ?? (SystemParameters.WorkArea.Height - Height) / 2, SystemParameters.WorkArea.Top, Math.Max(SystemParameters.WorkArea.Top, SystemParameters.WorkArea.Bottom - Height));
            }
            else if (!IsVisible)
            {
                Left = SystemParameters.WorkArea.Left + (SystemParameters.WorkArea.Width - Width) / 2;
                Top = SystemParameters.WorkArea.Top + (SystemParameters.WorkArea.Height - Height) / 2;
            }
        }
        else
        {
            Left = Math.Max(SystemParameters.WorkArea.Left, SystemParameters.WorkArea.Right - Width - 12);
            Top = Math.Max(SystemParameters.WorkArea.Top, SystemParameters.WorkArea.Bottom - Height - 12);
        }
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Show(); Activate();
    }
    void SaveFrame()
    {
        if (prefs.PanelMode == "window" && WindowState == WindowState.Normal)
        { prefs.WindowLeft = Left; prefs.WindowTop = Top; prefs.WindowWidth = Width; prefs.WindowHeight = Height; }
        try { prefs.Save(); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }
    void ApplyMode()
    {
        Topmost = prefs.PanelMode == "alwaysOnTop";
        ShowInTaskbar = prefs.PanelMode == "window";
        WindowStyle = prefs.PanelMode == "window" ? WindowStyle.SingleBorderWindow : WindowStyle.None;
        ResizeMode = prefs.PanelMode == "window" ? ResizeMode.CanResize : ResizeMode.NoResize;
    }
    public async Task Refresh(string command)
    {
        if (engine is null) return;
        try
        {
            if ((command == "refreshQuotas" || command == "refreshCurrentQuota") && prefs.QwenWebsiteConnected)
            {
                qwenWindow ??= new QwenWebsiteWindow(engine, prefs, SetState);
                try { await qwenWindow.Refresh(); } catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException or System.ComponentModel.Win32Exception or Microsoft.Web.WebView2.Core.WebView2RuntimeNotFoundException) { }
            }
            var view = (prefs.Category, prefs.Grouping, prefs.Language);
            var response = await engine.Request(command, prefs);
            if (view != (prefs.Category, prefs.Grouping, prefs.Language)) return;
            if (response.Result is { } result) SetState(result);
            if ((command == "refreshQuotas" || command == "refreshCurrentQuota") && prefs.XaiSubscriptionWebsiteConnected)
            {
                xaiSubscriptionWindow ??= new XAIWebsiteSubscriptionWindow(engine, prefs, SetState);
                _ = RefreshXaiSubscription();
            }
        }
        catch (Exception e) when (e is IOException or TimeoutException or InvalidOperationException) { status.Text = Tr("Could not refresh. Try again.", "刷新失败，请重试。"); }
    }
    async Task RefreshXaiSubscription()
    {
        try { if (xaiSubscriptionWindow is not null) await xaiSubscriptionWindow.Refresh(); }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException or System.ComponentModel.Win32Exception or Microsoft.Web.WebView2.Core.WebView2RuntimeNotFoundException) { }
    }
    public void SetState(DisplayState result)
    {
        state = result; Render();
        if (Tray is not null)
        {
            var text = "AI BenchGauge" + (result.TrayText is { } quota ? " · " + quota : "");
            Tray.Text = text.Length <= 63 ? text : text[..60] + "…";
            foreach (var alert in result.Alerts) Tray.ShowBalloonTip(5000, alert.Title, alert.Body, Forms.ToolTipIcon.Warning);
        }
    }
    void Render()
    {
        rendering = true;
        try
        {
            (status.Parent as Panel)?.Children.Remove(status);
            dropdowns.Clear(); content.Children.Clear(); content.RowDefinitions.Clear();
            for (var i = 0; i < 4; i++) content.RowDefinitions.Add(new RowDefinition { Height = i == 2 ? new GridLength(1, GridUnitType.Star) : GridLength.Auto });
            var header = new DockPanel { Margin = new Thickness(0, 0, 0, 12), LastChildFill = false };
            headerTitle = new TextBlock { Text = "AI BenchGauge", FontWeight = FontWeights.SemiBold, FontSize = 17, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0), Visibility = Width < 740 ? Visibility.Collapsed : Visibility.Visible };
            header.Children.Add(headerTitle);
            header.Children.Add(Select([("general",Tr("General","综合")),("coding",Tr("Coding","编程","編程")),("image",Tr("Image","图片","圖片")),("video",Tr("Video","视频","視頻"))], prefs.Category, async value => { prefs.Category = value; SaveFrame(); await Refresh("state"); await Refresh("refreshBoards"); }));
            header.Children.Add(Select([("model",Tr("Models","模型")),("company",Tr("Companies","公司"))], prefs.Grouping, async value => { prefs.Grouping = value; SaveFrame(); await Refresh("state"); }));
            var mode = Select([("clickToClose",Tr("Keep open","保持打开","保持打開")),("alwaysOnTop",Tr("Always on top","保持置顶","保持置頂")),("closeOnBlur",Tr("Close on blur","失焦关闭","失焦關閉")),("window",Tr("Window","独立窗口","獨立視窗"))], prefs.PanelMode, value => { SaveFrame(); prefs.PanelMode = value; ApplyMode(); SaveFrame(); Reveal(); return Task.CompletedTask; });
            DockPanel.SetDock(mode, Dock.Right); header.Children.Add(mode);
            var language = Select([("zh","简体中文"),("zh-Hant","繁體中文"),("en","English")], prefs.Language, async value => { prefs.Language = value; SaveFrame(); Render(); await Refresh("state"); });
            DockPanel.SetDock(language, Dock.Right); header.Children.Add(language);
            Place(header, 0);
            quotaPanel.Children.Clear();
            if (state?.QuotaNeedsCCSwitch == true)
                quotaPanel.Children.Add(LinkButton(Tr("Install CC Switch to view remaining quotas", "安装 CC Switch 查看余量", "安裝 CC Switch 查看餘量"), "https://github.com/farion1231/cc-switch"));
            foreach (var quota in state?.Quotas ?? [])
            {
                var text = new TextBlock { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(8), MaxWidth = 340, ToolTip = quota.Help };
                text.Inlines.Add(new System.Windows.Documents.Run(quota.Name + "  ") { FontWeight = FontWeights.SemiBold });
                foreach (var run in quota.Runs) text.Inlines.Add(new System.Windows.Documents.Run(run.Text) { Foreground = (Brush)new BrushConverter().ConvertFromString(run.Light)! });
                if (quota.IsStale) text.Inlines.Add(new System.Windows.Documents.Run("  · " + Tr("saved", "缓存", "快取")) { Foreground = Brushes.Gray });
                var background = quota.AccentLight is { } accent
                    ? new SolidColorBrush((Color)ColorConverter.ConvertFromString(accent)) { Opacity = quota.IsCurrent ? 0.12 : 0.06 }
                    : Brushes.White;
                var card = new Border { Child = text, CornerRadius = new CornerRadius(7), Background = background, Margin = new Thickness(0, 0, 8, 6), BorderThickness = new Thickness(quota.IsCurrent ? 1 : 0), BorderBrush = Brushes.DodgerBlue };
                card.Cursor = Cursors.Hand;
                card.MouseLeftButtonUp += async (_, _) => { if (quota.CanConnect) await Connect(quota); else if (quota.Url is { } url) Open(url); };
                quotaPanel.Children.Add(card);
            }
            if (state?.QuotaUnavailable == true) quotaPanel.Children.Add(new TextBlock { Text = Tr("CC Switch data unavailable", "CC Switch 数据暂不可用"), Foreground = Brushes.DarkOrange });
            Place(quotaArea, 1);
            var boards = new Grid(); boards.ColumnDefinitions.Add(new ColumnDefinition()); boards.ColumnDefinitions.Add(new ColumnDefinition());
            var displayed = state?.Boards ?? [];
            for (var i = 0; i < displayed.Length && i < 2; i++)
            {
                var board = RenderBoard(displayed[i]); Grid.SetColumn(board, i); boards.Children.Add(board);
            }
            if (displayed.Length == 0) boards.Children.Add(new TextBlock { Text = Tr("Loading leaderboards…", "正在加载排行榜…"), Margin = new Thickness(12) });
            Place(boards, 2);
            footer = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 10, 0, 0), Height = 28 };
            var left = new StackPanel { Orientation = Orientation.Horizontal };
            left.Children.Add(LinkButton("GitHub", "https://github.com/" + config.Repository));
            left.Children.Add(Button("MIT", () => ShowLicenses(false)));
            left.Children.Add(Button(Tr("Notices","声明","聲明"), () => ShowLicenses(true)));
            left.Children.Add(status);
            var right = new StackPanel { Orientation = Orientation.Horizontal }; DockPanel.SetDock(right, Dock.Right);
            right.Children.Add(Button(Tr("Copy", "截图", "截圖"), Capture));
            right.Children.Add(Button(Tr("Refresh", "刷新"), async () => { if (refreshing) return; refreshing = true; try { await Task.WhenAll(Refresh("refreshBoards"), Refresh("refreshQuotas")); } finally { refreshing = false; } }));
            updateButton = Button("v" + config.Version + (availableUpdate is null ? "" : " ↑"), async () => await CheckUpdates(true)); right.Children.Add(updateButton);
            footer.Children.Add(right); footer.Children.Add(left); Place(footer, 3);
        }
        finally { rendering = false; }
    }
    void Place(UIElement element, int row) { Grid.SetRow(element, row); content.Children.Add(element); }
    FrameworkElement RenderBoard(Board board)
    {
        var box = new DockPanel { Margin = new Thickness(0, 0, 8, 0), LastChildFill = true };
        var header = new StackPanel(); DockPanel.SetDock(header, Dock.Top);
        var heading = new DockPanel(); heading.Children.Add(LinkButton(board.Title, board.Url));
        var country = Select([("",Tr("All countries","所有国家","所有國家")),("china",Tr("China","中国","中國")),("unitedStates",Tr("United States","美国","美國")),("canada",Tr("Canada","加拿大")),("france",Tr("France","法国","法國")),("germany",Tr("Germany","德国","德國")),("singapore",Tr("Singapore","新加坡"))], prefs.Countries.GetValueOrDefault(board.Kind, ""), value => { prefs.Countries[board.Kind] = value; SaveFrame(); Render(); return Task.CompletedTask; });
        DockPanel.SetDock(country, Dock.Right); heading.Children.Add(country); header.Children.Add(heading);
        var note = board.Error ?? (board.UpdatedAt is { } iso && DateTimeOffset.TryParse(iso, out var date) ? date.ToLocalTime().ToString("MM-dd HH:mm", CultureInfo.InvariantCulture) : Tr("Waiting for data", "等待数据", "等待資料"));
        header.Children.Add(new TextBlock { Text = note, Foreground = board.Error is null ? Brushes.Gray : Brushes.DarkOrange, FontSize = 10, Margin = new Thickness(4, 4, 4, 8) }); box.Children.Add(header);
        var rows = new StackPanel(); var filter = prefs.Countries.GetValueOrDefault(board.Kind, "");
        foreach (var entry in board.Entries.Where(entry => filter.Length == 0 || entry.Country == filter))
        {
            var row = new Grid { Height = 25, ToolTip = entry.Help ?? entry.Name };
            foreach (var width in new[] { new GridLength(26), new GridLength(23), new GridLength(1, GridUnitType.Star), new GridLength(42), new GridLength(30), new GridLength(30) }) row.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
            AddCell(row, new TextBlock { Text = entry.Rank.ToString(CultureInfo.InvariantCulture), Foreground = Brushes.Gray, VerticalAlignment = VerticalAlignment.Center }, 0);
            if (entry.Logo is { } logo && File.Exists(Path.Combine(AppContext.BaseDirectory, "logos", logo + ".png")))
                AddCell(row, new Image { Source = new BitmapImage(new Uri(Path.Combine(AppContext.BaseDirectory,"logos",logo+".png"))), Width = 17, Height = 17, Stretch = Stretch.Uniform }, 1);
            AddCell(row, new TextBlock { Text = entry.Name, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center }, 2);
            AddCell(row, new TextBlock { Text = entry.Score.ToString("0.#", CultureInfo.InvariantCulture), FontWeight = FontWeights.SemiBold, TextAlignment = TextAlignment.Right, VerticalAlignment = VerticalAlignment.Center }, 3);
            if (entry.CodingURL is { } coding) AddCell(row, LinkButton("↗", coding, Tr("Coding plan", "编程套餐", "編程方案")), 4);
            if (entry.ApiURL is { } api) AddCell(row, LinkButton("API", api, Tr("API pricing", "API 价格", "API 價格")), 5);
            rows.Children.Add(row);
        }
        box.Children.Add(new ScrollViewer { Content = rows, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled }); return box;
    }
    static void AddCell(Grid row, UIElement cell, int column) { Grid.SetColumn(cell, column); row.Children.Add(cell); }
    ComboBox Select((string Value, string Title)[] items, string selected, Func<string, Task> change)
    {
        var combo = new ComboBox { Margin = new Thickness(3, 0, 3, 0), Padding = new Thickness(4), MinHeight = 26, MaxWidth = 160, VerticalAlignment = VerticalAlignment.Center };
        foreach (var item in items) combo.Items.Add(new ComboBoxItem { Content = item.Title, Tag = item.Value });
        combo.SelectedIndex = Math.Max(0, Array.FindIndex(items, item => item.Value == selected));
        combo.SelectionChanged += async (_, _) => { if (!rendering && combo.SelectedItem is ComboBoxItem item) await change((string)item.Tag); };
        dropdowns.Add(combo); return combo;
    }
    static Button Button(string text, Action action) { var button = new Button { Content = text, Padding = new Thickness(5, 2, 5, 2), Margin = new Thickness(2, 0, 2, 0), VerticalAlignment = VerticalAlignment.Center }; button.Click += (_, _) => action(); return button; }
    static Button Button(string text, Func<Task> action) { var button = new Button { Content = text, Padding = new Thickness(5, 2, 5, 2), Margin = new Thickness(2, 0, 2, 0), VerticalAlignment = VerticalAlignment.Center }; button.Click += async (_, _) => await action(); return button; }
    static Button LinkButton(string text, string url, string? help = null) { var button = Button(text, () => Open(url)); button.ToolTip = help ?? url; button.Foreground = Brushes.RoyalBlue; button.Background = Brushes.Transparent; button.BorderThickness = new Thickness(0); return button; }
    public static void Open(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "https") return;
        try { Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true }); } catch (System.ComponentModel.Win32Exception) { }
    }
    /// Launches the installed CC Switch. Its per-user and per-machine install
    /// directories both keep the executable name, so a miss only means the
    /// caller shows the sign-in instruction instead.
    static bool OpenCCSwitch()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        foreach (var path in new[]
        {
            Path.Combine(local, "cc-switch", "cc-switch.exe"),
            Path.Combine(local, "CC Switch", "cc-switch.exe"),
            Path.Combine(local, "Programs", "cc-switch", "cc-switch.exe"),
            Path.Combine(programFiles, "cc-switch", "cc-switch.exe"),
            Path.Combine(programFiles, "CC Switch", "cc-switch.exe"),
        })
        {
            if (!File.Exists(path)) continue;
            try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); return true; }
            catch (System.ComponentModel.Win32Exception) { }
        }
        return false;
    }
    async Task ManageOfficialAccounts()
    {
        if (engine is null || modalOpen) return;
        modalOpen = true;
        try
        {
            var response = await engine.Request("officialAccounts", prefs);
            CreateOfficialAccountsWindow(response).ShowDialog();
        }
        catch (Exception e) when (e is IOException or TimeoutException or InvalidOperationException) { status.Text = Tr("Could not open account settings. Try again.", "账号设置暂不可用，请重试。"); }
        finally { modalOpen = false; _ = Dispatcher.BeginInvoke(TryPresentPreparedUpdate); }
    }

    internal Window CreateOfficialAccountsWindow(EngineResponse response)
    {
        var window = new Window { Owner = this, Title = Tr("Add model", "添加模型", "添加模型"),
            Width = 500, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var form = new StackPanel { Margin = new Thickness(20) };
        form.Children.Add(new TextBlock { Text = Tr("CC Switch accounts appear automatically. Add an official API or plan key below.",
            "CC Switch 中的账号会自动显示，也可以添加官方 API 或套餐 Key。"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) });
        var providers = new ComboBox { ItemsSource = response.OfficialProviders ?? [], DisplayMemberPath = "Name", SelectedIndex = 0, Margin = new Thickness(0, 0, 0, 8) };
        var description = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.Gray, Margin = new Thickness(0, 0, 0, 8) };
        void DescribeProvider()
        {
            var id = (providers.SelectedItem as OfficialProviderSummary)?.Id;
            description.Text = id switch {
                "minimax-cn" or "minimax-global" => Tr("Coding Plan quota; Hailuo video credits are separate.", "查询 Coding Plan 套餐额度；海螺视频额度另行计算。"),
                "luma" => Tr("Luma API balance; Dream Machine subscriptions are separate.", "查询 Luma API 余额；Dream Machine 网页订阅另行计算。"),
                "bfl" => Tr("Official API credits.", "查询官方 API Credits。"),
                "deepseek" or "stepfun" => Tr("Official API account balance.", "查询官方 API 账户余额。"),
                _ => Tr("Use the official Coding Plan key.", "请使用官方 Coding Plan 套餐 Key。")
            };
        }
        providers.SelectionChanged += (_, _) => DescribeProvider(); DescribeProvider();
        form.Children.Add(providers); form.Children.Add(description);
        form.Children.Add(new TextBlock { Text = Tr("Official API / plan key", "官方 API / 套餐 Key") });
        var key = new PasswordBox { Margin = new Thickness(0, 4, 0, 10), MaxLength = 16_384 }; form.Children.Add(key);
        var message = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DarkRed, Margin = new Thickness(0, 0, 0, 8) }; form.Children.Add(message);
        var actions = new StackPanel { Orientation = Orientation.Horizontal };
        var add = new Button { Content = Tr("Verify and add", "验证并添加"), Margin = new Thickness(0, 0, 10, 0) };
        var done = new Button { Content = Tr("Done", "完成") }; actions.Children.Add(add); actions.Children.Add(done); form.Children.Add(actions);
        var accounts = new StackPanel { Margin = new Thickness(0, 14, 0, 0) };
        form.Children.Add(new ScrollViewer { Content = accounts, MaxHeight = 150, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        bool busy = false;
        void SetBusy(bool value) { busy = value; add.IsEnabled = done.IsEnabled = providers.IsEnabled = key.IsEnabled = accounts.IsEnabled = !value; }
        void DisplayAccounts(OfficialAccountSummary[] values)
        {
            accounts.Children.Clear();
            foreach (var account in values)
            {
                var row = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
                var remove = new Button { Content = Tr("Remove", "移除") }; DockPanel.SetDock(remove, Dock.Right); row.Children.Add(remove);
                var name = response.OfficialProviders?.FirstOrDefault(provider => provider.Id == account.ProviderID)?.Name ?? account.ProviderID;
                row.Children.Add(new TextBlock { Text = name + (account.Label.Length == 0 ? "" : " · " + account.Label), VerticalAlignment = VerticalAlignment.Center });
                remove.Click += async (_, _) => {
                    if (engine is null) return;
                    SetBusy(true); message.Text = "";
                    try {
                        var result = await engine.Request("removeOfficialAccount", prefs, providerID: account.Id);
                        if (result.Result is { } updated) SetState(updated);
                        DisplayAccounts((await engine.Request("officialAccounts", prefs)).OfficialAccounts ?? []);
                    } catch (Exception e) when (e is IOException or TimeoutException or InvalidOperationException) {
                        message.Text = Tr("Could not remove this account. Try again.", "账号移除失败，请重试。");
                    } finally { SetBusy(false); }
                };
                accounts.Children.Add(row);
            }
        }
        DisplayAccounts(response.OfficialAccounts ?? []);
        add.Click += async (_, _) => {
            if (engine is null) return;
            if (providers.SelectedItem is not OfficialProviderSummary selected || string.IsNullOrWhiteSpace(key.Password)) return;
            SetBusy(true); message.Text = Tr("Checking…", "验证中…");
            try {
                var result = await engine.Request("addOfficialAccount", prefs, officialProvider: selected.Id, apiKey: key.Password.Trim());
                key.Password = ""; message.Text = "";
                if (result.Result is { } updated) SetState(updated);
                DisplayAccounts((await engine.Request("officialAccounts", prefs)).OfficialAccounts ?? []);
            } catch (Exception e) when (e is IOException or TimeoutException or InvalidOperationException) {
                message.Text = Tr("Could not verify or save this account. Check the key, region and connection.", "账号验证或保存失败，请检查 Key、地区和网络连接。");
            } finally { SetBusy(false); }
        };
        done.Click += (_, _) => window.Close();
        window.Closing += (_, e) => e.Cancel = busy;
        form.Children.Add(new TextBlock { Text = Tr("Coverage and inclusion", "收录原则与范围", "收錄原則與範圍"),
            FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Brushes.Gray, Margin = new Thickness(0, 12, 0, 6) });
        foreach (var text in new[] {
            Tr("We prioritize official providers in the General, Coding, Image and Video Top 20 lists from Artificial Analysis and Arena.",
                "优先接入 Artificial Analysis 与 Arena 的综合、编程、图片、视频 Top 20 榜单涉及的官方供应商。",
                "優先接入 Artificial Analysis 與 Arena 的綜合、編程、圖片、視頻 Top 20 榜單涉及的官方供應商。"),
            Tr("The menu offers supported official API balance, credits and plan quota queries. Products, plans and regions may have separate quotas; see the selected provider's description.",
                "下拉列表仅提供已支持的官方 API 余额、Credits 和套餐额度查询。不同产品、套餐和地区可能有独立额度，请查看所选供应商的说明。",
                "下拉列表僅提供已支持的官方 API 餘額、Credits 和套餐額度查詢。不同產品、套餐和地區可能有獨立額度，請查看所選供應商的說明。"),
            Tr("Existing OpenAI, Claude, Gemini and Kimi official logins are detected locally. Accounts stay available when a provider leaves the rankings.",
                "已有 OpenAI、Claude、Gemini、Kimi 官方登录会从本地配置自动识别；供应商跌出榜单不会移除已有账号。",
                "已有 OpenAI、Claude、Gemini、Kimi 官方登錄會從本地配置自動識別；供應商跌出榜單不會移除已有帳號。")
        }) form.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap,
            FontSize = 11, Foreground = Brushes.Gray, Margin = new Thickness(0, 0, 0, 6) });
        window.Content = form; window.Closed += (_, _) => key.Password = "";
        return window;
    }

    async Task Connect(Quota quota)
    {
        // A Grok sign-in can only happen inside CC Switch, which owns the auth
        // file this quota reads. The provider website has no sign-in entry.
        if (quota.Connection == "ccswitch")
        {
            status.Text = OpenCCSwitch()
                ? Tr("Sign in to Grok in CC Switch.", "请在 CC Switch 中登录 Grok。", "請在 CC Switch 中登入 Grok。")
                : Tr("Open CC Switch to sign in to Grok.", "请打开 CC Switch 登录 Grok。", "請開啟 CC Switch 登入 Grok。");
            return;
        }
        if (engine is null) return;
        if (quota.Connection == "xaiSubscription")
        {
            xaiSubscriptionWindow ??= new XAIWebsiteSubscriptionWindow(engine, prefs, SetState);
            try { await xaiSubscriptionWindow.Connect(); }
            catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException or System.ComponentModel.Win32Exception or Microsoft.Web.WebView2.Core.WebView2RuntimeNotFoundException)
            { status.Text = Tr("xAI plan connection could not open. Try again.", "xAI 套餐连接暂不可用，请重试。", "xAI 套餐連接暫不可用，請重試。"); }
            return;
        }
        if (quota.Connection == "qwen")
        {
            qwenWindow ??= new QwenWebsiteWindow(engine, prefs, SetState);
            try { await qwenWindow.Connect(); }
            catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException or System.ComponentModel.Win32Exception or Microsoft.Web.WebView2.Core.WebView2RuntimeNotFoundException)
            { status.Text = Tr("Qwen sign-in could not open. Try again.", "千问登录暂不可用，请重试。"); }
            return;
        }
        modalOpen = true;
        try
        {
            var attempt = await engine.Request("connectOpenAI", prefs, providerID: quota.Id);
            if (attempt.AuthorizationURL is not { } url || attempt.LoginID is not { } id) return;
            Open(url); status.Text = Tr("Finish signing in in your browser…", "请在浏览器中完成授权…");
            var result = await engine.Request("finishOpenAI", prefs, quota.Id, id, url);
            if (result.Result is { } refreshed) SetState(refreshed);
        }
        catch (Exception e) when (e is IOException or TimeoutException or InvalidOperationException)
        { status.Text = Tr("Sign-in failed. Try again.", "授权未完成，请重试。"); try { await engine.Request("cancelOpenAI", prefs, providerID: quota.Id); } catch (Exception cancelError) when (cancelError is IOException or TimeoutException or InvalidOperationException) { } }
        finally { modalOpen = false; _ = Dispatcher.BeginInvoke(TryPresentPreparedUpdate); }
    }
    public async Task CheckUpdates(bool manual)
    {
        if (preparedUpdate.Installer is not null) { TryPresentPreparedUpdate(); return; }
        if (checkingUpdate) return;
        checkingUpdate = true;
        try
        {
            availableUpdate = await updater.Check(); Render();
            if (availableUpdate is null) { if (manual) status.Text = Tr("Up to date", "已是最新版"); return; }
            var file = await updater.Download(availableUpdate);
            preparedUpdate.Ready(file);
            TryPresentPreparedUpdate();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Net.Http.HttpRequestException or System.Security.Cryptography.CryptographicException or System.Text.Json.JsonException or FormatException or TaskCanceledException)
        { if (manual) status.Text = Tr("Update check failed. Try again.", "检查更新失败，请重试。"); }
        finally { checkingUpdate = false; }
    }
    void TryPresentPreparedUpdate()
    {
        if (!preparedUpdate.TryPresent(IsVisible, IsActive, modalOpen || panelMenuOpen || dropdowns.Any(box => box.IsDropDownOpen), closing)) return;
        modalOpen = true;
        updateDialog = new PreparedUpdateDialog(this, Tr, InstallPreparedUpdate);
        updateDialog.ShowDialog();
    }
    async void InstallPreparedUpdate()
    {
        var file = preparedUpdate.Confirm();
        if (file is null) return;
        try
        {
            // Recheck the cache after potentially hours awaiting activation.
            file = await updater.Download(availableUpdate!);
            UpdateClient.Install(file);
            closing = true;
            updateDialog?.PrepareForShutdown();
            Application.Current.Shutdown();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or InvalidOperationException or System.Net.Http.HttpRequestException or System.Security.Cryptography.CryptographicException or TaskCanceledException)
        {
            preparedUpdate.InstallationFailed();
            updateDialog?.InstallationFailed();
        }
    }
    void ShowLicenses(bool thirdParty)
    {
        modalOpen = true;
        try
        {
            var directory = Path.Combine(AppContext.BaseDirectory, "Licenses");
            var files = thirdParty ? Directory.GetFiles(directory, "*.txt").Where(file => Path.GetFileName(file) != "AI-BenchGauge.txt") : new[] { Path.Combine(directory, "AI-BenchGauge.txt") };
            var text = string.Join("\n\n", files.Select(file => Path.GetFileNameWithoutExtension(file) + "\n\n" + File.ReadAllText(file)));
            var dialog = new Window { Owner = this, Title = Tr("Licenses & notices", "许可证与声明"), Width = 580, Height = 540, WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Content = new TextBox { Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(16), FontFamily = new FontFamily("Consolas"), FontSize = 11 } };
            dialog.ShowDialog();
        }
        finally { modalOpen = false; _ = Dispatcher.BeginInvoke(TryPresentPreparedUpdate); }
    }
    public BitmapSource RenderScreenshot()
    {
        var original = footer;
        var text = new DockPanel { Height = 28, Margin = new Thickness(0, 10, 0, 0), LastChildFill = true };
        var attribution = new TextBlock { Text = "© cloydlau · MIT", FontSize = 12, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) };
        DockPanel.SetDock(attribution, Dock.Right); text.Children.Add(attribution);
        text.Children.Add(new TextBlock { Text = "github.com/" + config.Repository, FontSize = 12, VerticalAlignment = VerticalAlignment.Center });
        quotaPanel.Visibility = Visibility.Collapsed; privatePrompt.Text = Tr("View your remaining AI quotas with AI BenchGauge · CC Switch", "使用 AI BenchGauge · CC Switch 查看 AI 余量", "使用 AI BenchGauge · CC Switch 查看 AI 餘量"); privatePrompt.Visibility = Visibility.Visible;
        if (original is not null) content.Children.Remove(original); Place(text, 3);
        try
        {
            UpdateLayout();
            var root = (FrameworkElement)Content; var dpi = VisualTreeHelper.GetDpi(this);
            var bitmap = new RenderTargetBitmap((int)Math.Ceiling(root.ActualWidth * dpi.DpiScaleX), (int)Math.Ceiling(root.ActualHeight * dpi.DpiScaleY), dpi.PixelsPerInchX, dpi.PixelsPerInchY, PixelFormats.Pbgra32);
            bitmap.Render(root); bitmap.Freeze(); return bitmap;
        }
        finally { content.Children.Remove(text); if (original is not null) Place(original, 3); quotaPanel.Visibility = Visibility.Visible; privatePrompt.Visibility = Visibility.Collapsed; UpdateLayout(); }
    }
    void Capture()
    {
        try { Clipboard.SetImage(RenderScreenshot()); status.Text = Tr("Copied", "已复制", "已複製"); }
        catch (System.Runtime.InteropServices.COMException) { status.Text = Tr("Clipboard busy. Try again.", "剪贴板忙，请重试。"); }
    }
}
