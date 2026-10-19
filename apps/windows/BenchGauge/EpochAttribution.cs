using System;
using System.Collections.Generic;
using System.Text.Json;

namespace BenchGauge;

static class EpochAttribution
{
    sealed record Notice(string Credit, string SourceURL, string LicenseURL, Dictionary<string, string> Changes);
    static readonly Notice Data = Load();
    static Notice Load()
    {
        using var stream = typeof(EpochAttribution).Assembly.GetManifestResourceStream("EpochAttribution.json")
            ?? throw new InvalidOperationException("Missing bundled Epoch ECI attribution");
        return JsonSerializer.Deserialize<Notice>(stream, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidOperationException("Invalid bundled Epoch ECI attribution");
    }
    public static string LicenseURL => Data.LicenseURL;
    public static string FullText(string language) => string.Join("\n", Data.Credit,
        Data.SourceURL + " · " + Data.LicenseURL, Data.Changes.GetValueOrDefault(language, Data.Changes["en"]));
}
