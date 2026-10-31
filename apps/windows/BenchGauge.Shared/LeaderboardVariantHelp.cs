using System.Text.Json;

namespace BenchGauge.Shared;

public static class LeaderboardVariantHelp
{
    sealed record Option(string[] Title, string[] Detail);
    sealed record Catalog(string[] Heading, Dictionary<string, Option> Options, Dictionary<string, string[]> References);
    static readonly Catalog Data = Load();
    static Catalog Load()
    {
        using var stream = typeof(LeaderboardVariantHelp).Assembly.GetManifestResourceStream("BenchGauge.Shared.LeaderboardVariantHelp.json")
            ?? throw new InvalidOperationException("Missing sub-leaderboard explanations");
        return JsonSerializer.Deserialize<Catalog>(stream, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
    }
    public static string Text(string kind, string language)
    {
        var variants = Preferences.MediaVariants(kind);
        if (variants.Length == 0) return "";
        var index = language == "en" ? 0 : language is "zh-Hant" or "zh-TW" ? 2 : 1;
        var options = variants.Select(option => Data.Options[option].Title[index] + "\n" + Data.Options[option].Detail[index]);
        return string.Join("\n\n", new[] { Data.Heading[index] }.Concat(options)
            .Concat(Data.References.GetValueOrDefault(variants[0], [])));
    }
}
