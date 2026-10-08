using System.Reflection;
using System.Text.Json;

namespace BenchGauge.Shared;
public sealed record AppConfig(string Version, string Repository, string UpdatePublicKey)
{
    public static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    public static AppConfig Load()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("BenchGauge.Shared.app.json")
            ?? throw new InvalidOperationException("Missing application configuration");
        return JsonSerializer.Deserialize<AppConfig>(stream, Json) ?? throw new InvalidOperationException("Invalid application configuration");
    }
}
public sealed record DisplayState(Board[] Boards, Quota[] Quotas, bool QuotaNeedsCCSwitch, bool QuotaUnavailable, string? TrayText, Alert[] Alerts, LayoutEntry[]? LayoutEntries = null, string? QuotaUpdatedAt = null);
public sealed record LayoutEntry(string Name, string? PlanTitle, string? ApiTitle);
public sealed record Board(string Kind, string Title, string Url, string? UpdatedAt, string? Error, Entry[] Entries, string? FetchedAt = null);
public sealed record Entry(int Rank, string Name, double Score, string? Organization, string? Country, string? Logo, string? CodingURL, string? ApiURL, string? Help);
public sealed record Quota(string Id, string Name, bool IsCurrent, bool IsStale, string Help, string? Url, bool CanConnect, string? Connection, Run[] Runs, string? AccentLight = null);
public sealed record Run(string Text, string Light, string Dark);
public sealed record Alert(string Title, string Body);
public sealed record OfficialAccountSummary(string Id, string ProviderID, string Label);
public sealed record OfficialProviderSummary(string Id, string Name, string Description);
public sealed record EngineResponse(int Id, DisplayState? Result, string? AuthorizationURL, string? LoginID, string? Error,
    OfficialAccountSummary[]? OfficialAccounts = null, OfficialProviderSummary[]? OfficialProviders = null,
    bool? QwenAuthenticated = null, bool? QwenQuotaCaptured = null);
public sealed class Preferences
{
    public string Category { get; set; } = "general";
    public string Grouping { get; set; } = "model";
    public string Language { get; set; } = System.Globalization.CultureInfo.CurrentUICulture.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "zh" : "en";
    public bool QwenWebsiteConnected { get; set; }
    public bool XaiSubscriptionWebsiteConnected { get; set; }
    public string PanelMode { get; set; } = "clickToClose";
    public Dictionary<string, string> Countries { get; set; } = [];
    public double? WindowLeft { get; set; }
    public double? WindowTop { get; set; }
    public double? WindowWidth { get; set; }
    public double? WindowHeight { get; set; }
    public static string DirectoryPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AI-BenchGauge");
    public static Preferences Load()
    {
        try { return JsonSerializer.Deserialize<Preferences>(File.ReadAllText(Path.Combine(DirectoryPath, "settings.json")), AppConfig.Json) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }
    public void Save()
    {
        Directory.CreateDirectory(DirectoryPath);
        var file = Path.Combine(DirectoryPath, "settings.json");
        var temporary = file + "." + Guid.NewGuid() + ".tmp";
        try { File.WriteAllText(temporary, JsonSerializer.Serialize(this, AppConfig.Json)); File.Move(temporary, file, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
