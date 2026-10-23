using System.Text.Json;

namespace BenchGauge.Shared;
public static class UsageLicense
{
    public static string Text(string kind, string? sourceNote, string language)
    {
        using var stream = typeof(UsageLicense).Assembly.GetManifestResourceStream("BenchGauge.Shared.CC-BY-4.0.json")
            ?? throw new InvalidOperationException("Missing CC BY 4.0 license");
        using var document = JsonDocument.Parse(stream);
        var key = language is "zh" or "zh-CN" ? "zh" : language is "zh-Hant" or "zh-TW" ? "zh-Hant" : "en";
        var credit = !string.IsNullOrWhiteSpace(sourceNote) ? sourceNote : kind == "vercelUsage"
            ? "© 2026 Vercel. \"AI Gateway Leaderboard Data\" is licensed under CC BY 4.0. To view a copy of this license, visit https://creativecommons.org/licenses/by/4.0/\nSource: https://vercel.com/ai-gateway/leaderboards/models"
            : "Source: OpenRouter (openrouter.ai/rankings). Licensed under CC BY 4.0.\nhttps://creativecommons.org/licenses/by/4.0/";
        return credit.Trim() + "\n\n" + document.RootElement.GetProperty(key).GetString();
    }
}
