using System;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using BenchGauge.Shared;

namespace BenchGauge;
sealed partial class MainWindow
{
    bool fixedVisualViewport;

    // The native capture fixture explicitly owns its viewport. Normal popovers
    // use the Mac sizing policy: both name columns, cell chrome, then screen cap.
    public void SetVisualViewport(double width, double height)
    {
        fixedVisualViewport = true; Width = width; Height = height;
    }

    double MeasurePanelText(string text, double size = 13) => new FormattedText(text,
        CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
        new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal),
        size, Brushes.Black, VisualTreeHelper.GetDpi(this).PixelsPerDip).WidthIncludingTrailingWhitespace;

    void UpdatePanelWidth()
    {
        if (fixedVisualViewport || (prefs.PanelMode == "window" && (IsVisible || prefs.WindowWidth.HasValue))) return;
        var layout = state?.LayoutEntries ?? state?.Boards.SelectMany(board => board.Entries)
            .Select(entry => new LayoutEntry(entry.Name, entry.CodingURL is null ? null : "↗", entry.ApiURL is null ? null : "API")).ToArray() ?? [];
        var column = layout.Select(entry => MeasurePanelText(entry.Name) + 54 +
            (entry.PlanTitle is null ? 0 : MeasurePanelText(entry.PlanTitle, 12) + 14) +
            (entry.ApiTitle is null ? 0 : MeasurePanelText(entry.ApiTitle, 12) + 14)).DefaultIfEmpty(0).Max();
        var header = state?.Boards.Select(board => MeasurePanelText(BoardTitle(board) + (board.Kind == "epochECI" || ArenaAttribution.Applies(board) ? " · CC BY 4.0" : ""), 11) + MeasurePanelText(" · " + SourceLens(board), 10)
            + MeasurePanelText("12/31 23:59", 9) + 18)
            .DefaultIfEmpty(0).Max() ?? 0;
        // Shrink the popup with the fixed columns, keeping the measured name
        // allowance stable across categories. English filter titles need more room.
        var chrome = 560 - (60 - 40) - 2 * (52 - CountryColumnWidth) - 2 * (60 - SourceColumnWidth);
        var count = prefs.VisibleBoardKinds().Length;
        var desired = Math.Max(850, Math.Ceiling(Math.Max(column, header) * count + 40 + (chrome - 40) / 2 * count));
        var area = SystemParameters.WorkArea;
        var target = Math.Min(desired, Math.Max(MinWidth, area.Width - 16));
        if (Math.Abs(Width - target) < 0.5) return;
        Width = target;
        if (IsVisible) Left = Math.Max(area.Left, area.Right - Width - 12);
    }
}
