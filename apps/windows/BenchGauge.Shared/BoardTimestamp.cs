namespace BenchGauge.Shared;

public readonly record struct BoardTimestamp(DateTimeOffset? Value, bool IsSourceTime)
{
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
