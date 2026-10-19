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
public sealed record Board(string Kind, string Title, string Url, string? UpdatedAt, string? Error, Entry[] Entries, string? FetchedAt = null, CountryOption[]? CountryOptions = null, LeaderboardDistribution? Distribution = null, string? SourceNote = null, JsonElement? ModelMetadataSource = null);
public sealed record CountryOption(string Value, string Label);
public sealed record Entry(int Rank, string Name, double Score, string? Organization, string? Country, string? Logo, string? CodingURL, string? ApiURL, string? Help, string? Openness = null, string? BrandColor = null, string? LogoPNG = null, string? Initials = null, JsonElement? ModelMetadata = null, int? VoteCount = null, ModelDetailSection[]? Details = null, string? DetailID = null);
public sealed record ModelDetailSection(string Id, string Title, string? Summary, ModelDetailRow[] Rows);
public sealed record ModelDetailRow(string Label, string Value, string? Url);
public sealed record Quota(string Id, string Name, bool IsCurrent, bool IsStale, string Help, string? Url, bool CanConnect, string? Connection, Run[] Runs, string? AccentLight = null, bool IsDimmed = false);
public sealed record Run(string Text, string Light, string Dark);
public sealed record Alert(string Title, string Body);
public sealed record OfficialAccountSummary(string Id, string ProviderID, string Label);
public sealed record OfficialProviderSummary(string Id, string Name, string Description);
public sealed record EngineResponse(int Id, DisplayState? Result, string? AuthorizationURL, string? LoginID, string? Error,
    OfficialAccountSummary[]? OfficialAccounts = null, OfficialProviderSummary[]? OfficialProviders = null,
    bool? QwenAuthenticated = null, bool? QwenQuotaCaptured = null,
    string? UserCode = null, string? LoginState = null, double? PollInterval = null, double? ExpiresIn = null,
    bool? QwenQuotaRefreshNeeded = null, ModelDetailSection[]? ModelDetails = null);
public static class LeaderboardCountryPolicy
{
    static readonly Dictionary<string, string> CountryOverrides = ReadOverrides();
    static Dictionary<string, string> ReadOverrides()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("BenchGauge.Shared.leaderboard-policy.json")
            ?? throw new InvalidOperationException("Missing leaderboard policy");
        using var document = JsonDocument.Parse(stream);
        return document.RootElement.GetProperty("countryOverrides").EnumerateObject()
            .ToDictionary(item => item.Name, item => item.Value.GetString()!);
    }
    public static string NormalizeFilter(string value)
    {
        var code = value?.Trim().ToUpperInvariant();
        return code is not null && (code == "CN" || CountryOverrides.GetValueOrDefault(code) == "CN") ? "china" : value ?? "";
    }
}
public sealed class Preferences
{
    public string Category { get; set; } = "general";
    public Dictionary<string, string[]> BoardSelections { get; set; } = [];
    public string[] AvailableBoardKinds() => Category switch {
        "coding" => ["artificialAnalysisCodingAgent", "codeArenaWebDev"],
        "image" => ["artificialAnalysisTextToImage", "arenaTextToImage"],
        "video" => ["artificialAnalysisTextToVideo", "arenaTextToVideo"],
        _ => ["artificialAnalysis", "arenaText", "epochECI"]
    };
    public string[] VisibleBoardKinds()
    {
        var all = AvailableBoardKinds();
        var selected = BoardSelections?.GetValueOrDefault(Category);
        var valid = all.Where(kind => selected is null || selected.Contains(kind)).ToArray();
        return valid.Length == 0 ? all : valid;
    }
    public void ToggleBoard(string kind)
    {
        var current = VisibleBoardKinds();
        if (!AvailableBoardKinds().Contains(kind) || (current.Length == 1 && current.Contains(kind))) return;
        SetVisibleBoards(AvailableBoardKinds().Where(value => value == kind ? !current.Contains(value) : current.Contains(value)));
    }
    public bool SetVisibleBoards(IEnumerable<string> kinds)
    {
        var selected = kinds.ToHashSet();
        var next = AvailableBoardKinds().Where(selected.Contains).ToArray();
        if (next.Length == 0 || next.SequenceEqual(VisibleBoardKinds())) return false;
        BoardSelections ??= [];
        BoardSelections[Category] = next;
        return true;
    }
    public string Grouping { get; set; } = "model";
    public string Language { get; set; } = System.Globalization.CultureInfo.CurrentUICulture.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "zh" : "en";
    public bool QwenWebsiteConnected { get; set; }
    public bool XaiSubscriptionWebsiteConnected { get; set; }
    public string PanelMode { get; set; } = "clickToClose";
    public Dictionary<string, string> Sources { get; set; } = [];
    Dictionary<string, string> countries = [];
    public Dictionary<string, string> Countries
    {
        get => countries;
        set => countries = value.ToDictionary(item => item.Key, item => LeaderboardCountryPolicy.NormalizeFilter(item.Value));
    }
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
