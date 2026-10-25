namespace BenchGauge.Shared;

public readonly record struct BoardTimestamp(DateTimeOffset? Value, bool IsSourceTime)
{
    public string FormatValue(DateTimeOffset now, string language, TimeZoneInfo? timeZone = null,
                              bool dateOnly = false, bool includesYear = false)
    {
        if (Value is not { } stamp) return "—";
        var zone = timeZone ?? TimeZoneInfo.Local;
        var date = TimeZoneInfo.ConvertTime(stamp, zone);
        var today = TimeZoneInfo.ConvertTime(now, zone);
        var days = (today.Date - date.Date).Days;
        var culture = System.Globalization.CultureInfo.InvariantCulture;
        if (days is >= 0 and <= 3)
        {
            var labels = language == "en" ? new[] { "Today", "Yesterday", "2 days ago", "3 days ago" }
                : new[] { "今天", "昨天", "前天", "大前天" };
            return dateOnly ? labels[days] : $"{labels[days]} {date.ToString("HH:mm", culture)}";
        }
        return date.ToString(dateOnly ? includesYear ? "yyyy-MM-dd" : "M/d" : "M/d HH:mm", culture);
    }

    public static BoardTimestamp For(Board board) => board.Kind is not ("vercelUsage" or "cloudbaseUsage")
        && UpdateAge.Parse(board.UpdatedAt) is { } source
        ? new(source, true)
        : new(UpdateAge.Parse(board.FetchedAt), false);

    public static string? StatisticalDay(Board board, string language)
    {
        if (board.Kind != "vercelUsage" || UpdateAge.Parse(board.UpdatedAt) is not { } day) return null;
        var label = language == "en" ? "Statistical day (UTC): "
            : language is "zh-Hant" or "zh-TW" ? "統計日期（UTC）：" : "统计日期（UTC）：";
        return label + day.UtcDateTime.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
    }

    public string Caption(string value, string language)
    {
        var label = language == "en" ? IsSourceTime ? "Published" : "Refreshed"
            : IsSourceTime ? language == "zh-Hant" ? "發佈" : "发布" : "刷新";
        return $"{value} {label}";
    }
}
