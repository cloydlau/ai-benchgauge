using System;
using System.Collections.Generic;
using System.Text.Json;
using BenchGauge.Shared;

namespace BenchGauge;

static class ArenaAttribution
{
    sealed record Notice(string Credit, string SourceURL, string LicenseURL, Dictionary<string, string> Changes);
    static readonly Notice Data = Load();
    static Notice Load()
    {
        using var stream = typeof(ArenaAttribution).Assembly.GetManifestResourceStream("arena-attribution.json")
            ?? throw new InvalidOperationException("Missing Arena data attribution");
        return JsonSerializer.Deserialize<Notice>(stream, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidOperationException("Invalid Arena data attribution");
    }
    public static bool Applies(Board board) => (board.Kind.StartsWith("arena") || board.Kind == "codeArenaWebDev")
        && board.SourceNote?.Contains(Data.SourceURL) == true;
    public static string LicenseURL => Data.LicenseURL;
    public static string FullText(string language) => string.Join("\n", Data.Credit,
        Data.SourceURL + " · " + Data.LicenseURL, Data.Changes.GetValueOrDefault(language, Data.Changes["en"]));
}
