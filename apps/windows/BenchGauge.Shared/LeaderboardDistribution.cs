using System.Globalization;

namespace BenchGauge.Shared;
public sealed record DistributionSlice(string Id, int Count, int Total)
{
    public double Fraction => Total > 0 ? (double)Count / Total : 0;
    public string Percent => Total == 0 ? "—" : Count > 0 && Fraction < .001 ? "<0.1%" : (Fraction * 100).ToString("0.0", CultureInfo.InvariantCulture) + "%";
}
public sealed record LeaderboardDistribution(int Total, DistributionSlice[] Countries, DistributionSlice[] Sources)
{
    public static string CountryKey(string? value)
    {
        var key = LeaderboardCountryPolicy.NormalizeFilter(value ?? "").Trim();
        return key.ToLowerInvariant() switch {
            "china" => "CN", "unitedstates" => "US", "canada" => "CA", "france" => "FR", "germany" => "DE", "singapore" => "SG",
            _ => key.Length == 2 && key.All(char.IsAsciiLetter) ? key.ToUpperInvariant() : "unknown"
        };
    }
    public static LeaderboardDistribution FromEntries(Entry[] entries)
    {
        var total = entries.Length;
        var counts = entries.GroupBy(entry => CountryKey(entry.Country)).ToDictionary(group => group.Key, group => group.Count());
        var known = counts.Where(pair => pair.Key != "unknown").OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal).ToArray();
        var countries = known.Take(5).Select(pair => new DistributionSlice(pair.Key, pair.Value, total)).ToList();
        var other = known.Skip(5).Sum(pair => pair.Value);
        if (other > 0) countries.Add(new("other", other, total));
        if (counts.TryGetValue("unknown", out var unknown)) countries.Add(new("unknown", unknown, total));
        return new(total, countries.ToArray(), new[] { "open", "closed", "unknown" }.Select(id =>
            new DistributionSlice(id, entries.Count(entry => (entry.Openness is "open" or "closed" ? entry.Openness : "unknown") == id), total))
            .Where(slice => slice.Id != "unknown" || slice.Count > 0).ToArray());
    }
}
