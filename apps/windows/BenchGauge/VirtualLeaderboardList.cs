using System;
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

    public VirtualLeaderboardList(int count, Func<int, FrameworkElement> createRow)
    {
        this.createRow = createRow;
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
        ItemsSource = Enumerable.Range(0, count);
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
