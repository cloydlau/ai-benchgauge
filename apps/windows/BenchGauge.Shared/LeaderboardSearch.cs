using System.Globalization;

namespace BenchGauge.Shared;
public static class LeaderboardSearch
{
    public static bool Matches(string name, string query) => Compile(query)(name);

    public static Func<string, bool> Compile(string query)
    {
        var words = query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return name => words.All(word => CultureInfo.InvariantCulture.CompareInfo.IndexOf(name, word,
            CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace | CompareOptions.IgnoreWidth) >= 0);
    }
}
