using System.Globalization;

namespace BenchGauge.Shared;
public static class ScoreShare
{
    public static double FillRatio(double score, double leaderScore)
    {
        if (!double.IsFinite(score) || score < 0 || !double.IsFinite(leaderScore) || leaderScore <= 0) return 1;
        return Math.Min(1, score / leaderScore);
    }

    public static string Format(double score, double leaderScore)
    {
        if (!double.IsFinite(score) || score < 0 || !double.IsFinite(leaderScore) || leaderScore <= 0) return "";
        var percent = Math.Round(score / leaderScore * 100, MidpointRounding.AwayFromZero);
        return percent < 100 ? percent.ToString("0", CultureInfo.InvariantCulture) + "%" : "";
    }
}
