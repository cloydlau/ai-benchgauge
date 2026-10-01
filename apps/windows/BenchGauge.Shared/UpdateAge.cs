using System.Globalization;

namespace BenchGauge.Shared;
public static class UpdateAge
{
    public static DateTimeOffset? Parse(string? stamp) => DateTimeOffset.TryParse(stamp, CultureInfo.InvariantCulture,
        DateTimeStyles.RoundtripKind, out var date) ? date : null;

    public static string Format(DateTimeOffset? stamp, DateTimeOffset now, string language)
    {
        string Text(string en, string zh, string traditional) => language switch { "zh" => zh, "zh-Hant" => traditional, _ => en };
        if (stamp is null) return Text("pending", "待更新", "待更新");
        var seconds = Math.Max(0, (now - stamp.Value).TotalSeconds);
        if (seconds < 60) return Text("just now", "刚刚", "剛剛");
        if (seconds < 3600) return Text($"{(int)(seconds / 60)} min ago", $"{(int)(seconds / 60)} 分钟前", $"{(int)(seconds / 60)} 分鐘前");
        if (seconds < 86400) return Text($"{(int)(seconds / 3600)} hr ago", $"{(int)(seconds / 3600)} 小时前", $"{(int)(seconds / 3600)} 小時前");
        var days = (int)(seconds / 86400);
        return Text($"{days} {(days == 1 ? "day" : "days")} ago", $"{days} 天前", $"{days} 天前");
    }
}
