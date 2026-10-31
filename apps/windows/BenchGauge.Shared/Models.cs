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
public sealed record Board(string Kind, string Title, string Url, string? UpdatedAt, string? Error, Entry[] Entries, string? FetchedAt = null, CountryOption[]? CountryOptions = null, LeaderboardDistribution? Distribution = null, string? SourceNote = null, JsonElement? ModelMetadataSource = null, string? ContentUpdatedAt = null);
public sealed record CountryOption(string Value, string Label);
public sealed record RankChange(int? Delta = null, bool? IsNew = null);
public sealed record Entry(int Rank, string Name, double Score, string? Organization, string? Country, string? Logo, string? CodingURL, string? ApiURL, string? Help, string? Openness = null, string? BrandColor = null, string? LogoPNG = null, string? Initials = null, JsonElement? ModelMetadata = null, int? VoteCount = null, ModelDetailSection[]? Details = null, string? DetailID = null, RankChange? RankChange = null, double? TaskCostUSD = null, double? Speed = null, double? OutputPriceUSD = null, string? Provider = null);
public sealed record ModelDetailSection(string Id, string Title, string? Summary, ModelDetailRow[] Rows);
public sealed record ModelDetailRow(string Label, string Value, string? Url);
public sealed record Quota(string Id, string Name, bool IsCurrent, bool IsStale, string Help, string? Url, bool CanConnect, string? Connection, Run[] Runs, string? AccentLight = null, bool IsDimmed = false, string? LogoPNG = null, string? Initials = null);
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
    string category = "general";
    public string Category { get => VisibleCategories().Contains(category) ? category : VisibleCategories()[0]; set => category = value == "price" ? "usage" : value; }
    public int SpecialistIndex { get; set; }
    public Dictionary<string, string[]> BoardSelections { get; set; } = [];
    public Dictionary<string, string> MediaSelections { get; set; } = [];
    public static string[] MediaVariants(string kind) => kind switch {
        "arenaText" or "arenaTextUncontrolled" => ["arenaText", "arenaTextUncontrolled"],
        "codeArenaWebDev" or "codeArenaImageToWebDev" => ["codeArenaWebDev", "codeArenaImageToWebDev"],
        "artificialAnalysisTextToImage" or "artificialAnalysisImageEditing" => ["artificialAnalysisTextToImage", "artificialAnalysisImageEditing"],
        "arenaTextToImage" or "arenaImageEditing" or "arenaMultiImageEditing" => ["arenaTextToImage", "arenaImageEditing", "arenaMultiImageEditing"],
        "artificialAnalysisTextToVideo" or "artificialAnalysisImageToVideo" or "artificialAnalysisVideoEditing" => ["artificialAnalysisTextToVideo", "artificialAnalysisImageToVideo", "artificialAnalysisVideoEditing"],
        "arenaTextToVideo" or "arenaImageToVideo" or "arenaVideoEditing" => ["arenaTextToVideo", "arenaImageToVideo", "arenaVideoEditing"],
        "artificialAnalysisSpeechProviderVoice" or "artificialAnalysisSpeechControlledVoice" or "artificialAnalysisSpeechAgent" or "artificialAnalysisSpeechToText" or "artificialAnalysisSpeechToTextStreaming" => ["artificialAnalysisSpeechProviderVoice", "artificialAnalysisSpeechControlledVoice", "artificialAnalysisSpeechAgent", "artificialAnalysisSpeechToText", "artificialAnalysisSpeechToTextStreaming"],
        _ => []
    };
    public bool SelectMediaVariant(string current, string selected)
    {
        var variants = MediaVariants(current);
        if (variants.Length == 0 || !variants.Contains(selected) || current == selected) return false;
        MediaSelections ??= [];
        if (selected == variants[0]) MediaSelections.Remove(variants[0]);
        else MediaSelections[variants[0]] = selected;
        return true;
    }
    public HashSet<string> MetricGuidesSeen { get; set; } = [];
    public bool HasSeenMetricGuide(string kind) => MetricGuidesSeen?.Contains(kind) == true;
    public bool MarkMetricGuideSeen(string kind)
    {
        if (kind is not ("openRouterUsage" or "artificialAnalysis" or "artificialAnalysisCodingAgent" or "valsSWEbench" or "artificialAnalysisTextToImage" or "artificialAnalysisImageEditing" or "artificialAnalysisTextToVideo" or "artificialAnalysisImageToVideo" or "artificialAnalysisVideoEditing")) return false;
        MetricGuidesSeen ??= [];
        return MetricGuidesSeen.Add(kind);
    }
    public static readonly string[] Categories = ["usage", "general", "image", "video", "coding", "speech"];
    public string[] AvailableBoardKinds() => AvailableBoardKinds(Category);
    public static string[] AvailableBoardKinds(string category) => category switch {
        "coding" => ["artificialAnalysisCodingAgent", "codeArenaWebDev", "epochSoftwareECI"],
        "image" => ["artificialAnalysisTextToImage", "arenaTextToImage"],
        "video" => ["artificialAnalysisTextToVideo", "arenaTextToVideo"],
        "speech" => ["artificialAnalysisSpeechProviderVoice", "epochMathECI", "epochCyberECI"],
        "usage" => ["openRouterUsage", "vercelUsage", "cloudbaseUsage"],
        "price" => ["openRouterPrice"],
        _ => ["artificialAnalysis", "arenaText", "epochECI"]
    };
    public string[] SelectedBoardKinds(string category)
    {
        var all = AvailableBoardKinds(category);
        var selected = BoardSelections?.GetValueOrDefault(category);
        if (selected is null) return all;
        var valid = all.Where(selected.Contains).ToArray();
        return selected.Length == 0 ? [] : valid.Length == 0 ? all : valid;
    }
    public string[] VisibleCategories()
    {
        var visible = Categories.Where(value => SelectedBoardKinds(value).Length > 0).ToArray();
        return visible.Length == 0 ? Categories : visible;
    }
    public int SelectedBoardCount() => Categories.Sum(value => SelectedBoardKinds(value).Length);
    public void NormalizeBoardSelections()
    {
        if (SelectedBoardCount() == 0) BoardSelections = [];
        BoardSelections = Categories.Select(value => (Category: value, Kinds: SelectedBoardKinds(value)))
            .Where(value => !value.Kinds.SequenceEqual(AvailableBoardKinds(value.Category)))
            .ToDictionary(value => value.Category, value => value.Kinds);
        category = Category;
    }
    public string[] VisibleBaseBoardKinds()
    {
        var selected = SelectedBoardKinds(Category);
        return Category == "speech" && selected.Length > 0 ? [selected[Math.Clamp(SpecialistIndex, 0, selected.Length - 1)]] : selected;
    }
    public string[] VisibleBoardKinds() => VisibleBaseBoardKinds().Select(kind =>
        MediaSelections?.TryGetValue(kind, out var chosen) == true && MediaVariants(kind).Contains(chosen) ? chosen : kind).ToArray();
    public void ToggleBoard(string kind)
    {
        var current = SelectedBoardKinds(Category);
        if (!AvailableBoardKinds().Contains(kind) || (SelectedBoardCount() == 1 && current.Contains(kind))) return;
        SetVisibleBoards(AvailableBoardKinds().Where(value => value == kind ? !current.Contains(value) : current.Contains(value)));
    }
    public bool SetVisibleBoards(IEnumerable<string> kinds)
    {
        var selected = kinds.ToHashSet();
        if (selected.Any(value => !AvailableBoardKinds().Contains(value))) return false;
        var draft = new Dictionary<string, string[]>(BoardSelections ?? []);
        draft[Category] = AvailableBoardKinds().Where(selected.Contains).ToArray();
        return SetBoardSelections(draft);
    }
    public bool SetBoardSelections(Dictionary<string, string[]> selections)
    {
        var draft = new Preferences { BoardSelections = selections };
        if (draft.SelectedBoardCount() == 0) return false;
        draft.NormalizeBoardSelections();
        if (Categories.All(value => draft.SelectedBoardKinds(value).SequenceEqual(SelectedBoardKinds(value)))) return false;
        var previous = Category;
        var specialist = Category == "speech" ? VisibleBaseBoardKinds().FirstOrDefault() : null;
        BoardSelections = draft.BoardSelections;
        category = VisibleCategories().Contains(previous) ? previous : VisibleCategories()[0];
        if (specialist is not null) SpecialistIndex = Math.Max(0, Array.IndexOf(SelectedBoardKinds("speech"), specialist));
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
        try { var value = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(Path.Combine(DirectoryPath, "settings.json")), AppConfig.Json) ?? new(); value.NormalizeBoardSelections(); return value; }
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
