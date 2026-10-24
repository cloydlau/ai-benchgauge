using System.Text.Json;

namespace BenchGauge.Shared;
public static class UsageLicense
{
    public static string Text(string kind, string? sourceNote, string language)
    {
        if (kind == "cloudbaseUsage") return (language == "en" ? "Tencent Cloud · Source notice. Sampled-period cumulative token shares; input + output including cache hits, grouped by model family. No absolute volumes or full sample dates published. No open-data license stated; rights retained by Tencent. This is not CC BY data." : language is "zh-Hant" or "zh-TW" ? "騰訊雲 · 來源說明。抽樣統計日累計 token 佔比，輸入與輸出之和含快取命中，按模型系列彙總。未公開絕對用量或完整日期；未聲明開放資料授權，相關權利歸騰訊所有，此資料不適用 CC BY 4.0。" : "腾讯云 · 来源说明。抽样统计日累计 token 占比，输入与输出之和含缓存命中，按模型系列汇总。未公开绝对用量或完整日期；未声明开放数据许可，相关权利归腾讯所有，此数据不适用 CC BY 4.0。") + "\n\n" + (sourceNote ?? "Source: https://docs.cloudbase.net/ai/announcement/model-token-volume");
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
