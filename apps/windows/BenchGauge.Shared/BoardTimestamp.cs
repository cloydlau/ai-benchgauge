namespace BenchGauge.Shared;

public readonly record struct BoardTimestamp(DateTimeOffset? Value, bool IsSourceTime)
{
    public static BoardTimestamp For(Board board) => UpdateAge.Parse(board.UpdatedAt) is { } source
        ? new(source, true)
        : new(UpdateAge.Parse(board.FetchedAt), false);

    public string Caption(string value, string language)
    {
        var label = language == "en" ? IsSourceTime ? "Published" : "Updated"
            : IsSourceTime ? language == "zh-Hant" ? "發佈" : "发布" : "更新";
        return $"{value} {label}";
    }
}
