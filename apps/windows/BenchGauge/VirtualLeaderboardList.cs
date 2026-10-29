using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BenchGauge;

// The item source contains indices only. WPF creates row controls for the
// viewport/cache and recycles their containers as the user scrolls.
sealed class VirtualLeaderboardList : ListBox
{
    readonly Func<int, FrameworkElement> createRow;
    readonly ObservableCollection<int> indices = new();
    readonly int rankingCount;
    int loadedCount;

    public VirtualLeaderboardList(int count, Func<int, FrameworkElement> createRow)
    {
        this.createRow = createRow;
        rankingCount = Math.Max(0, count - 1);
        loadedCount = Math.Min(20, rankingCount);
        foreach (var index in Enumerable.Range(0, loadedCount)) indices.Add(index);
        indices.Add(rankingCount); // Distribution panel remains after the loaded rows.
        Background = Brushes.Transparent;
        BorderThickness = new Thickness(0);
        Padding = new Thickness(0);
        IsTabStop = false;
        ScrollViewer.SetCanContentScroll(this, true);
        ScrollViewer.SetVerticalScrollBarVisibility(this, ScrollBarVisibility.Auto);
        ScrollViewer.SetHorizontalScrollBarVisibility(this, ScrollBarVisibility.Disabled);
        VirtualizingPanel.SetIsVirtualizing(this, true);
        VirtualizingPanel.SetVirtualizationMode(this, VirtualizationMode.Recycling);
        VirtualizingPanel.SetScrollUnit(this, ScrollUnit.Pixel);
        VirtualizingPanel.SetCacheLength(this, new VirtualizationCacheLength(1));
        VirtualizingPanel.SetCacheLengthUnit(this, VirtualizationCacheLengthUnit.Page);
        ItemsPanel = new ItemsPanelTemplate(new FrameworkElementFactory(typeof(VirtualizingStackPanel)));
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.ContentProperty, new TemplateBindingExtension(ContentControl.ContentProperty));
        presenter.SetValue(HorizontalAlignmentProperty, HorizontalAlignment.Stretch);
        var template = new ControlTemplate(typeof(ListBoxItem)) { VisualTree = presenter };
        ItemContainerStyle = new Style(typeof(ListBoxItem))
        {
            Setters = {
                new Setter(Control.TemplateProperty, template),
                new Setter(Control.PaddingProperty, new Thickness(0)),
                new Setter(Control.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch),
                new Setter(FocusableProperty, false),
            }
        };
        System.Windows.Automation.AutomationProperties.SetAutomationId(this, "leaderboard-rows");
        ItemsSource = indices;
        AddHandler(ScrollViewer.ScrollChangedEvent, new ScrollChangedEventHandler((_, change) =>
        {
            if (change.VerticalChange <= 0 || change.VerticalOffset + change.ViewportHeight < loadedCount * 32 - 96) return;
            LoadMore();
        }));
    }

    void LoadMore()
    {
        var next = Math.Min(rankingCount, loadedCount + 20);
        while (loadedCount < next) indices.Insert(indices.Count - 1, loadedCount++);
    }

    // Refresh visible content in place without replacing the list or its scroll viewer.
    public void RefreshRealizedRows()
    {
        for (var position = 0; position < indices.Count; position++)
            if (ItemContainerGenerator.ContainerFromIndex(position) is ListBoxItem item && indices[position] < rankingCount)
                item.Content = createRow(indices[position]);
    }

    protected override void PrepareContainerForItemOverride(DependencyObject element, object item)
    {
        base.PrepareContainerForItemOverride(element, item);
        ((ListBoxItem)element).Content = createRow((int)item);
    }

    protected override void ClearContainerForItemOverride(DependencyObject element, object item)
    {
        ((ListBoxItem)element).Content = null;
        base.ClearContainerForItemOverride(element, item);
    }
}
