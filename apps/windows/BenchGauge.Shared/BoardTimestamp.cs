namespace BenchGauge.Shared;

public readonly record struct BoardTimestamp(DateTimeOffset? Value, bool IsSourceTime)
{
    public static string ExplanationTitle(string language) => language == "en" ? "Time labels"
        : language is "zh-Hant" or "zh-TW" ? "時間說明" : "时间说明";

    public static string Explanation(string language) => language == "en"
        ? "Leaderboard data is updated in real time. There are two types of time labels:\n\nPublished: When a leaderboard provides a publication time, that time is displayed.\n\nRefreshed: When a leaderboard does not provide a publication time, the last time new leaderboard data became available is displayed. Refreshing unchanged data keeps this time unchanged."
        : language is "zh-Hant" or "zh-TW"
        ? "榜單資料即時更新。時間標記分為兩種：\n\n發佈：榜單提供了發佈時間，展示其發佈時間。\n\n刷新：榜單未提供發佈時間，展示上一次更新到新資料的時間；資料沒有變化時，時間保持不變。"
        : "榜单数据实时更新。时间标记分为两种：\n\n发布：榜单提供了发布时间，展示其发布时间。\n\n刷新：榜单未提供发布时间，展示上一次更新到新数据的时间；数据没有变化时，时间保持不变。";

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
        : new(UpdateAge.Parse(board.ContentUpdatedAt) ?? UpdateAge.Parse(board.FetchedAt), false);

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
