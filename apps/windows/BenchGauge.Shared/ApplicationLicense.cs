using System.Text.Json;

namespace BenchGauge.Shared;

public static class ApplicationLicense
{
    sealed record Document(string Name, string ShortName);
    static readonly Document document = Load();
    static Document Load()
    {
        using var stream = typeof(ApplicationLicense).Assembly.GetManifestResourceStream("BenchGauge.Shared.ApplicationLicense.json")
            ?? throw new InvalidOperationException("Missing application license identity");
        return JsonSerializer.Deserialize<Document>(stream, AppConfig.Json)
            ?? throw new InvalidOperationException("Invalid application license identity");
    }
    public static string Name => document.Name;
    public static string ShortName => document.ShortName;
}
