using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using BenchGauge.Shared;

namespace BenchGauge;
sealed partial class MainWindow
{
    string leaderboardQuery = "";
    bool leaderboardSearchExpanded;
    TextBox? leaderboardSearchField;

    FrameworkElement SearchNavigation(FrameworkElement switches)
    {
        var host = new Grid { HorizontalAlignment = HorizontalAlignment.Center, Height = 24 };
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(34) });
        host.Children.Add(switches);
        System.Windows.Shapes.Path SearchIcon() => new() { Data = Geometry.Parse("M 8,4.5 A 3.5,3.5 0 1 1 1,4.5 A 3.5,3.5 0 1 1 8,4.5 M 7,7 L 11,11"),
            Stroke = PanelMuted, StrokeThickness = 1.3, Width = 12, Height = 12,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false };
        var open = QuietButton("", () => { }); open.Content = SearchIcon(); open.Width = 26; open.Focusable = false;
        open.Margin = new Thickness(8, 0, 0, 0); open.ToolTip = Tr("Search models", "搜索模型", "搜尋模型");
        System.Windows.Automation.AutomationProperties.SetAutomationId(open, "leaderboard-search-button");
        System.Windows.Automation.AutomationProperties.SetName(open, (string)open.ToolTip);
        Grid.SetColumn(open, 1); host.Children.Add(open);
        var field = new TextBox { Text = leaderboardQuery, FontSize = 12, FontFamily = FontFamily,
            Foreground = PanelInk, Background = Brushes.Transparent, BorderThickness = new Thickness(0),
            VerticalContentAlignment = VerticalAlignment.Center, Padding = new Thickness(5, 0, 5, 0) };
        leaderboardSearchField = field;
        System.Windows.Automation.AutomationProperties.SetAutomationId(field, "leaderboard-search-input");
        System.Windows.Automation.AutomationProperties.SetName(field, (string)open.ToolTip);
        var input = new Grid();
        input.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) });
        input.Children.Add(SearchIcon());
        input.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        input.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
        Grid.SetColumn(field, 1); input.Children.Add(field);
        var placeholder = Caption((string)open.ToolTip, PanelMuted, 12);
        placeholder.Margin = new Thickness(5, 0, 0, 0); placeholder.IsHitTestVisible = false; Grid.SetColumn(placeholder, 1); input.Children.Add(placeholder);
        var clear = QuietButton("×", () => { field.Clear(); field.Focus(); }); clear.Focusable = false;
        clear.ToolTip = Tr("Clear search", "清空搜索", "清空搜尋"); Grid.SetColumn(clear, 2); input.Children.Add(clear);
        var overlay = new Border { Child = input, Height = 24, HorizontalAlignment = HorizontalAlignment.Right,
            Background = PanelBackground, BorderBrush = PanelLine, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(5), ClipToBounds = true };
        Grid.SetColumnSpan(overlay, 2); host.Children.Add(overlay);
        void Layout(bool animate)
        {
            switches.Opacity = leaderboardSearchExpanded ? 0 : 1;
            switches.IsEnabled = !leaderboardSearchExpanded;
            open.Visibility = leaderboardSearchExpanded ? Visibility.Hidden : Visibility.Visible;
            field.IsTabStop = leaderboardSearchExpanded;
            var target = leaderboardSearchExpanded ? Math.Max(26, host.ActualWidth) : 26;
            if (leaderboardSearchExpanded) overlay.Visibility = Visibility.Visible;
            if (animate)
            {
                var animation = new DoubleAnimation(target, TimeSpan.FromSeconds(.2)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
                animation.Completed += (_, _) => { if (!leaderboardSearchExpanded) overlay.Visibility = Visibility.Collapsed; };
                overlay.BeginAnimation(WidthProperty, animation);
            }
            else { overlay.BeginAnimation(WidthProperty, null); overlay.Width = target; overlay.Visibility = leaderboardSearchExpanded ? Visibility.Visible : Visibility.Collapsed; }
        }
        void Labels()
        {
            placeholder.Visibility = field.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            clear.Visibility = field.Text.Length == 0 ? Visibility.Hidden : Visibility.Visible;
        }
        open.Click += (_, _) => { leaderboardSearchExpanded = true; Layout(true); field.Focus(); };
        field.TextChanged += (_, _) => { leaderboardQuery = field.Text; Labels(); RefreshSearchResults(); };
        field.LostKeyboardFocus += (_, _) => Dispatcher.BeginInvoke(() => {
            if (rendering || leaderboardSearchField != field || field.IsKeyboardFocusWithin || leaderboardQuery.Length > 0) return;
            leaderboardSearchExpanded = false; Layout(true);
        }, DispatcherPriority.Background);
        host.SizeChanged += (_, _) => Layout(false);
        Labels(); Layout(false);
        return host;
    }

    void RefreshSearchResults()
    {
        var old = content.Children.OfType<UIElement>().FirstOrDefault(child => Grid.GetRow(child) == 2);
        if (old is not null) content.Children.Remove(old);
        Place(PairedBoards(), 2);
    }
}
