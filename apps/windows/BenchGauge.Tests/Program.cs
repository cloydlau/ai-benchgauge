using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using BenchGauge.Shared;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;

foreach (var language in new[] { "en", "zh", "zh-Hant", "zh-TW" })
{
    var explanation = BoardTimestamp.Explanation(language);
    if (string.IsNullOrEmpty(BoardTimestamp.ExplanationTitle(language)) ||
        !explanation.Contains(language == "en" ? "updated in real time" : language == "zh" ? "实时更新" : "即時更新") ||
        !explanation.Contains(language == "en" ? "does not provide a publication time" : language == "zh" ? "未提供发布时间" : "未提供發佈時間") ||
        explanation.Contains("抓取") || explanation.Contains("retrieved"))
        throw new Exception("Timestamp help must explain publication and fallback refresh labels in every language");
}

// The shared brand catalog covers exact category IDs, independent of column positions.
foreach (var kinds in new[] {
    new[] { "artificialAnalysis", "artificialAnalysisCodingAgent", "artificialAnalysisTextToImage", "artificialAnalysisTextToVideo" },
    new[] { "arenaText", "codeArenaWebDev", "arenaTextToImage", "arenaTextToVideo" },
    new[] { "epochECI" }, new[] { "openRouterUsage" }, new[] { "vercelUsage" } })
    foreach (var dark in new[] { false, true })
        foreach (var kind in kinds)
            if (SourceTabTheme.For(kind, dark) != SourceTabTheme.For(kinds[0], dark)
                || !SourceTabTheme.For(kind, dark).Accent.StartsWith('#'))
                throw new Exception("Source themes must follow complete source identities");
if (SourceTabTheme.For("vercelUsage", false).Accent != "#000000"
    || SourceTabTheme.For("vercelUsage", true).Accent != "#FFFFFF"
    || SourceTabTheme.For("artificialAnalysisCodingAgent-extra", false) != SourceTabTheme.For("unknown-source", false)
    || SourceTabTheme.For("unknown-source", true) == SourceTabTheme.For("unknown-source", false)
    || SourceTabTheme.For("cloudbaseUsage", false).Accent != "#0052D9"
    || SourceTabTheme.For("cloudbaseUsage", true).Accent != "#00A4FF")
    throw new Exception("Source text must retain brand contrast and exact-ID fallback");

// Source data time always wins; snapshot time is only a fallback, never a maximum.
var timestampFetch = DateTimeOffset.Parse("2026-10-22T12:00:00Z");
foreach (var (language, published, updated) in new[] {
    ("en", "Published", "Refreshed"), ("zh", "发布", "刷新"), ("zh-Hant", "發佈", "刷新") })
{
    if (new BoardTimestamp(timestampFetch, true).Caption("10/22 12:00", language) != $"10/22 12:00 {published}" ||
        new BoardTimestamp(timestampFetch, false).Caption("10/22 12:00", language) != $"10/22 12:00 {updated}" ||
        new BoardTimestamp(null, false).Caption("—", language) != $"— {updated}")
        throw new Exception("Timestamp captions must use only publication/update suffixes");
}
foreach (var hours in new[] { -24, 0, 24 })
{
    var source = timestampFetch.AddHours(hours);
    var board = new Board("arenaText", "Fixture", "https://example.test", source.ToString("O"), null, [], timestampFetch.ToString("O"));
    var selected = BoardTimestamp.For(board);
    if (selected.Value != source || !selected.IsSourceTime)
        throw new Exception("Source timestamp must win regardless of fetch order");
}
foreach (var source in new string?[] { null, "", "invalid" })
{
    var board = new Board("arenaText", "Fixture", "https://example.test", source, null, [], timestampFetch.ToString("O"));
    if (BoardTimestamp.For(board) != new BoardTimestamp(timestampFetch, false) ||
        BoardTimestamp.For(board with { FetchedAt = null }) != new BoardTimestamp(null, false))
        throw new Exception("Missing source time must fall back only to fetch time");
}

// Statistical coverage dates must not replace retrieval timestamps in usage headers.
foreach (var kind in new[] { "vercelUsage", "cloudbaseUsage" })
    foreach (var hours in new[] { -24, 0, 24 })
    {
        var board = new Board(kind, "Fixture", "https://example.test", timestampFetch.AddHours(hours).ToString("O"), null, [], timestampFetch.ToString("O"));
        if (BoardTimestamp.For(board) != new BoardTimestamp(timestampFetch, false)
            || BoardTimestamp.For(board with { FetchedAt = "invalid" }) != new BoardTimestamp(null, false))
            throw new Exception("Usage statistical dates must never masquerade as retrieval time");
    }
foreach (var language in new[] { "en", "zh", "zh-Hant" })
{
    var board = new Board("vercelUsage", "Fixture", "https://example.test", "2026-10-22T23:00:00-02:00", null, [], timestampFetch.ToString("O"));
    if (BoardTimestamp.StatisticalDay(board, language) is not { } day || !day.Contains("2026-10-23") || !day.Contains("UTC"))
        throw new Exception("Statistics help must retain the UTC coverage day");
    if (BoardTimestamp.StatisticalDay(board with { Kind = "cloudbaseUsage" }, language) != null
        || BoardTimestamp.StatisticalDay(board with { UpdatedAt = "invalid" }, language) != null)
        throw new Exception("Do not invent unpublished statistical dates");
}

// Every client uses the same midnight, month/year and daylight-saving boundaries.
var calendarRoot = new DirectoryInfo(AppContext.BaseDirectory);
while (calendarRoot != null && !File.Exists(Path.Combine(calendarRoot.FullName, "Tests/fixtures/calendar-timestamps.json")))
    calendarRoot = calendarRoot.Parent;
if (calendarRoot == null) throw new Exception("Calendar timestamp fixture is missing");
using (var calendarFixture = JsonDocument.Parse(File.ReadAllText(Path.Combine(calendarRoot.FullName, "Tests/fixtures/calendar-timestamps.json"))))
    foreach (var sample in calendarFixture.RootElement.GetProperty("cases").EnumerateArray())
        foreach (var language in new[] { "en", "zh", "zh-Hant" })
        {
            var stamp = DateTimeOffset.Parse(sample.GetProperty("date").GetString()!);
            var now = DateTimeOffset.Parse(sample.GetProperty("now").GetString()!);
            var zone = TimeZoneInfo.FindSystemTimeZoneById(sample.GetProperty("timeZone").GetString()!);
            var dateOnly = sample.TryGetProperty("dateOnly", out var only) && only.GetBoolean();
            var includesYear = sample.TryGetProperty("includesYear", out var year) && year.GetBoolean();
            var actual = new BoardTimestamp(stamp, true).FormatValue(now, language, zone, dateOnly, includesYear);
            if (actual != sample.GetProperty(language == "en" ? "en" : "zh").GetString())
                throw new Exception($"Incorrect calendar timestamp: {sample.GetProperty("name").GetString()}, {language}: {actual}");
        }
if (new BoardTimestamp(null, false).FormatValue(timestampFetch, "zh") != "—")
    throw new Exception("Missing timestamps must remain unknown");

// Model distributions retain unknowns and the China policy without score weighting.
var distributionEntries = new[] {
    new Entry(1, "A", 9999, "Maker", "US", null, null, null, null, "closed"),
    new Entry(2, "B", 1, "Maker", "HK", null, null, null, null, "open"),
    new Entry(3, "C", 0, "Maker", "TW", null, null, null, null, "open"),
    new Entry(4, "D", 0, null, null, null, null, null, null) };
var modelDistribution = LeaderboardDistribution.FromEntries(distributionEntries);
if (modelDistribution.Total != 4 || modelDistribution.Countries.Single(slice => slice.Id == "CN").Count != 2 ||
    !modelDistribution.Sources.Select(slice => slice.Count).SequenceEqual(new[] { 2, 1, 1 }) ||
    LeaderboardDistribution.FromEntries([]).Sources.Any(slice => slice.Percent != "—"))
    throw new Exception("Incorrect full-board distributions");
var knownDistribution = LeaderboardDistribution.FromEntries(distributionEntries.Take(3).ToArray());
if (knownDistribution.Countries.Any(slice => slice.Id == "unknown") ||
    !knownDistribution.Sources.Select(slice => slice.Id).SequenceEqual(new[] { "open", "closed" }) ||
    LeaderboardDistribution.FromEntries([]).Sources.Any(slice => slice.Id == "unknown"))
    throw new Exception("Zero-count unknown chart items must be hidden");
var summaryBoard = JsonSerializer.Deserialize<Board>("""{"kind":"arenaText","title":"Arena","url":"https://example.test","entries":[],"distribution":{"total":8,"countries":[{"id":"CN","count":8,"total":8}],"sources":[{"id":"unknown","count":8,"total":8}]}}""", AppConfig.Json)!;
if (summaryBoard.Distribution is not { } summaryDistribution || summaryDistribution.Total != 8 || summaryDistribution.Countries[0].Percent != "100.0%")
    throw new Exception("Engine distribution must survive empty filtered/company projections");

// Search accepts unordered words, case/width/diacritic variants, and whitespace.
var searchInput = new DebouncedSearchQuery();
foreach (var (value, at) in new[] { ("g", 0L), ("gp", 50L), ("gpt", 100L) })
    if (searchInput.Edit(value, at)) throw new Exception("Draft typing filtered synchronously");
if (searchInput.Input != "gpt" || searchInput.Query != "" || searchInput.ApplyIfReady(349) ||
    !searchInput.ApplyIfReady(350) || searchInput.Query != "gpt" || searchInput.ApplyIfReady(600))
    throw new Exception("Rapid typing must produce just one settled search");
searchInput.Edit("claude", 700);
if (!searchInput.Edit("", 750) || searchInput.Query != "" || searchInput.ApplyIfReady(1000))
    throw new Exception("Clearing must restore rows immediately and cancel stale input");
searchInput.Edit("pending", 1100);
searchInput.Edit("中", 1150, composing: true);
if (searchInput.Pending || searchInput.ApplyIfReady(2000) || searchInput.Query != "")
    throw new Exception("IME composition must not refresh the table");
searchInput.Edit("中文", 2100);
if (!searchInput.ApplyIfReady(2350) || searchInput.Query != "中文")
    throw new Exception("Committed IME input must be searchable");
searchInput.Edit("中文", 2400);
if (searchInput.Pending) throw new Exception("Identical input should not schedule another refresh");

foreach (var sample in new (string Name, string Query, bool Expected)[] {
    ("DeepSeek V3.2 Speciale", "speciale DEEP", true),
    ("Café ＧＰＴ", "cafe gpt", true), ("Claude Sonnet", "   ", true),
    ("GPT-5", "GPT Claude", false), ("OpenAI", "openai", true) })
    if (LeaderboardSearch.Matches(sample.Name, sample.Query) != sample.Expected)
        throw new Exception("Incorrect selected-leaderboard search matching");
var compiledSearch = LeaderboardSearch.Compile(" CAFE gpt ");
if (!compiledSearch("Café ＧＰＴ") || compiledSearch("Café Claude"))
    throw new Exception("Prepared search must retain matching rules across rows");

foreach (var sample in new[] {
    (Score: 100d, Leader: 100d, Expected: 1d), (50, 100, 0.5), (99.6, 100, 0.996), (0, 100, 0),
    (120, 100, 1), (1, 0, 1), (-1, 100, 1), (double.NaN, 100, 1),
    (double.PositiveInfinity, 100, 1), (1, double.PositiveInfinity, 1), (1, double.NaN, 1) })
    if (ScoreShare.FillRatio(sample.Score, sample.Leader) != sample.Expected)
        throw new Exception("Incorrect score background ratio");

foreach (var sample in new[] {
    (Score: 56d, Leader: 57.6d, Expected: "97%"), (97.5, 100, "98%"), (0, 100, "0%"),
    (100, 100, ""), (99.6, 100, ""), (101, 100, ""), (1, 0, ""), (-1, 100, ""),
    (double.NaN, 100, ""), (1, double.PositiveInfinity, ""), (double.PositiveInfinity, 1, "") })
    if (ScoreShare.Format(sample.Score, sample.Leader) != sample.Expected)
        throw new Exception("Incorrect score share");

foreach (var code in new[] { "CN", "HK", "MO", "TW", " hk ", "mo", "tw", "HKG", "MAC", "TWN", "Hong Kong", "Macao", "Macau", "Taiwan", "香港", "澳门", "澳門", "台湾", "台灣", "臺灣" })
{
    var saved = JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(new { countries = new { arenaText = code } }), AppConfig.Json)!;
    if (saved.Countries["arenaText"] != "china" || LeaderboardCountryPolicy.NormalizeFilter(code) != "china")
        throw new Exception("China country filter migration failed: " + code);
}
if (LeaderboardCountryPolicy.NormalizeFilter("JP") != "JP" || LeaderboardCountryPolicy.NormalizeFilter("unknown") != "unknown")
    throw new Exception("Country migration changed unrelated filters");

// Shared images arrive in the engine response; older engines remain readable.
var brandedEntry = JsonSerializer.Deserialize<Entry>("""
    {"rank":1,"name":"New Model","score":99,"organization":"New Maker","brandColor":"#319FA8","logoPNG":"iVBORw0KGgo=","initials":"N"}
    """, AppConfig.Json)!;
if (brandedEntry.BrandColor != "#319FA8" || brandedEntry.LogoPNG != "iVBORw0KGgo=" || brandedEntry.Initials != "N")
    throw new Exception("Shared brand fields lost in engine protocol");
var legacyEntry = JsonSerializer.Deserialize<Entry>("""{"rank":1,"name":"Old Model","score":99}""", AppConfig.Json)!;
if (legacyEntry.BrandColor is not null || legacyEntry.LogoPNG is not null || legacyEntry.Initials is not null)
    throw new Exception("Legacy engine response cannot require brand fields");

// Stable data timestamps, boundary ages and language forms; rendering alone
// must never fabricate a just-now timestamp from the presence of quota cards.
var ageNow = DateTimeOffset.Parse("2026-10-01T12:00:00Z");
foreach (var sample in new[] {
    (Seconds: 0, En: "just now", Zh: "刚刚", Hant: "剛剛"),
    (Seconds: 59, En: "just now", Zh: "刚刚", Hant: "剛剛"),
    (Seconds: 60, En: "1 min ago", Zh: "1 分钟前", Hant: "1 分鐘前"),
    (Seconds: 3599, En: "59 min ago", Zh: "59 分钟前", Hant: "59 分鐘前"),
    (Seconds: 3600, En: "1 hr ago", Zh: "1 小时前", Hant: "1 小時前"),
    (Seconds: 86399, En: "23 hr ago", Zh: "23 小时前", Hant: "23 小時前"),
    (Seconds: 86400, En: "1 day ago", Zh: "1 天前", Hant: "1 天前"),
    (Seconds: 172800, En: "2 days ago", Zh: "2 天前", Hant: "2 天前") })
{
    var date = ageNow.AddSeconds(-sample.Seconds);
    if (UpdateAge.Format(date, ageNow, "en") != sample.En || UpdateAge.Format(date, ageNow, "zh") != sample.Zh || UpdateAge.Format(date, ageNow, "zh-Hant") != sample.Hant)
        throw new Exception("Incorrect relative update age");
}
if (UpdateAge.Parse("invalid") is not null || UpdateAge.Format(null, ageNow, "zh") != "待更新" ||
    UpdateAge.Format(ageNow.AddSeconds(30), ageNow, "zh") != "刚刚" ||
    UpdateAge.Parse("2026-10-01T20:00:00+08:00") != ageNow) throw new Exception("Incorrect unknown or offset update time");
var oldState = JsonSerializer.Deserialize<DisplayState>("{\"boards\":[],\"quotas\":[],\"quotaNeedsCCSwitch\":false,\"quotaUnavailable\":false,\"alerts\":[]}", AppConfig.Json)!;
if (oldState.QuotaUpdatedAt is not null) throw new Exception("Missing data timestamp must remain unknown");
var recoveryResponse = JsonSerializer.Deserialize<EngineResponse>("""
    {"id":1,"qwenQuotaRefreshNeeded":true,"result":{"boards":[],"quotas":[],"quotaNeedsCCSwitch":false,"quotaUnavailable":false,"alerts":[{"title":"GLM · Quota restored","body":"5h 100%"}]}}
    """, AppConfig.Json)!;
if (recoveryResponse.QwenQuotaRefreshNeeded != true || recoveryResponse.Result?.Alerts.Single().Title != "GLM · Quota restored")
    throw new Exception("Recovery response lost provider identity or website refresh request");
var oldResponse = JsonSerializer.Deserialize<EngineResponse>("{\"id\":2}", AppConfig.Json)!;
if (oldResponse.QwenQuotaRefreshNeeded is not null) throw new Exception("Older responses must not request a website refresh");

var keys = new Ed25519PrivateKeyParameters(new SecureRandom());
var publicKey = Convert.ToBase64String(keys.GeneratePublicKey().GetEncoded());
const string repository = "cloydlau/ai-benchgauge";
var valid = new WindowsUpdate("20261028", "https://github.com/cloydlau/ai-benchgauge/releases/download/v20261028/AI-BenchGauge-20261028-windows-x64-setup.exe", new string('a', 64), 123, "Release notes");
byte[] Encode(WindowsUpdate update) => JsonSerializer.SerializeToUtf8Bytes(update, AppConfig.Json);
string Sign(byte[] data)
{
    var signer = new Ed25519Signer(); signer.Init(true, keys); signer.BlockUpdate(data, 0, data.Length);
    return Convert.ToBase64String(signer.GenerateSignature());
}
void Reject(Action action)
{
    try { action(); } catch (Exception e) when (e is CryptographicException or JsonException or FormatException or ArgumentException) { return; }
    throw new Exception("Accepted invalid update");
}
var bytes = Encode(valid);
if (UpdateClient.Verify(bytes, Sign(bytes), publicKey, repository) != valid) throw new Exception("Could not verify update");
var tampered = bytes.ToArray(); tampered[10] ^= 1;
Reject(() => UpdateClient.Verify(tampered, Sign(bytes), publicKey, repository));
var wrongKey = Convert.ToBase64String(new Ed25519PrivateKeyParameters(new SecureRandom()).GeneratePublicKey().GetEncoded());
Reject(() => UpdateClient.Verify(bytes, Sign(bytes), wrongKey, repository));
Reject(() => UpdateClient.Verify(bytes, Convert.ToBase64String(new byte[63]), publicKey, repository));
foreach (var invalid in new[] {
    valid with { Url = "https://evil.example/installer.exe" }, valid with { Url = valid.Url + "?token=anything" },
    valid with { Version = "1.2.3-beta" }, valid with { Version = "01.2.3" }, valid with { Version = "20260230" },
    valid with { Version = "20261028\n" }, valid with { Length = 0 },
    valid with { Length = 1_073_741_825 }, valid with { Sha256 = "bad" } })
{
    var bad = Encode(invalid); Reject(() => UpdateClient.Verify(bad, Sign(bad), publicKey, repository));
}
var oversized = Encoding.UTF8.GetBytes(new string('x', 65_537));
Reject(() => UpdateClient.Verify(oversized, Sign(oversized), publicKey, repository));
if (AppConfig.Load().Repository != repository) throw new Exception("Wrong embedded repository");
var appAssembly = typeof(AppConfig).Assembly;
var versionInfo = System.Diagnostics.FileVersionInfo.GetVersionInfo(appAssembly.Location);
if (versionInfo.ProductVersion != AppConfig.Load().Version)
    throw new Exception("Windows product version differs from the public date version");
var dateVersion = DateOnly.ParseExact(AppConfig.Load().Version, "yyyyMMdd", System.Globalization.CultureInfo.InvariantCulture);
if (appAssembly.GetName().Version != new Version(dateVersion.Year, dateVersion.Month, dateVersion.Day, 0))
    throw new Exception("Windows assembly version differs from the shared date");
foreach (var (left, right, expected) in new[] {
    ("20261028", "20261027", 1), ("20261028", "20261028", 0), ("20261028", "20261029", -1),
    ("20270101", "20261231", 1), ("20261028", "0.0.0", 1), ("20261028", "1.10.0", 1),
    ("20261028", "2026.10.28", 0), ("1.10.0", "1.9.99", 1) })
    if (Math.Sign(UpdateClient.CompareVersions(left, right)) != expected) throw new Exception("Incorrect date/legacy version ordering");
// Every ordering of download completion, activation, visibility and modal state.
var gateCases = 0;
foreach (var visible in new[] { false, true })
foreach (var active in new[] { false, true })
foreach (var modal in new[] { false, true })
foreach (var closing in new[] { false, true })
{
    var gate = new PreparedUpdate();
    if (gate.TryPresent(visible, active, modal, closing)) throw new Exception("Prompt before download");
    gate.Ready("verified-installer.exe");
    if (gate.Confirm() is not null) throw new Exception("Install before presenting");
    var expected = visible && active && !modal && !closing;
    if (gate.TryPresent(visible, active, modal, closing) != expected) throw new Exception("Incorrect update presentation gate");
    if (expected)
    {
        if (gate.TryPresent(true, true, false, false)) throw new Exception("Duplicate update dialog");
        if (gate.Confirm() != "verified-installer.exe" || gate.Confirm() is not null) throw new Exception("Install must be confirmed once");
        gate.InstallationFailed();
        if (gate.Confirm() != "verified-installer.exe") throw new Exception("Failed installer must be retryable");
    }
    else if (!gate.TryPresent(true, true, false, false)) throw new Exception("Deferred prompt lost after activation");
    gateCases++;
}
var pending = new PreparedUpdate();
pending.Ready("first.exe"); pending.Ready("second.exe");
if (!pending.TryPresent(true, true, false, false) || pending.Confirm() != "first.exe") throw new Exception("Pending installer changed under the dialog");

var fixtureDirectory = Path.Combine(Path.GetTempPath(), "BenchGauge-update-tests-" + Guid.NewGuid());
var installerBytes = Encoding.UTF8.GetBytes("Synthetic installer: must never be executed");
var downloadUpdate = valid with { Length = installerBytes.Length, Sha256 = Convert.ToHexStringLower(SHA256.HashData(installerBytes)) };
var fixtureConfig = new AppConfig("20261027", repository, publicKey);
var downloadCases = 0;
try
{
    var payload = Encode(downloadUpdate);
    using var handler = new FixtureHttpHandler(request => request.RequestUri!.AbsolutePath.EndsWith(".sig")
        ? Encoding.UTF8.GetBytes(Sign(payload)) : request.RequestUri.AbsolutePath.EndsWith(".json") ? payload : installerBytes);
    using var http = new HttpClient(handler);
    var client = new UpdateClient(fixtureConfig, http, fixtureDirectory);
    if (await client.Check() != downloadUpdate) throw new Exception("Higher signed version not detected");
    downloadCases++;
    var file = await client.Download(downloadUpdate);
    if (!File.ReadAllBytes(file).SequenceEqual(installerBytes)) throw new Exception("Verified installer not saved");
    var requests = handler.Requests;
    if (await client.Download(downloadUpdate) != file || handler.Requests != requests) throw new Exception("Verified cache not reused");
    downloadCases++;
    File.WriteAllBytes(file, new byte[installerBytes.Length]);
    await client.Download(downloadUpdate);
    if (!File.ReadAllBytes(file).SequenceEqual(installerBytes) || handler.Requests != requests + 1) throw new Exception("Corrupt cache not replaced");
    downloadCases++;
    var currentClient = new UpdateClient(fixtureConfig with { Version = "20261028" }, http, fixtureDirectory);
    if (await currentClient.Check() is not null) throw new Exception("Same version offered as update");
    var newerClient = new UpdateClient(fixtureConfig with { Version = "20261029" }, http, fixtureDirectory);
    if (await newerClient.Check() is not null) throw new Exception("Rollback offered as update");
    downloadCases += 2;
    File.Delete(file);
    foreach (var badBytes in new[] { new byte[installerBytes.Length], installerBytes[..^1], installerBytes.Concat(new byte[] { 0 }).ToArray() })
    {
        using var badHandler = new FixtureHttpHandler(_ => badBytes);
        using var badHttp = new HttpClient(badHandler);
        try { await new UpdateClient(fixtureConfig, badHttp, fixtureDirectory).Download(downloadUpdate); throw new Exception("Accepted corrupt download"); }
        catch (Exception error) when (error is CryptographicException or IOException) { }
        if (Directory.GetFiles(fixtureDirectory).Length != 0) throw new Exception("Failed download left installer or temporary data");
        downloadCases++;
    }
    using var tamperedHandler = new FixtureHttpHandler(request => request.RequestUri!.AbsolutePath.EndsWith(".sig") ? Encoding.UTF8.GetBytes(Sign(payload)) : tampered);
    using var tamperedHttp = new HttpClient(tamperedHandler);
    try { await new UpdateClient(fixtureConfig, tamperedHttp, fixtureDirectory).Check(); throw new Exception("Accepted tampered live metadata"); }
    catch (CryptographicException) { }
    downloadCases++;
}
finally { if (Directory.Exists(fixtureDirectory)) Directory.Delete(fixtureDirectory, true); }
// The desktop source selection defaults to all three, survives persistence,
// cannot become empty, and keeps separate choices for other categories.
var visibility = new Preferences();
if (!visibility.VisibleBoardKinds().SequenceEqual(new[] { "artificialAnalysis", "arenaText", "epochECI" }))
    throw new Exception("Desktop must default to all three boards");
visibility.ToggleBoard("arenaText"); visibility.ToggleBoard("artificialAnalysis"); visibility.ToggleBoard("epochECI");
if (!visibility.VisibleBoardKinds().SequenceEqual(new[] { "epochECI" })) throw new Exception("Last board was deselected");
visibility = JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(visibility, AppConfig.Json), AppConfig.Json)!;
if (!visibility.VisibleBoardKinds().SequenceEqual(new[] { "epochECI" })) throw new Exception("Board selection did not persist");
visibility.Category = "coding";
if (visibility.VisibleBoardKinds().Length != 2) throw new Exception("Board selections leaked between categories");
visibility.Category = "general"; visibility.ToggleBoard("artificialAnalysis");
if (!visibility.VisibleBoardKinds().SequenceEqual(new[] { "artificialAnalysis", "epochECI" })) throw new Exception("Restored board order is wrong");
foreach (var invalid in new[] { Array.Empty<string>(), new[] { "retired" }, new[] { "arenaTextToImage" } }) {
    visibility.BoardSelections["general"] = invalid;
    if (visibility.VisibleBoardKinds().Length != 3) throw new Exception("Invalid board preferences were not repaired");
}

Console.WriteLine("PASS: desktop board defaults, persistence, minimum selection, category isolation and invalid-preference recovery");
var stagedPreferences = new Preferences();
var draftBoards = stagedPreferences.VisibleBoardKinds().ToHashSet();
draftBoards.Remove("artificialAnalysis"); draftBoards.Remove("arenaText");
if (stagedPreferences.VisibleBoardKinds().Length != 3 || stagedPreferences.BoardSelections.Count != 0)
    throw new Exception("Draft board selection changed preferences before confirmation");
if (!stagedPreferences.SetVisibleBoards(draftBoards) || !stagedPreferences.VisibleBoardKinds().SequenceEqual(new[] { "epochECI" }))
    throw new Exception("Confirmed board selection was not applied as a batch");
if (stagedPreferences.SetVisibleBoards(draftBoards) || stagedPreferences.SetVisibleBoards([]) || stagedPreferences.SetVisibleBoards(["retired"]))
    throw new Exception("Unchanged or invalid selections should not trigger a refresh");
if (!stagedPreferences.SetVisibleBoards(["epochECI", "artificialAnalysis", "epochECI"]) ||
    !stagedPreferences.VisibleBoardKinds().SequenceEqual(new[] { "artificialAnalysis", "epochECI" }))
    throw new Exception("Batch board selection must retain catalog order and remove duplicates");
Console.WriteLine("PASS: desktop board draft isolation and confirmed batch selection");

Console.WriteLine($"PASS: 13 signature/configuration cases, {gateCases + 1} update presentation cases, {downloadCases} signed check/download/cache/integrity cases");

var usageVisibility = new Preferences { Category = "usage" };
if (!usageVisibility.AvailableBoardKinds().SequenceEqual(new[] { "openRouterUsage", "vercelUsage", "cloudbaseUsage" }) || !usageVisibility.VisibleBoardKinds().SequenceEqual(new[] { "openRouterUsage", "vercelUsage", "cloudbaseUsage" }))
    throw new Exception("Usage must expose all three sources separately");
usageVisibility.ToggleBoard("openRouterUsage");
if (!usageVisibility.VisibleBoardKinds().SequenceEqual(new[] { "vercelUsage", "cloudbaseUsage" })) throw new Exception("Vercel and Tencent remain selected when OpenRouter is hidden");

foreach (var language in new[] { "en", "zh", "zh-Hant" }) {
    var fallback = UsageLicense.Text("vercelUsage", null, language);
    if (!fallback.Contains("© 2026 Vercel") || !fallback.Contains("creativecommons.org/licenses/by/4.0") || fallback.Length < 1000)
        throw new Exception("Vercel offline credit and localized full license must be bundled");
    if (!UsageLicense.Text("vercelUsage", "Cached Vercel date", language).StartsWith("Cached Vercel date\n\n"))
        throw new Exception("Vercel agreement must retain the current snapshot provenance");
    var license = UsageLicense.FullLicense(language);
    if (!fallback.EndsWith(license) || !UsageLicense.Text("openRouterUsage", "Current OpenRouter credit", language).EndsWith(license)
        || !UsageLicense.Text("openRouterUsage", "Current OpenRouter credit", language).StartsWith("Current OpenRouter credit\n\n"))
        throw new Exception("Source-name agreements must include the complete localized offline license and their own credit");
}
usageVisibility.BoardSelections["usage"] = ["cloudbaseUsage"];
if (!usageVisibility.VisibleBoardKinds().SequenceEqual(new[] { "cloudbaseUsage" })) throw new Exception("Restored Tencent selection must be retained");
Console.WriteLine("PASS: Vercel cached credit and offline full license in all three languages");


foreach (var language in new[] { "en", "zh", "zh-Hant" }) {
    var notice = UsageLicense.Text("cloudbaseUsage", "Cached Tencent provenance", language);
    if (!notice.Contains("Cached Tencent provenance") || notice.Contains("creativecommons.org/licenses"))
        throw new Exception("CloudBase source notice must remain offline and must not grant a Creative Commons license");
}
Console.WriteLine("PASS: CloudBase source notice in all three languages");

sealed class FixtureHttpHandler(Func<HttpRequestMessage, byte[]> response) : HttpMessageHandler
{
    public int Requests { get; private set; }
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests++;
        return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK) { Content = new ByteArrayContent(response(request)) });
    }
}
