using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;

namespace BenchGauge;

/// Centers the quota cards when they fit on one row; wrapped rows keep their leading alignment.
sealed class QuotaWrapPanel : WrapPanel
{
    protected override Size ArrangeOverride(Size finalSize)
    {
        var children = InternalChildren.Cast<UIElement>().Where(child => child.Visibility != Visibility.Collapsed).ToArray();
        var width = children.Sum(child => child.DesiredSize.Width);
        if (children.Length == 0 || width > finalSize.Width) return base.ArrangeOverride(finalSize);

        // Child desired sizes include margins; center the visible cards, excluding outer margins.
        var leading = (children[0] as FrameworkElement)?.Margin.Left ?? 0;
        var trailing = (children[^1] as FrameworkElement)?.Margin.Right ?? 0;
        var x = Math.Max(0, (finalSize.Width - width + trailing - leading) / 2);
        var height = children.Max(child => child.DesiredSize.Height);
        foreach (var child in children)
        {
            child.Arrange(new Rect(x, 0, child.DesiredSize.Width, height));
            x += child.DesiredSize.Width;
        }
        return finalSize;
    }
}
